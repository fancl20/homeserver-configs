package controller

import (
	"testing"

	imagev1 "github.com/fluxcd/image-reflector-controller/api/v1"
	sourcev1 "github.com/fluxcd/source-controller/api/v1"
	batchv1 "k8s.io/api/batch/v1"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/event"
	"sigs.k8s.io/controller-runtime/pkg/predicate"

	fluxmeta "github.com/fluxcd/pkg/apis/meta"

	"image-controller/api/v1alpha1"
)

func gitRepoWithArtifact(revision string) *sourcev1.GitRepository {
	return &sourcev1.GitRepository{
		ObjectMeta: metav1.ObjectMeta{Name: "configs", Namespace: "flux-system", Generation: 1},
		Status: sourcev1.GitRepositoryStatus{
			Artifact: &fluxmeta.Artifact{Revision: revision},
		},
	}
}

func imagePolicyWithTag(tag string) *imagev1.ImagePolicy {
	return &imagev1.ImagePolicy{
		ObjectMeta: metav1.ObjectMeta{Name: "debian", Namespace: "flux-system", Generation: 1},
		Status: imagev1.ImagePolicyStatus{
			LatestRef: &imagev1.ImageRef{Tag: tag},
		},
	}
}

func jobWithConditions(conditions ...batchv1.JobCondition) *batchv1.Job {
	return &batchv1.Job{
		ObjectMeta: metav1.ObjectMeta{Name: "dae-abc1234", Namespace: "continuous", Generation: 1},
		Status:     batchv1.JobStatus{Conditions: conditions},
	}
}

func completeCondition() batchv1.JobCondition {
	return batchv1.JobCondition{Type: batchv1.JobComplete, Status: corev1.ConditionTrue}
}

func failedCondition() batchv1.JobCondition {
	return batchv1.JobCondition{Type: batchv1.JobFailed, Status: corev1.ConditionTrue}
}

func TestJobStatusChangedPredicate(t *testing.T) {
	running := jobWithConditions()
	complete := jobWithConditions(completeCondition())
	failed := jobWithConditions(failedCondition())

	tests := []struct {
		name string
		old  client.Object
		new  client.Object
		want bool
	}{
		{name: "running to complete", old: running, new: complete, want: true},
		{name: "running to failed", old: running, new: failed, want: true},
		{name: "still running, other status change", old: running, new: jobWithConditions(), want: false},
		{name: "already complete", old: complete, new: complete.DeepCopy(), want: false},
		{name: "old not a Job", old: &v1alpha1.ContainerImage{}, new: complete, want: false},
		{name: "new not a Job", old: running, new: &v1alpha1.ContainerImage{}, want: false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			evt := event.UpdateEvent{ObjectOld: tt.old, ObjectNew: tt.new}
			if got := (JobStatusChangedPredicate{}).Update(evt); got != tt.want {
				t.Fatalf("Update = %v, want %v", got, tt.want)
			}
		})
	}

	// Create and Delete must not pass: the controller deletes failed Jobs
	// itself, and the resulting Delete event would map straight back to the
	// ContainerImage, defeating the failure backoff.
	if (JobStatusChangedPredicate{}).Create(event.CreateEvent{Object: complete}) {
		t.Error("Create must not pass")
	}
	if (JobStatusChangedPredicate{}).Delete(event.DeleteEvent{Object: failed}) {
		t.Error("Delete must not pass")
	}
}

// TestForFilterMustStayScoped guards the watch wiring in cmd/controller.
// controller-runtime ANDs WithEventFilter predicates into every watch (each
// predicate must pass), and the events the cross-object watches exist for
// are status-only updates. Applying the For() filter globally therefore
// dropped every artifact, tag, and completion event, leaving change
// detection to the interval requeue. If this test fails after a wiring
// change, the filter has leaked back into the watches.
func TestForFilterMustStayScoped(t *testing.T) {
	global := predicate.Or(
		predicate.GenerationChangedPredicate{},
		RequestedAtPredicate{},
	)

	artifactUpdate := event.UpdateEvent{
		ObjectOld: gitRepoWithArtifact("main@sha1:old"),
		ObjectNew: gitRepoWithArtifact("main@sha1:new"),
	}
	if global.Update(artifactUpdate) {
		t.Error("generation/requestedAt filter must not pass a status-only artifact update")
	}
	if !(SourceArtifactPredicate{}).Update(artifactUpdate) {
		t.Error("SourceArtifactPredicate must pass an artifact revision change")
	}

	tagUpdate := event.UpdateEvent{
		ObjectOld: imagePolicyWithTag("testing-1"),
		ObjectNew: imagePolicyWithTag("testing-2"),
	}
	if global.Update(tagUpdate) {
		t.Error("generation/requestedAt filter must not pass a status-only tag update")
	}
	if !(BasePolicyPredicate{}).Update(tagUpdate) {
		t.Error("BasePolicyPredicate must pass a tag change")
	}

	completion := event.UpdateEvent{
		ObjectOld: jobWithConditions(),
		ObjectNew: jobWithConditions(completeCondition()),
	}
	if global.Update(completion) {
		t.Error("generation/requestedAt filter must not pass a status-only Job completion")
	}
	if !(JobStatusChangedPredicate{}).Update(completion) {
		t.Error("JobStatusChangedPredicate must pass a Job completion")
	}
}
