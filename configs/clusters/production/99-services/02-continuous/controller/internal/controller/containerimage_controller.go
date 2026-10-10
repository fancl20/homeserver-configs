// Package controller reconciles ContainerImages into buildkit Jobs.
package controller

import (
	"context"
	"sort"
	"strconv"
	"strings"
	"time"

	batchv1 "k8s.io/api/batch/v1"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/equality"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/client-go/tools/events"
	"k8s.io/utils/ptr"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"

	fluxmeta "github.com/fluxcd/pkg/apis/meta"

	"image-controller/api/v1alpha1"
	"image-controller/internal/build"
	"image-controller/internal/config"
	"image-controller/internal/status"
)

const (
	// Finalizer deletes build Jobs when a ContainerImage is deleted.
	Finalizer = "image-controller.d20.fan/builds"

	// SourceRefIndex and BaseRefIndex are cache field indexes over the CR
	// specs, keyed "<namespace>/<name>".
	SourceRefIndex = "spec.sourceRef"
	BaseRefIndex   = "spec.baseRef"
)

// ContainerImageReconciler drives the ContainerImage state machine. It never
// builds anything itself: it creates Jobs and reads their termination
// messages back, so the build pod needs no RBAC at all.
//
// +kubebuilder:rbac:groups=d20.fan,resources=containerimages,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=d20.fan,resources=containerimages/status;containerimages/finalizers,verbs=get;update;patch
// +kubebuilder:rbac:groups=source.toolkit.fluxcd.io,resources=gitrepositories,verbs=get;list;watch
// +kubebuilder:rbac:groups=image.toolkit.fluxcd.io,resources=imagepolicies,verbs=get;list;watch
// +kubebuilder:rbac:groups=batch,resources=jobs,verbs=get;list;watch;create;delete;deletecollection
// +kubebuilder:rbac:groups="",resources=pods,verbs=get;list;watch
// +kubebuilder:rbac:groups="";events.k8s.io,resources=events,verbs=create;patch
type ContainerImageReconciler struct {
	client.Client
	Scheme   *runtime.Scheme
	Recorder events.EventRecorder
	Config   *config.Config

	// Clock is injectable for tests.
	Clock func() time.Time
}

func (r *ContainerImageReconciler) now() time.Time {
	if r.Clock != nil {
		return r.Clock()
	}
	return time.Now()
}

// Reconcile runs the trigger matrix and manages the build Job lifecycle.
func (r *ContainerImageReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	ci := &v1alpha1.ContainerImage{}
	if err := r.Get(ctx, req.NamespacedName, ci); err != nil {
		return ctrl.Result{}, client.IgnoreNotFound(err)
	}

	if !ci.DeletionTimestamp.IsZero() {
		return r.finalize(ctx, ci)
	}
	if !controllerutil.ContainsFinalizer(ci, Finalizer) {
		patch := client.MergeFrom(ci.DeepCopy())
		controllerutil.AddFinalizer(ci, Finalizer)
		if err := r.Patch(ctx, ci, patch); err != nil {
			return ctrl.Result{}, err
		}
		return ctrl.Result{Requeue: true}, nil
	}

	if ci.Spec.Suspend {
		err := r.updateStatus(ctx, ci, func() {
			ci.Status.ObservedGeneration = ci.Generation
			status.Mark(ci, metav1.ConditionFalse, status.ReasonSuspended, "reconciliation suspended")
		})
		return ctrl.Result{}, err
	}

	if message := ValidateSpec(&ci.Spec); message != "" {
		err := r.updateStatus(ctx, ci, func() {
			ci.Status.ObservedGeneration = ci.Generation
			status.Mark(ci, metav1.ConditionFalse, status.ReasonInvalidSpec, message)
		})
		return ctrl.Result{RequeueAfter: 5 * time.Minute}, err
	}

	artifact, err := sourceArtifact(ctx, r.Client, ci)
	if err != nil {
		if isNotFound(err) {
			message := err.Error()
			err = r.updateStatus(ctx, ci, func() {
				ci.Status.ObservedGeneration = ci.Generation
				status.Mark(ci, metav1.ConditionFalse, status.ReasonArtifactMissing, message)
			})
			return ctrl.Result{RequeueAfter: ci.Spec.Interval.Duration}, err
		}
		return ctrl.Result{}, err
	}

	baseTag := ""
	if ci.Spec.BaseRef != nil {
		baseTag, err = resolveBaseTag(ctx, r.Client, ci)
		if err != nil {
			if isNotFound(err) {
				message := err.Error()
				err = r.updateStatus(ctx, ci, func() {
					ci.Status.ObservedGeneration = ci.Generation
					status.Mark(ci, metav1.ConditionFalse, status.ReasonBaseNotReady, message)
				})
				return ctrl.Result{RequeueAfter: ci.Spec.Interval.Duration}, err
			}
			return ctrl.Result{}, err
		}
	}

	now := r.now()
	trigger := EvaluateTrigger(ci, artifact.Revision, baseTag, now)

	job, jobsErr := r.pickJob(ctx, ci)
	if jobsErr != nil {
		return ctrl.Result{}, jobsErr
	}

	if job != nil && jobComplete(job) {
		return r.processCompletion(ctx, ci, job)
	}
	if job != nil && jobFailed(job) {
		return r.processFailure(ctx, ci, job)
	}

	_, pendingKey, attempts := r.triggerKeys(ci, trigger, artifact.Revision, baseTag)

	if job != nil {
		if trigger != nil && job.Annotations[build.AnnTriggerKey] != pendingKey {
			// Replace semantics, mirroring the Argo CronWorkflow's
			// concurrencyPolicy: the pending trigger wins.
			if err := r.Delete(ctx, job, client.PropagationPolicy(metav1.DeletePropagationBackground)); err != nil && !apierrors.IsNotFound(err) {
				return ctrl.Result{}, err
			}
			r.Recorder.Eventf(ci, job, corev1.EventTypeNormal, status.EventBuildSuperseded,
				"Supersede", "Job %s superseded by %s trigger", job.Name, trigger.Cause)
		} else {
			err := r.updateStatus(ctx, ci, func() {
				r.observe(ci, artifact.Revision)
				ci.Status.CurrentJob = job.Name
				ci.Status.BuildAttempts = attempts
				status.Mark(ci, metav1.ConditionFalse, status.ReasonBuildProgressing,
					"Job "+job.Name+" running")
			})
			return ctrl.Result{RequeueAfter: r.requeueAfter(ci, now)}, err
		}
	}

	if trigger == nil {
		var untilNext time.Duration
		err := r.updateStatus(ctx, ci, func() {
			r.observe(ci, artifact.Revision)
			untilNext = r.seedNextSchedule(ci, now)
			switch {
			case ci.Status.BuildAttempts >= r.Config.MaxAttempts:
				// A burned-out trigger (e.g. a schedule tick whose attempts
				// were exhausted and whose next tick is now seeded) must not
				// be repainted as Ready from the stale lastImageRef.
				status.Mark(ci, metav1.ConditionFalse, status.ReasonBuildFailed,
					"giving up after "+strconv.Itoa(ci.Status.BuildAttempts)+
						" attempts; request a manual rebuild")
			case ci.Status.BuildAttempts > 0:
				// Unreachable in practice — a trigger survives its build
				// failures — but never paper over an outstanding failure.
				status.Mark(ci, metav1.ConditionFalse, status.ReasonBuildFailed,
					"last build failed; waiting for the next trigger")
			default:
				message := "no pending build"
				if ci.Status.LastImageRef != "" {
					message = "pushed " + ci.Status.LastImageRef
				}
				status.Mark(ci, metav1.ConditionTrue, status.ReasonBuildSucceeded, message)
			}
		})
		return ctrl.Result{RequeueAfter: minDuration(ci.Spec.Interval.Duration, untilNext)}, err
	}

	return r.createJob(ctx, ci, trigger, artifact, baseTag, now)
}

// observe records the generation and artifact revision being reconciled.
func (r *ContainerImageReconciler) observe(ci *v1alpha1.ContainerImage, revision string) {
	ci.Status.ObservedGeneration = ci.Generation
	ci.Status.ObservedArtifactRevision = revision
}

// triggerKeys computes the base trigger key (attempts reset when it changes)
// and the full key naming the Job for the current attempt.
func (r *ContainerImageReconciler) triggerKeys(ci *v1alpha1.ContainerImage, trigger *Trigger, revision, baseTag string) (baseKey, fullKey string, attempts int) {
	if trigger == nil {
		return "", "", ci.Status.BuildAttempts
	}
	specHash := build.SpecHash(ci.Spec)
	baseKey = build.TriggerKey(ci.Namespace, ci.Name, specHash, revision, baseTag, trigger.Token, 0)
	attempts = ci.Status.BuildAttempts
	if baseKey != ci.Status.LastTriggerKey {
		attempts = 0
	}
	fullKey = build.TriggerKey(ci.Namespace, ci.Name, specHash, revision, baseTag, trigger.Token, attempts)
	return baseKey, fullKey, attempts
}

// createJob starts a build for the pending trigger. Triggers are consumed on
// success (in processCompletion), not here: a manual or schedule build that
// fails keeps its trigger pending, so the retry budget applies and the
// BuildFailed condition is never repainted as Ready from a stale image ref.
func (r *ContainerImageReconciler) createJob(ctx context.Context, ci *v1alpha1.ContainerImage, trigger *Trigger, artifact *fluxmeta.Artifact, baseTag string, now time.Time) (ctrl.Result, error) {
	baseKey, fullKey, attempts := r.triggerKeys(ci, trigger, artifact.Revision, baseTag)

	if attempts >= r.Config.MaxAttempts {
		message := "giving up after " + strconv.Itoa(attempts) + " attempts; request a manual rebuild"
		var untilNext time.Duration
		err := r.updateStatus(ctx, ci, func() {
			r.observe(ci, artifact.Revision)
			// Advance a due schedule so its next tick starts a fresh attempt
			// budget (a new trigger token) instead of re-entering give-up on
			// every interval.
			if trigger.Cause == TriggerSchedule {
				untilNext = r.seedNextSchedule(ci, now)
			}
			status.Mark(ci, metav1.ConditionFalse, status.ReasonBuildFailed, message)
		})
		return ctrl.Result{RequeueAfter: minDuration(ci.Spec.Interval.Duration, untilNext)}, err
	}

	job := build.BuildJob(build.JobInput{
		ContainerImage: ci,
		TriggerKey:     fullKey,
		SpecHash:       build.SpecHash(ci.Spec),
		ArtifactURL:    artifact.URL,
		ArtifactDigest: artifact.Digest,
		ArtifactRev:    artifact.Revision,
		BaseTag:        baseTag,
		BuildKitImage:  buildKitImage(ctx, r.Client, r.Config),
		Config:         r.Config,
		Now:            now,
	})
	if err := r.Create(ctx, job); err != nil {
		if apierrors.IsAlreadyExists(err) {
			err = r.updateStatus(ctx, ci, func() {
				ci.Status.CurrentJob = job.Name
				status.Mark(ci, metav1.ConditionFalse, status.ReasonBuildProgressing, "Job "+job.Name+" running")
			})
			return ctrl.Result{Requeue: true}, err
		}
		return ctrl.Result{}, err
	}

	r.Recorder.Eventf(ci, nil, corev1.EventTypeNormal, status.EventBuildStarted,
		"Build", "building %s/%s from %s (%s trigger)", r.Config.RegistryHost, ci.Spec.Image,
		build.ShortSHA(artifact.Revision), trigger.Cause)

	if err := r.updateStatus(ctx, ci, func() {
		r.observe(ci, artifact.Revision)
		ci.Status.CurrentJob = job.Name
		ci.Status.LastTriggerKey = baseKey
		ci.Status.BuildAttempts = attempts
		ci.Status.LastBuildStartTime = ptr.To(metav1.NewTime(now))
		status.Mark(ci, metav1.ConditionFalse, status.ReasonBuildProgressing, "Job "+job.Name+" running")
	}); err != nil {
		return ctrl.Result{}, err
	}
	return ctrl.Result{RequeueAfter: r.requeueAfter(ci, now)}, nil
}

// processCompletion copies a succeeded Job's result into the status. The
// pushed reference arrives via the build container's termination message.
func (r *ContainerImageReconciler) processCompletion(ctx context.Context, ci *v1alpha1.ContainerImage, job *batchv1.Job) (ctrl.Result, error) {
	message, exitCode, ok := r.terminationMessage(ctx, job)
	if !ok {
		// The Job is Complete but its pod has not reported yet; try again
		// shortly instead of guessing.
		return ctrl.Result{RequeueAfter: 10 * time.Second}, nil
	}
	if exitCode != 0 {
		return r.processFailure(ctx, ci, job)
	}
	ref := message
	tag := ref
	if i := strings.LastIndexByte(ref, ':'); i >= 0 {
		tag = ref[i+1:]
	}

	now := r.now()
	var untilNext time.Duration
	err := r.updateStatus(ctx, ci, func() {
		ci.Status.LastBuiltRevision = job.Annotations[build.AnnArtifactRevision]
		ci.Status.LastBaseTag = job.Annotations[build.AnnBaseTag]
		ci.Status.LastSpecHash = job.Annotations[build.AnnSpecHash]
		ci.Status.LastTag = tag
		ci.Status.LastImageRef = ref
		ci.Status.LastBuildCompletionTime = job.Status.CompletionTime
		ci.Status.CurrentJob = ""
		ci.Status.BuildAttempts = 0
		// Consume the manual request now that a build succeeded; the
		// annotations mirror the Job's inputs, so a spec or revision that
		// changed mid-build is not falsely recorded as built.
		if requested := manualRequested(ci); requested != "" {
			ci.Status.LastHandledReconcileAt = requested
		}
		untilNext = r.seedNextSchedule(ci, now)
		status.Mark(ci, metav1.ConditionTrue, status.ReasonBuildSucceeded, "pushed "+ref)
	})
	if err == nil {
		r.Recorder.Eventf(ci, nil, corev1.EventTypeNormal, status.EventBuildSucceeded, "Build", "pushed %s", ref)
	}
	return ctrl.Result{RequeueAfter: minDuration(ci.Spec.Interval.Duration, untilNext)}, err
}

// processFailure records a failed Job, deletes it, and backs off. Artifact
// fetch or digest failures also clear the last built revision so the retry
// targets the current artifact (source-controller GCs old revisions fast).
func (r *ContainerImageReconciler) processFailure(ctx context.Context, ci *v1alpha1.ContainerImage, job *batchv1.Job) (ctrl.Result, error) {
	message, _, _ := r.terminationMessage(ctx, job)
	if message == "" {
		message = "Job " + job.Name + " failed"
	}

	err := r.updateStatus(ctx, ci, func() {
		ci.Status.BuildAttempts++
		ci.Status.CurrentJob = ""
		if strings.Contains(message, "artifact fetch failed") || strings.Contains(message, "digest mismatch") {
			ci.Status.LastBuiltRevision = ""
		}
		status.Mark(ci, metav1.ConditionFalse, status.ReasonBuildFailed, message)
	})
	if err != nil {
		return ctrl.Result{}, err
	}
	r.Recorder.Eventf(ci, nil, corev1.EventTypeWarning, status.EventBuildFailed, "Build", "%s", message)

	// Jobs are immutable: delete so the retried attempt (with a bumped
	// attempts component in its name) can be created.
	if err := r.Delete(ctx, job, client.PropagationPolicy(metav1.DeletePropagationBackground)); client.IgnoreNotFound(err) != nil {
		return ctrl.Result{}, err
	}

	attempts := ci.Status.BuildAttempts
	if attempts >= r.Config.MaxAttempts {
		return ctrl.Result{RequeueAfter: ci.Spec.Interval.Duration}, nil
	}
	backoff := time.Minute
	for i := 1; i < attempts && backoff < 30*time.Minute; i++ {
		backoff *= 2
	}
	return ctrl.Result{RequeueAfter: backoff}, nil
}

// terminationMessage reads the build container's termination message from the
// Job's pod. ok is false while the pod has not terminated yet. On success the
// message is the pushed image reference; on failure it is the log tail
// (terminationMessagePolicy: FallbackToLogsOnError). A failed prepare init
// container (artifact fetch, digest mismatch) reports through its own
// termination message — the failure markers live there, since the build
// container never started.
func (r *ContainerImageReconciler) terminationMessage(ctx context.Context, job *batchv1.Job) (message string, exitCode int32, ok bool) {
	pods := &corev1.PodList{}
	if err := r.List(ctx, pods,
		client.InNamespace(job.Namespace),
		client.MatchingLabels{"job-name": job.Name}); err != nil {
		return "", 0, false
	}
	for i := range pods.Items {
		for _, cs := range pods.Items[i].Status.ContainerStatuses {
			if cs.Name != "build" || cs.State.Terminated == nil {
				continue
			}
			return cs.State.Terminated.Message, cs.State.Terminated.ExitCode, true
		}
		for _, cs := range pods.Items[i].Status.InitContainerStatuses {
			// Only failures: a successful prepare writes no termination
			// message, and the build container above owns the success path.
			if cs.Name != "prepare" || cs.State.Terminated == nil || cs.State.Terminated.ExitCode == 0 {
				continue
			}
			return cs.State.Terminated.Message, cs.State.Terminated.ExitCode, true
		}
	}
	return "", 0, false
}

// pickJob selects the Job to reconcile: the one named in status.currentJob,
// else the newest active or unprocessed Job (adopting orphans left by a
// controller crash between Job creation and the status update).
func (r *ContainerImageReconciler) pickJob(ctx context.Context, ci *v1alpha1.ContainerImage) (*batchv1.Job, error) {
	jobs := &batchv1.JobList{}
	if err := r.List(ctx, jobs,
		client.InNamespace(r.Config.BuildNamespace),
		client.MatchingLabels{build.LabelContainerImage: build.ContainerImageLabel(ci)}); err != nil {
		return nil, err
	}
	items := make([]batchv1.Job, 0, len(jobs.Items))
	items = append(items, jobs.Items...)
	sort.Slice(items, func(i, j int) bool {
		a, b := items[i].CreationTimestamp, items[j].CreationTimestamp
		if a.Equal(&b) {
			return items[i].Name > items[j].Name
		}
		return a.After(b.Time)
	})

	if ci.Status.CurrentJob != "" {
		for i := range items {
			if items[i].Name == ci.Status.CurrentJob {
				return &items[i], nil
			}
		}
	}
	for i := range items {
		job := &items[i]
		if !jobComplete(job) && !jobFailed(job) {
			return job, nil // active
		}
		if jobComplete(job) && unprocessedCompletion(job, ci) {
			return job, nil
		}
		// Failed orphans (a crash between the status update and the Job
		// delete) stay put until their TTL cleans them up; the retried
		// attempt gets a fresh name.
	}
	return nil, nil
}

func unprocessedCompletion(job *batchv1.Job, ci *v1alpha1.ContainerImage) bool {
	last := ci.Status.LastBuildCompletionTime
	return last == nil ||
		(job.Status.CompletionTime != nil && job.Status.CompletionTime.After(last.Time))
}

func jobComplete(job *batchv1.Job) bool { return jobCondition(job, batchv1.JobComplete) }

func jobFailed(job *batchv1.Job) bool { return jobCondition(job, batchv1.JobFailed) }

func jobCondition(job *batchv1.Job, conditionType batchv1.JobConditionType) bool {
	for _, condition := range job.Status.Conditions {
		if condition.Type == conditionType && condition.Status == corev1.ConditionTrue {
			return true
		}
	}
	return false
}

// finalize removes the build Jobs before the ContainerImage goes away.
func (r *ContainerImageReconciler) finalize(ctx context.Context, ci *v1alpha1.ContainerImage) (ctrl.Result, error) {
	if !controllerutil.ContainsFinalizer(ci, Finalizer) {
		return ctrl.Result{}, nil
	}
	jobs := &batchv1.JobList{}
	if err := r.List(ctx, jobs,
		client.InNamespace(r.Config.BuildNamespace),
		client.MatchingLabels{build.LabelContainerImage: build.ContainerImageLabel(ci)}); err != nil {
		return ctrl.Result{}, err
	}
	if len(jobs.Items) > 0 {
		if err := r.DeleteAllOf(ctx, &batchv1.Job{},
			client.InNamespace(r.Config.BuildNamespace),
			client.MatchingLabels{build.LabelContainerImage: build.ContainerImageLabel(ci)}); err != nil {
			return ctrl.Result{}, err
		}
		return ctrl.Result{Requeue: true, RequeueAfter: 5 * time.Second}, nil
	}
	patch := client.MergeFrom(ci.DeepCopy())
	controllerutil.RemoveFinalizer(ci, Finalizer)
	return ctrl.Result{}, r.Patch(ctx, ci, patch)
}

// seedNextSchedule computes and records the next schedule tick, returning the
// duration until it (0 when unscheduled).
func (r *ContainerImageReconciler) seedNextSchedule(ci *v1alpha1.ContainerImage, from time.Time) time.Duration {
	if ci.Spec.Schedule == "" {
		return 0
	}
	next, err := NextScheduleRun(ci.Spec.Schedule, ci.Spec.TimeZone, r.Config.Location, from)
	if err != nil {
		return 0
	}
	ci.Status.NextScheduleRun = ptr.To(metav1.NewTime(next))
	return time.Until(next)
}

// requeueAfter returns the sooner of the interval and the next schedule tick.
func (r *ContainerImageReconciler) requeueAfter(ci *v1alpha1.ContainerImage, now time.Time, untilNext ...time.Duration) time.Duration {
	result := ci.Spec.Interval.Duration
	for _, d := range untilNext {
		result = minDuration(result, d)
	}
	if ci.Spec.Schedule != "" && ci.Status.NextScheduleRun != nil {
		result = minDuration(result, time.Until(ci.Status.NextScheduleRun.Time))
	}
	if result < 10*time.Second {
		result = 10 * time.Second
	}
	return result
}

func minDuration(a, b time.Duration) time.Duration {
	if a <= 0 {
		return b
	}
	if b <= 0 || a < b {
		return a
	}
	return b
}

func (r *ContainerImageReconciler) updateStatus(ctx context.Context, ci *v1alpha1.ContainerImage, mutate func()) error {
	base := ci.DeepCopy()
	mutate()
	if equality.Semantic.DeepEqual(base.Status, ci.Status) {
		return nil
	}
	return r.Status().Patch(ctx, ci, client.MergeFrom(base))
}

// RegisterIndexes sets up the cache field indexes used by the watch mappers.
func RegisterIndexes(mgr ctrl.Manager) error {
	if err := mgr.GetFieldIndexer().IndexField(context.Background(), &v1alpha1.ContainerImage{}, SourceRefIndex,
		func(obj client.Object) []string {
			ref := obj.(*v1alpha1.ContainerImage).Spec.SourceRef
			namespace := ref.Namespace
			if namespace == "" {
				namespace = "flux-system"
			}
			return []string{namespace + "/" + ref.Name}
		}); err != nil {
		return err
	}
	return mgr.GetFieldIndexer().IndexField(context.Background(), &v1alpha1.ContainerImage{}, BaseRefIndex,
		func(obj client.Object) []string {
			ref := obj.(*v1alpha1.ContainerImage).Spec.BaseRef
			if ref == nil {
				return nil
			}
			namespace := ref.Namespace
			if namespace == "" {
				namespace = "flux-system"
			}
			return []string{namespace + "/" + ref.Name}
		})
}

// statusNamespacedName is used by the watch mappers.
func statusNamespacedName(ci *v1alpha1.ContainerImage) types.NamespacedName {
	return types.NamespacedName{Namespace: ci.Namespace, Name: ci.Name}
}
