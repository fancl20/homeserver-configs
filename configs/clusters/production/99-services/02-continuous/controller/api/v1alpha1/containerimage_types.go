package v1alpha1

import (
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

// Tag template variables substituted by the build pod's prepare step.
const (
	// TagVarVersion is replaced with the version from spec.version or the
	// update command's versionFile.
	TagVarVersion = "version"
	// TagVarBase is replaced with the tag selected by spec.baseRef.
	TagVarBase = "base"
	// TagVarSHA is replaced with the 7-char short SHA of the source revision.
	TagVarSHA = "sha"
	// TagVarDate is replaced with the build start time (YYYYMMDD-HHMM).
	TagVarDate = "date"
)

// ContainerImageSpec declares a container image that must exist in the local
// registry, built from a Flux source artifact. The controller rebuilds it when
// the source revision changes, the schedule ticks, the base tag moves, or a
// manual reconcile is requested with the reconcile.fluxcd.io/requestedAt
// annotation.
type ContainerImageSpec struct {
	// SourceRef points at the Flux source whose artifact provides the build
	// context.
	// +kubebuilder:validation:Required
	SourceRef SourceRef `json:"sourceRef"`

	// Context is the path of the build context inside the source artifact.
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:Pattern=`^[.a-zA-Z0-9/_-]+$`
	// +kubebuilder:validation:MaxLength=512
	Context string `json:"context"`

	// Image is the repository pushed as <registry-host>/<image>; it must not
	// contain a registry host or tag.
	// +kubebuilder:validation:Required
	// +kubebuilder:validation:Pattern=`^[a-z0-9./_-]+$`
	// +kubebuilder:validation:MaxLength=255
	Image string `json:"image"`

	// Tag is a template for the pushed tag. Variables: version, base, sha,
	// date. The image-controller tag policy matches "<version>-testing-<date>"
	// (Semver '*-testing-'), mirroring the dae/chrome schemes.
	// +kubebuilder:validation:MaxLength=128
	// +kubebuilder:default=`{{ version }}`
	Tag string `json:"tag,omitempty"`

	// Update runs a version-determination command inside the build context
	// before the build (the images/*/update.py contract: `version` writes the
	// version file that both this tag template and the Dockerfile consume).
	// Mutually exclusive with version.
	Update *UpdateSpec `json:"update,omitempty"`

	// Version is a static tag version, used when the version is known in
	// advance (e.g. the controller's own image). Mutually exclusive with
	// update.
	// +kubebuilder:validation:MaxLength=64
	// +kubebuilder:validation:Pattern=`^[A-Za-z0-9][A-Za-z0-9._+-]*$`
	Version string `json:"version,omitempty"`

	// BaseRef selects an ImagePolicy whose tag feeds the {{ base }} template
	// variable and the BASE_TAG build arg (e.g. the debian testing policy).
	BaseRef *PolicyRef `json:"baseRef,omitempty"`

	// BuildArgs are passed as build-arg KEY=VALUE to the Dockerfile.
	// +kubebuilder:validation:MaxProperties=32
	BuildArgs map[string]string `json:"buildArgs,omitempty"`

	// Schedule is an optional 5-field cron expression (plus @descriptors)
	// triggering a rebuild, evaluated in timeZone. Use it for images whose
	// version is discovered from upstream at build time.
	// +kubebuilder:validation:MaxLength=64
	Schedule string `json:"schedule,omitempty"`

	// +kubebuilder:validation:MaxLength=64
	TimeZone string `json:"timeZone,omitempty"`

	// Interval is how often the source and base policy are checked.
	// +kubebuilder:validation:Type=string
	// +kubebuilder:validation:Pattern=`^([0-9]+(\.[0-9]+)?(ms|s|m|h))+$`
	// +kubebuilder:validation:Required
	Interval metav1.Duration `json:"interval"`

	// Timeout bounds a single build; exceeded builds fail.
	// +kubebuilder:validation:Type=string
	// +kubebuilder:validation:Pattern=`^([0-9]+(\.[0-9]+)?(ms|s|m|h))+$`
	Timeout *metav1.Duration `json:"timeout,omitempty"`

	// Suspend stops all builds and triggers for this image.
	Suspend bool `json:"suspend,omitempty"`
}

// SourceRef references the Flux source whose artifact provides the build
// context.
type SourceRef struct {
	// +kubebuilder:validation:Enum=GitRepository
	// +kubebuilder:validation:Required
	Kind string `json:"kind"`

	// +kubebuilder:validation:MinLength=1
	// +kubebuilder:validation:MaxLength=253
	// +kubebuilder:validation:Required
	Name string `json:"name"`

	// +kubebuilder:validation:MaxLength=253
	Namespace string `json:"namespace,omitempty"`
}

// UpdateSpec describes the version-determination command.
type UpdateSpec struct {
	// Image is the container image the command runs in; defaults to the
	// controller's prepare image (python).
	// +kubebuilder:validation:MaxLength=255
	Image string `json:"image,omitempty"`

	// Command is an argv (no shell) run with the build context as working
	// directory.
	// +kubebuilder:validation:MinItems=1
	// +kubebuilder:validation:Required
	Command []string `json:"command"`

	// VersionFile is the file (relative to the context) the command writes
	// the version into.
	// +kubebuilder:validation:Pattern=`^[.a-zA-Z0-9/_-]+$`
	// +kubebuilder:validation:MaxLength=128
	// +kubebuilder:validation:Required
	VersionFile string `json:"versionFile"`
}

// PolicyRef references an image.toolkit.fluxcd.io ImagePolicy.
type PolicyRef struct {
	// +kubebuilder:validation:MinLength=1
	// +kubebuilder:validation:MaxLength=253
	// +kubebuilder:validation:Required
	Name string `json:"name"`

	// +kubebuilder:validation:MaxLength=253
	Namespace string `json:"namespace,omitempty"`
}

// ContainerImageStatus is the observed state of a ContainerImage.
type ContainerImageStatus struct {
	// +listType=map
	// +listMapKey=type
	// +kubebuilder:validation:MaxItems=8
	Conditions []metav1.Condition `json:"conditions,omitempty"`

	// LastHandledReconcileAt records the reconcile.fluxcd.io/requestedAt
	// annotation value last consumed as a build trigger.
	LastHandledReconcileAt string `json:"lastHandledReconcileAt,omitempty"`

	ObservedGeneration int64 `json:"observedGeneration,omitempty"`

	// ObservedArtifactRevision is the revision of the source artifact last
	// seen by the controller.
	ObservedArtifactRevision string `json:"observedArtifactRevision,omitempty"`

	// LastBuiltRevision is the revision the last successful build used.
	LastBuiltRevision string `json:"lastBuiltRevision,omitempty"`

	// LastSpecHash is the spec hash the last successful build used; a
	// different hash means the spec changed since and a rebuild is due.
	LastSpecHash string `json:"lastSpecHash,omitempty"`

	// LastBaseTag is the base policy tag the last successful build used.
	LastBaseTag string `json:"lastBaseTag,omitempty"`

	// LastTag is the tag of the last successful build.
	LastTag string `json:"lastTag,omitempty"`

	// LastImageRef is the full reference of the last successful build.
	LastImageRef string `json:"lastImageRef,omitempty"`

	LastBuildStartTime *metav1.Time `json:"lastBuildStartTime,omitempty"`

	LastBuildCompletionTime *metav1.Time `json:"lastBuildCompletionTime,omitempty"`

	// CurrentJob is the build Job currently tracked by the controller.
	CurrentJob string `json:"currentJob,omitempty"`

	// NextScheduleRun is the precomputed next schedule tick.
	NextScheduleRun *metav1.Time `json:"nextScheduleRun,omitempty"`

	// LastTriggerKey is the trigger key (without the attempts component) of
	// the last created Job; a different key resets BuildAttempts.
	LastTriggerKey string `json:"lastTriggerKey,omitempty"`

	// BuildAttempts counts consecutive failures for the same trigger.
	BuildAttempts int `json:"buildAttempts,omitempty"`
}

// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:resource:shortName={ci,cimg},categories=flux
// +kubebuilder:printcolumn:name="Image",type=string,JSONPath=`.spec.image`
// +kubebuilder:printcolumn:name="Last Tag",type=string,JSONPath=`.status.lastTag`
// +kubebuilder:printcolumn:name="Ready",type=string,JSONPath=`.status.conditions[?(@.type=="Ready")].status`
// +kubebuilder:printcolumn:name="Reason",type=string,JSONPath=`.status.conditions[?(@.type=="Ready")].reason`
// +kubebuilder:printcolumn:name="Job",type=string,JSONPath=`.status.currentJob`
// +kubebuilder:printcolumn:name="Age",type=date,JSONPath=`.metadata.creationTimestamp`

// ContainerImage declares a container image built from a Flux source.
type ContainerImage struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   ContainerImageSpec   `json:"spec,omitempty"`
	Status ContainerImageStatus `json:"status,omitempty"`
}

// +kubebuilder:object:root=true

// ContainerImageList contains a list of ContainerImages.
type ContainerImageList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []ContainerImage `json:"items"`
}

func init() {
	SchemeBuilder.Register(&ContainerImage{}, &ContainerImageList{})
}
