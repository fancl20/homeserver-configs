// Package status defines condition reasons for ContainerImage resources.
package status

import (
	apimeta "k8s.io/apimachinery/pkg/api/meta"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"

	"github.com/fluxcd/pkg/apis/meta"

	"image-controller/api/v1alpha1"
)

// Ready is the single top-level condition, following the Flux convention.
const Ready = meta.ReadyCondition

// Reasons for the Ready condition.
const (
	ReasonSuspended        = "Suspended"
	ReasonInvalidSpec      = "InvalidSpec"
	ReasonSourceNotFound   = "SourceNotFound"
	ReasonArtifactMissing  = "ArtifactMissing"
	ReasonBaseNotReady     = "BaseNotReady"
	ReasonBuildProgressing = "BuildProgressing"
	ReasonBuildFailed      = "BuildFailed"
	ReasonBuildSucceeded   = "BuildSucceeded"
)

// Event reasons.
const (
	EventBuildStarted    = "BuildStarted"
	EventBuildSucceeded  = "BuildSucceeded"
	EventBuildFailed     = "BuildFailed"
	EventBuildSuperseded = "BuildSuperseded"
)

// Mark sets the Ready condition on the ContainerImage status.
func Mark(ci *v1alpha1.ContainerImage, status metav1.ConditionStatus, reason, message string) {
	apimeta.SetStatusCondition(&ci.Status.Conditions, metav1.Condition{
		Type:               Ready,
		Status:             status,
		Reason:             reason,
		Message:            message,
		ObservedGeneration: ci.Generation,
	})
}

// NamespacedName returns the request key for a ContainerImage.
func NamespacedName(ci *v1alpha1.ContainerImage) types.NamespacedName {
	return types.NamespacedName{Namespace: ci.Namespace, Name: ci.Name}
}
