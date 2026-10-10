package controller

import (
	"context"
	"errors"
	"fmt"

	imagev1 "github.com/fluxcd/image-reflector-controller/api/v1"
	sourcev1 "github.com/fluxcd/source-controller/api/v1"
	"sigs.k8s.io/controller-runtime/pkg/client"

	fluxmeta "github.com/fluxcd/pkg/apis/meta"

	"image-controller/api/v1alpha1"
	"image-controller/internal/config"
)

// notFoundError marks a referenced object that does not exist (or is not
// ready), mapped to a distinct condition reason by the reconciler.
type notFoundError struct{ message string }

func (e *notFoundError) Error() string { return e.message }

func notFound(format string, args ...any) error {
	return &notFoundError{message: fmt.Sprintf(format, args...)}
}

// sourceArtifact resolves the artifact of the referenced GitRepository.
func sourceArtifact(ctx context.Context, c client.Reader, ci *v1alpha1.ContainerImage) (*fluxmeta.Artifact, error) {
	ref := ci.Spec.SourceRef
	namespace := ref.Namespace
	if namespace == "" {
		namespace = "flux-system"
	}
	repo := &sourcev1.GitRepository{}
	if err := c.Get(ctx, client.ObjectKey{Namespace: namespace, Name: ref.Name}, repo); err != nil {
		return nil, notFound("GitRepository %s/%s not found: %v", namespace, ref.Name, err)
	}
	if repo.Status.Artifact == nil {
		return nil, notFound("GitRepository %s/%s has no artifact yet", namespace, ref.Name)
	}
	return repo.Status.Artifact, nil
}

// resolveBaseTag returns the tag selected by spec.baseRef's ImagePolicy.
func resolveBaseTag(ctx context.Context, c client.Reader, ci *v1alpha1.ContainerImage) (string, error) {
	ref := ci.Spec.BaseRef
	namespace := ref.Namespace
	if namespace == "" {
		namespace = "flux-system"
	}
	policy := &imagev1.ImagePolicy{}
	if err := c.Get(ctx, client.ObjectKey{Namespace: namespace, Name: ref.Name}, policy); err != nil {
		return "", notFound("ImagePolicy %s/%s not found: %v", namespace, ref.Name, err)
	}
	if policy.Status.LatestRef == nil || policy.Status.LatestRef.Tag == "" {
		return "", notFound("ImagePolicy %s/%s has not selected a tag yet", namespace, ref.Name)
	}
	return policy.Status.LatestRef.Tag, nil
}

// buildKitImage resolves the buildkit image from its ImagePolicy, falling
// back to the pinned default when the policy has no tag yet.
func buildKitImage(ctx context.Context, c client.Reader, cfg *config.Config) string {
	policy := &imagev1.ImagePolicy{}
	key := client.ObjectKey{Namespace: cfg.BuildKitPolicyNamespace, Name: cfg.BuildKitPolicyName}
	if err := c.Get(ctx, key, policy); err == nil &&
		policy.Status.LatestRef != nil && policy.Status.LatestRef.Tag != "" {
		return cfg.BuildKitRepo + ":" + policy.Status.LatestRef.Tag
	}
	return cfg.BuildKitFallbackImage
}

// isNotFound reports whether err is a notFoundError.
func isNotFound(err error) bool {
	var nf *notFoundError
	return errors.As(err, &nf)
}
