package controller

import (
	"context"

	imagev1 "github.com/fluxcd/image-reflector-controller/api/v1"
	sourcev1 "github.com/fluxcd/source-controller/api/v1"
	batchv1 "k8s.io/api/batch/v1"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/event"
	"sigs.k8s.io/controller-runtime/pkg/predicate"
	"sigs.k8s.io/controller-runtime/pkg/reconcile"

	fluxmeta "github.com/fluxcd/pkg/apis/meta"

	"image-controller/api/v1alpha1"
)

// RequestedAtPredicate passes updates of the reconcile.fluxcd.io/requestedAt
// annotation. Annotation writes do not bump metadata.generation, so it must be
// OR-ed with GenerationChangedPredicate or manual triggers never fire.
type RequestedAtPredicate struct {
	predicate.Funcs
}

func (RequestedAtPredicate) Update(e event.UpdateEvent) bool {
	if e.ObjectOld == nil || e.ObjectNew == nil {
		return false
	}
	return e.ObjectOld.GetAnnotations()[fluxmeta.ReconcileRequestAnnotation] !=
		e.ObjectNew.GetAnnotations()[fluxmeta.ReconcileRequestAnnotation]
}

// JobStatusChangedPredicate passes Job updates whose Complete or Failed
// condition newly appeared. Completion is a status-only change (generation
// does not bump), so the Owns(Job) watch must carry this predicate instead
// of inheriting a generation-based filter. Create and Delete are explicitly
// rejected: the controller deletes failed Jobs itself, and a Delete event
// mapping back to the ContainerImage would re-reconcile it immediately and
// defeat the failure backoff.
type JobStatusChangedPredicate struct {
	predicate.Funcs
}

func (JobStatusChangedPredicate) Update(e event.UpdateEvent) bool {
	oldJob, oldOK := e.ObjectOld.(*batchv1.Job)
	newJob, newOK := e.ObjectNew.(*batchv1.Job)
	if !oldOK || !newOK {
		return false
	}
	return (!jobComplete(oldJob) && jobComplete(newJob)) ||
		(!jobFailed(oldJob) && jobFailed(newJob))
}

func (JobStatusChangedPredicate) Create(event.CreateEvent) bool { return false }

func (JobStatusChangedPredicate) Delete(event.DeleteEvent) bool { return false }

// SourceArtifactPredicate passes GitRepository events whose artifact revision
// changed (status-only updates do not bump generation).
type SourceArtifactPredicate struct {
	predicate.Funcs
}

func (SourceArtifactPredicate) Update(e event.UpdateEvent) bool {
	oldRepo, oldOK := e.ObjectOld.(*sourcev1.GitRepository)
	newRepo, newOK := e.ObjectNew.(*sourcev1.GitRepository)
	if !oldOK || !newOK {
		return false
	}
	return artifactRevision(oldRepo) != artifactRevision(newRepo)
}

// BasePolicyPredicate passes ImagePolicy events whose selected tag changed.
type BasePolicyPredicate struct {
	predicate.Funcs
}

func (BasePolicyPredicate) Update(e event.UpdateEvent) bool {
	oldPolicy, oldOK := e.ObjectOld.(*imagev1.ImagePolicy)
	newPolicy, newOK := e.ObjectNew.(*imagev1.ImagePolicy)
	if !oldOK || !newOK {
		return false
	}
	return latestTag(oldPolicy) != latestTag(newPolicy)
}

func artifactRevision(repo *sourcev1.GitRepository) string {
	if repo.Status.Artifact == nil {
		return ""
	}
	return repo.Status.Artifact.Revision
}

func latestTag(policy *imagev1.ImagePolicy) string {
	if policy.Status.LatestRef == nil {
		return ""
	}
	return policy.Status.LatestRef.Tag
}

// MapSource enqueues ContainerImages whose spec.sourceRef matches the event
// object. Requires the SourceRefIndex field index.
func (r *ContainerImageReconciler) MapSource(ctx context.Context, obj client.Object) []reconcile.Request {
	return r.mapByIndex(ctx, SourceRefIndex, obj.GetNamespace()+"/"+obj.GetName())
}

// MapBasePolicy enqueues ContainerImages whose spec.baseRef matches the event
// object. Requires the BaseRefIndex field index.
func (r *ContainerImageReconciler) MapBasePolicy(ctx context.Context, obj client.Object) []reconcile.Request {
	return r.mapByIndex(ctx, BaseRefIndex, obj.GetNamespace()+"/"+obj.GetName())
}

func (r *ContainerImageReconciler) mapByIndex(ctx context.Context, index, value string) []reconcile.Request {
	list := &v1alpha1.ContainerImageList{}
	if err := r.List(ctx, list, client.MatchingFields{index: value}); err != nil {
		return nil
	}
	requests := make([]reconcile.Request, 0, len(list.Items))
	for _, item := range list.Items {
		requests = append(requests, reconcile.Request{
			NamespacedName: statusNamespacedName(&item),
		})
	}
	return requests
}
