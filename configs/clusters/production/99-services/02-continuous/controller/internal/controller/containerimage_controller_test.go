package controller

import (
	"context"
	"testing"
	"time"

	imagev1 "github.com/fluxcd/image-reflector-controller/api/v1"
	sourcev1 "github.com/fluxcd/source-controller/api/v1"
	batchv1 "k8s.io/api/batch/v1"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	clientgoscheme "k8s.io/client-go/kubernetes/scheme"
	"k8s.io/client-go/tools/events"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"
	"sigs.k8s.io/controller-runtime/pkg/reconcile"

	fluxmeta "github.com/fluxcd/pkg/apis/meta"

	"image-controller/api/v1alpha1"
	"image-controller/internal/build"
	"image-controller/internal/config"
)

const (
	testRevision = "main@sha1:8fdae8812345678"
	testBaseTag  = "testing-20260824"
)

func testScheme(t *testing.T) *runtime.Scheme {
	t.Helper()
	scheme := runtime.NewScheme()
	for _, add := range []func(*runtime.Scheme) error{
		clientgoscheme.AddToScheme,
		v1alpha1.AddToScheme,
		sourcev1.AddToScheme,
		imagev1.AddToScheme,
	} {
		if err := add(scheme); err != nil {
			t.Fatal(err)
		}
	}
	return scheme
}

func testSetup(t *testing.T, objects ...client.Object) (*ContainerImageReconciler, client.Client) {
	t.Helper()
	cfg := &config.Config{
		RegistryHost:            "registry.local.d20.fan",
		BuildNamespace:          "continuous",
		Location:                time.UTC,
		PrepareImage:            "docker.io/library/python:3.14.2-slim",
		BuildKitRepo:            "docker.io/moby/buildkit",
		BuildKitPolicyNamespace: "flux-system",
		BuildKitPolicyName:      "buildkit",
		BuildKitFallbackImage:   "docker.io/moby/buildkit:v0.32.2-rootless",
		JobTTL:                  24 * time.Hour,
		JobTimeout:              time.Hour,
		MaxAttempts:             3,
	}
	c := fake.NewClientBuilder().
		WithScheme(testScheme(t)).
		WithStatusSubresource(
			&v1alpha1.ContainerImage{},
			&sourcev1.GitRepository{},
			&imagev1.ImagePolicy{},
			&batchv1.Job{},
		).
		WithObjects(objects...).
		Build()
	r := &ContainerImageReconciler{
		Client:   c,
		Scheme:   c.Scheme(),
		Recorder: events.NewFakeRecorder(32),
		Config:   cfg,
		Clock:    func() time.Time { return time.Date(2026, 8, 31, 3, 0, 0, 0, time.UTC) },
	}
	return r, c
}

func sourceObjects() []client.Object {
	return []client.Object{
		&sourcev1.GitRepository{
			ObjectMeta: metav1.ObjectMeta{Name: "configs", Namespace: "flux-system"},
			Status: sourcev1.GitRepositoryStatus{
				Artifact: &fluxmeta.Artifact{
					Revision: testRevision,
					Digest:   "sha256:abc123",
					URL:      "http://source-controller.flux-system.svc.cluster.local./gitrepository/flux-system/configs/latest.tar.gz",
				},
			},
		},
		&imagev1.ImagePolicy{
			ObjectMeta: metav1.ObjectMeta{Name: "debian", Namespace: "flux-system"},
			Status: imagev1.ImagePolicyStatus{
				LatestRef: &imagev1.ImageRef{
					Name: "docker.io/library/debian",
					Tag:  testBaseTag,
				},
			},
		},
	}
}

func testCR(mutate func(*v1alpha1.ContainerImage)) *v1alpha1.ContainerImage {
	ci := triggerCI(mutate)
	ci.Finalizers = []string{Finalizer}
	return ci
}

func doReconcile(t *testing.T, r *ContainerImageReconciler, ci *v1alpha1.ContainerImage) reconcile.Result {
	t.Helper()
	result, err := r.Reconcile(context.Background(), reconcile.Request{
		NamespacedName: types.NamespacedName{Namespace: ci.Namespace, Name: ci.Name},
	})
	if err != nil {
		t.Fatalf("reconcile: %v", err)
	}
	return result
}

func refresh(t *testing.T, c client.Client, ci *v1alpha1.ContainerImage) *v1alpha1.ContainerImage {
	t.Helper()
	if err := c.Get(context.Background(), client.ObjectKeyFromObject(ci), ci); err != nil {
		t.Fatal(err)
	}
	return ci
}

func jobsOf(t *testing.T, c client.Client) []batchv1.Job {
	t.Helper()
	list := &batchv1.JobList{}
	if err := c.List(context.Background(), list, client.InNamespace("continuous")); err != nil {
		t.Fatal(err)
	}
	return list.Items
}

func readyCondition(ci *v1alpha1.ContainerImage) *metav1.Condition {
	for i := range ci.Status.Conditions {
		if ci.Status.Conditions[i].Type == "Ready" {
			return &ci.Status.Conditions[i]
		}
	}
	return nil
}

func TestReconcileCreatesJobOnFirstObservation(t *testing.T) {
	ci := testCR(nil)
	r, c := testSetup(t, append(sourceObjects(), ci)...)

	doReconcile(t, r, ci)
	ci = refresh(t, c, ci)

	jobs := jobsOf(t, c)
	if len(jobs) != 1 {
		t.Fatalf("want 1 job, got %d", len(jobs))
	}
	job := jobs[0]
	if job.Labels[build.LabelContainerImage] != "continuous.dae" {
		t.Fatalf("job label = %q", job.Labels[build.LabelContainerImage])
	}
	if ci.Status.CurrentJob != job.Name {
		t.Fatalf("currentJob = %q, want %q", ci.Status.CurrentJob, job.Name)
	}
	cond := readyCondition(ci)
	if cond == nil || cond.Status != metav1.ConditionFalse || cond.Reason != "BuildProgressing" {
		t.Fatalf("condition = %+v", cond)
	}
	if ci.Status.ObservedArtifactRevision != testRevision {
		t.Fatalf("observed revision = %q", ci.Status.ObservedArtifactRevision)
	}

	// Idempotent: a second reconcile with no new trigger creates no second
	// Job and does not error.
	doReconcile(t, r, ci)
	if got := len(jobsOf(t, c)); got != 1 {
		t.Fatalf("want still 1 job, got %d", got)
	}
}

func TestReconcileSuspended(t *testing.T) {
	ci := testCR(func(ci *v1alpha1.ContainerImage) { ci.Spec.Suspend = true })
	r, c := testSetup(t, append(sourceObjects(), ci)...)

	doReconcile(t, r, ci)
	ci = refresh(t, c, ci)

	if got := len(jobsOf(t, c)); got != 0 {
		t.Fatalf("suspended CR must not create jobs, got %d", got)
	}
	if cond := readyCondition(ci); cond == nil || cond.Reason != "Suspended" {
		t.Fatalf("condition = %+v", cond)
	}
}

func TestReconcileMissingSource(t *testing.T) {
	ci := testCR(nil)
	r, c := testSetup(t, ci) // no GitRepository

	doReconcile(t, r, ci)
	ci = refresh(t, c, ci)
	if cond := readyCondition(ci); cond == nil || cond.Reason != "ArtifactMissing" {
		t.Fatalf("condition = %+v", cond)
	}
}

func TestReconcileJobSuccess(t *testing.T) {
	ci := testCR(nil)
	r, c := testSetup(t, append(sourceObjects(), ci)...)

	doReconcile(t, r, ci)
	jobs := jobsOf(t, c)
	if len(jobs) != 1 {
		t.Fatalf("want 1 job, got %d", len(jobs))
	}
	job := jobs[0]

	// Simulate the Job completing and its pod reporting the pushed ref via
	// the termination message.
	completionTime := metav1.Now()
	job.Status.Conditions = []batchv1.JobCondition{{Type: batchv1.JobComplete, Status: corev1.ConditionTrue}}
	job.Status.CompletionTime = &completionTime
	if err := c.Status().Update(context.Background(), &job); err != nil {
		t.Fatal(err)
	}
	pod := &corev1.Pod{
		ObjectMeta: metav1.ObjectMeta{
			Name:      job.Name + "-pod",
			Namespace: "continuous",
			Labels:    map[string]string{"job-name": job.Name},
		},
		Status: corev1.PodStatus{
			ContainerStatuses: []corev1.ContainerStatus{{
				Name: "build",
				State: corev1.ContainerState{
					Terminated: &corev1.ContainerStateTerminated{
						ExitCode: 0,
						Message:  "registry.local.d20.fan/fancl20/dae:2.0.2-" + testBaseTag,
					},
				},
			}},
		},
	}
	if err := c.Create(context.Background(), pod); err != nil {
		t.Fatal(err)
	}

	doReconcile(t, r, ci)
	ci = refresh(t, c, ci)

	if cond := readyCondition(ci); cond == nil || cond.Reason != "BuildSucceeded" || cond.Status != metav1.ConditionTrue {
		t.Fatalf("condition = %+v", cond)
	}
	if ci.Status.LastTag != "2.0.2-"+testBaseTag {
		t.Fatalf("lastTag = %q", ci.Status.LastTag)
	}
	if ci.Status.LastBuiltRevision != testRevision {
		t.Fatalf("lastBuiltRevision = %q", ci.Status.LastBuiltRevision)
	}
	if ci.Status.CurrentJob != "" {
		t.Fatalf("currentJob = %q, want cleared", ci.Status.CurrentJob)
	}
	if ci.Status.BuildAttempts != 0 {
		t.Fatalf("buildAttempts = %d", ci.Status.BuildAttempts)
	}

	// Re-delivery of the same completed Job is not reprocessed.
	doReconcile(t, r, ci)
	ci = refresh(t, c, ci)
	if ci.Status.CurrentJob != "" || readyCondition(ci).Reason != "BuildSucceeded" {
		t.Fatal("completed job must not be reprocessed")
	}
}

func TestReconcileJobFailureRetriesAndSelfHealsArtifactGC(t *testing.T) {
	ci := testCR(func(ci *v1alpha1.ContainerImage) {
		ci.Status.LastBuiltRevision = "main@sha1:older"
	})
	r, c := testSetup(t, append(sourceObjects(), ci)...)

	doReconcile(t, r, ci)
	jobs := jobsOf(t, c)
	if len(jobs) != 1 {
		t.Fatalf("want 1 job, got %d", len(jobs))
	}
	job := jobs[0]

	job.Status.Conditions = []batchv1.JobCondition{{Type: batchv1.JobFailed, Status: corev1.ConditionTrue}}
	if err := c.Status().Update(context.Background(), &job); err != nil {
		t.Fatal(err)
	}
	pod := &corev1.Pod{
		ObjectMeta: metav1.ObjectMeta{
			Name:      job.Name + "-pod",
			Namespace: "continuous",
			Labels:    map[string]string{"job-name": job.Name},
		},
		Status: corev1.PodStatus{
			ContainerStatuses: []corev1.ContainerStatus{{
				Name: "build",
				State: corev1.ContainerState{
					Terminated: &corev1.ContainerStateTerminated{
						ExitCode: 1,
						Message:  "artifact fetch failed: 404",
					},
				},
			}},
		},
	}
	if err := c.Create(context.Background(), pod); err != nil {
		t.Fatal(err)
	}

	doReconcile(t, r, ci)
	ci = refresh(t, c, ci)

	if cond := readyCondition(ci); cond == nil || cond.Reason != "BuildFailed" {
		t.Fatalf("condition = %+v", cond)
	}
	if ci.Status.BuildAttempts != 1 {
		t.Fatalf("buildAttempts = %d", ci.Status.BuildAttempts)
	}
	if ci.Status.LastBuiltRevision != "" {
		t.Fatalf("artifact fetch failure must clear lastBuiltRevision, got %q", ci.Status.LastBuiltRevision)
	}

	// The failed Job is deleted so the retry gets a fresh name.
	for _, j := range jobsOf(t, c) {
		if j.Name == job.Name {
			t.Fatal("failed job must be deleted")
		}
	}

	// The retry (triggered by the cleared revision) creates a new Job.
	doReconcile(t, r, ci)
	jobs = jobsOf(t, c)
	if len(jobs) != 1 || jobs[0].Name == job.Name {
		t.Fatalf("want a retried job with a new name, got %+v", jobs)
	}
}

func TestReconcileReplacesActiveJobOnNewRevision(t *testing.T) {
	// A completed build exists, then a new artifact revision lands while the
	// rebuild for the previous revision is still running.
	ci := testCR(func(ci *v1alpha1.ContainerImage) {
		ci.Status.LastBuiltRevision = "main@sha1:older"
		ci.Status.LastBaseTag = testBaseTag
	})
	r, c := testSetup(t, append(sourceObjects(), ci)...)

	doReconcile(t, r, ci)
	firstJobs := jobsOf(t, c)
	if len(firstJobs) != 1 {
		t.Fatalf("want 1 job, got %d", len(firstJobs))
	}
	firstJob := firstJobs[0]

	// A new commit lands while the Job is active.
	repo := &sourcev1.GitRepository{}
	if err := c.Get(context.Background(), types.NamespacedName{Namespace: "flux-system", Name: "configs"}, repo); err != nil {
		t.Fatal(err)
	}
	newRevision := "main@sha1:11223344556677"
	repo.Status.Artifact.Revision = newRevision
	if err := c.Status().Update(context.Background(), repo); err != nil {
		t.Fatal(err)
	}

	doReconcile(t, r, ci)

	// The stale Job is replaced by one for the new revision.
	replaced := false
	for _, j := range jobsOf(t, c) {
		if j.Name != firstJob.Name {
			if j.Annotations[build.AnnArtifactRevision] == newRevision {
				replaced = true
			}
		}
	}
	if !replaced {
		t.Fatalf("active job for the old revision must be replaced, jobs: %+v", jobsOf(t, c))
	}
}

func TestReconcileDeleteFinalizesJobs(t *testing.T) {
	ci := testCR(nil)
	r, c := testSetup(t, append(sourceObjects(), ci)...)

	doReconcile(t, r, ci)
	if len(jobsOf(t, c)) != 1 {
		t.Fatal("want the job to exist")
	}

	// Deleting the CR (finalizer blocks removal) must clean up the Jobs,
	// then remove the finalizer so the object goes away.
	if err := c.Delete(context.Background(), ci); err != nil {
		t.Fatal(err)
	}
	doReconcile(t, r, ci)
	doReconcile(t, r, ci)

	err := c.Get(context.Background(), client.ObjectKeyFromObject(ci), &v1alpha1.ContainerImage{})
	if err == nil {
		t.Fatal("ContainerImage must be gone after finalization")
	}
	for _, j := range jobsOf(t, c) {
		if j.Labels[build.LabelContainerImage] == "continuous."+ci.Name {
			t.Fatalf("build job %s must be deleted", j.Name)
		}
	}
}

// failCurrentJob marks the CR's active Job failed with a pod reporting the
// given termination message (empty: generic failure) and processes it.
func failCurrentJob(t *testing.T, r *ContainerImageReconciler, c client.Client, ci *v1alpha1.ContainerImage, message string, init bool) {
	t.Helper()
	doReconcile(t, r, ci)
	jobs := jobsOf(t, c)
	if len(jobs) != 1 {
		t.Fatalf("want 1 active job, got %d", len(jobs))
	}
	job := jobs[0]
	job.Status.Conditions = []batchv1.JobCondition{{Type: batchv1.JobFailed, Status: corev1.ConditionTrue}}
	if err := c.Status().Update(context.Background(), &job); err != nil {
		t.Fatal(err)
	}
	terminated := corev1.ContainerStateTerminated{ExitCode: 1, Message: message}
	pod := &corev1.Pod{
		ObjectMeta: metav1.ObjectMeta{
			Name:      job.Name + "-pod",
			Namespace: "continuous",
			Labels:    map[string]string{"job-name": job.Name},
		},
	}
	if init {
		// The prepare init container died; the build container never started.
		pod.Status = corev1.PodStatus{InitContainerStatuses: []corev1.ContainerStatus{{
			Name:  "prepare",
			State: corev1.ContainerState{Terminated: &terminated},
		}}}
	} else {
		pod.Status = corev1.PodStatus{ContainerStatuses: []corev1.ContainerStatus{{
			Name:  "build",
			State: corev1.ContainerState{Terminated: &terminated},
		}}}
	}
	if err := c.Create(context.Background(), pod); err != nil {
		t.Fatal(err)
	}
	doReconcile(t, r, ci)
}

// TestReconcileInitContainerFailureSelfHeals covers a prepare init container
// failure (artifact fetch): the markers reach the controller via the init
// container's termination message, since the build container never started.
func TestReconcileInitContainerFailureSelfHeals(t *testing.T) {
	ci := testCR(func(ci *v1alpha1.ContainerImage) {
		ci.Status.LastBuiltRevision = "main@sha1:older"
	})
	r, c := testSetup(t, append(sourceObjects(), ci)...)

	failCurrentJob(t, r, c, ci, "artifact fetch failed: 404", true)
	ci = refresh(t, c, ci)

	if cond := readyCondition(ci); cond == nil || cond.Reason != "BuildFailed" {
		t.Fatalf("condition = %+v", cond)
	}
	if ci.Status.BuildAttempts != 1 {
		t.Fatalf("buildAttempts = %d", ci.Status.BuildAttempts)
	}
	if ci.Status.LastBuiltRevision != "" {
		t.Fatalf("artifact fetch failure must clear lastBuiltRevision, got %q", ci.Status.LastBuiltRevision)
	}
}

// TestReconcileScheduleGiveUpNotMasked covers a schedule-triggered build that
// exhausts its attempts: the Ready condition must stay False (not flip back to
// "pushed <stale ref>"), and the next tick must be seeded with a fresh attempt
// budget.
func TestReconcileScheduleGiveUpNotMasked(t *testing.T) {
	now := time.Date(2026, 8, 31, 3, 0, 0, 0, time.UTC)
	due := metav1.Time{Time: now.Add(-time.Hour)}
	ci := testCR(func(ci *v1alpha1.ContainerImage) {
		ci.Status.LastBuiltRevision = testRevision
		ci.Status.LastBaseTag = testBaseTag
		ci.Status.LastTag = "2.0.2-" + testBaseTag
		ci.Status.LastImageRef = "registry.local.d20.fan/fancl20/dae:2.0.2-" + testBaseTag
		ci.Status.NextScheduleRun = &due
	})
	r, c := testSetup(t, append(sourceObjects(), ci)...)

	for attempt := 1; attempt <= r.Config.MaxAttempts; attempt++ {
		failCurrentJob(t, r, c, ci, "", false)
		ci = refresh(t, c, ci)
		if ci.Status.BuildAttempts != attempt {
			t.Fatalf("buildAttempts = %d, want %d", ci.Status.BuildAttempts, attempt)
		}
	}

	// The next reconcile enters give-up: the tick is consumed (seeded to the
	// future) and the failure is recorded, not hidden.
	doReconcile(t, r, ci)
	ci = refresh(t, c, ci)
	if cond := readyCondition(ci); cond == nil || cond.Reason != "BuildFailed" || cond.Status != metav1.ConditionFalse {
		t.Fatalf("give-up condition = %+v", cond)
	}
	if ci.Status.NextScheduleRun == nil || !ci.Status.NextScheduleRun.After(now) {
		t.Fatalf("next schedule run = %+v, want a future tick", ci.Status.NextScheduleRun)
	}

	// An idle reconcile must not repaint the burned-out schedule as Ready
	// from the stale lastImageRef.
	doReconcile(t, r, ci)
	ci = refresh(t, c, ci)
	if cond := readyCondition(ci); cond == nil || cond.Reason != "BuildFailed" || cond.Status != metav1.ConditionFalse {
		t.Fatalf("idle condition = %+v, want BuildFailed to persist", cond)
	}
	if got := len(jobsOf(t, c)); got != 0 {
		t.Fatalf("no further jobs after give-up, got %d", got)
	}
}
