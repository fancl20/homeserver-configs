// Package build creates the buildkit Jobs that realize ContainerImages.
package build

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"sort"
	"strings"
	"time"

	batchv1 "k8s.io/api/batch/v1"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/utils/ptr"

	"image-controller/api/v1alpha1"
	"image-controller/internal/config"
)

// Labels and annotations linking a build Job back to its ContainerImage.
const (
	LabelContainerImage = "d20.fan/container-image"
	AnnTriggerKey       = "d20.fan/trigger-key"
	AnnArtifactRevision = "d20.fan/artifact-revision"
	AnnBaseTag          = "d20.fan/base-tag"
	AnnSpecHash         = "d20.fan/spec-hash"

	// ContextDir and TagFile are the shared emptyDir layout.
	contextDir = "/work/src"
	outDir     = "/work/out"
	tagFile    = outDir + "/tag"
)

// ContainerImageLabel returns the label value identifying a ContainerImage on
// its build Jobs. Jobs all live in the build namespace, so the value must be
// namespace-qualified (label values cannot contain '/', hence the '.') to keep
// same-named ContainerImages in different namespaces from adopting each
// other's Jobs.
func ContainerImageLabel(ci *v1alpha1.ContainerImage) string {
	return ci.Namespace + "." + ci.Name
}

// SpecHash hashes the spec fields that affect the build, so any spec change
// produces a new trigger key and Job name.
func SpecHash(spec v1alpha1.ContainerImageSpec) string {
	normalized := spec.DeepCopy()
	normalized.Interval = metav1.Duration{}
	normalized.Timeout = nil
	normalized.Suspend = false
	normalized.Schedule = ""
	normalized.TimeZone = ""
	raw, err := json.Marshal(normalized)
	if err != nil {
		// json.Marshal of plain API types cannot fail.
		panic(err)
	}
	sum := sha256.Sum256(raw)
	return hex.EncodeToString(sum[:])
}

// ShortSHA extracts a 7-char short SHA from a Flux revision such as
// "main@sha1:8fdae88...". Non-SHA revisions hash to a stable fallback.
func ShortSHA(revision string) string {
	if i := strings.LastIndexByte(revision, ':'); i >= 0 && len(revision)-i-1 >= 7 {
		return revision[i+1 : i+8]
	}
	sum := sha256.Sum256([]byte(revision))
	return hex.EncodeToString(sum[:])[:7]
}

// JobInput carries everything needed to render a build Job.
type JobInput struct {
	ContainerImage *v1alpha1.ContainerImage
	TriggerKey     string
	SpecHash       string
	ArtifactURL    string
	ArtifactDigest string
	ArtifactRev    string
	BaseTag        string
	BuildKitImage  string
	Config         *config.Config
	Now            time.Time
}

// BuildJob renders the buildkit Job. The build container's security context
// and buildctl invocation mirror the proven Argo Workflows template.
func BuildJob(in JobInput) *batchv1.Job {
	ci := in.ContainerImage
	spec := ci.Spec
	location := in.Config.Location
	if spec.TimeZone != "" {
		if loc, err := time.LoadLocation(spec.TimeZone); err == nil {
			location = loc
		}
	}

	prepareImage := in.Config.PrepareImage
	var updateCommand string
	var versionFile string
	if spec.Update != nil {
		if spec.Update.Image != "" {
			prepareImage = spec.Update.Image
		}
		updateCommand = marshalJSON(spec.Update.Command)
		versionFile = spec.Update.VersionFile
	}

	workingDir := contextDir + "/" + spec.Context

	prepareEnv := []corev1.EnvVar{
		env("ARTIFACT_URL", in.ArtifactURL),
		env("ARTIFACT_DIGEST", in.ArtifactDigest),
		env("SOURCE_DIR", contextDir),
		env("OUT_DIR", outDir),
		env("CONTEXT", spec.Context),
		env("UPDATE_CMD", updateCommand),
		env("VERSION_FILE", versionFile),
		env("VERSION_LITERAL", spec.Version),
		env("TAG", spec.Tag),
		env("VAR_BASE", in.BaseTag),
		env("VAR_SHA", ShortSHA(in.ArtifactRev)),
		env("VAR_DATE", in.Now.In(location).Format("20060102-1504")),
	}

	buildEnv := []corev1.EnvVar{
		env("BUILDKITD_FLAGS", "--oci-worker-no-process-sandbox"),
		env("REGISTRY_HOST", in.Config.RegistryHost),
		env("IMAGE_NAME", spec.Image),
		env("TAG_FILE", tagFile),
		env("BUILD_ARGS", strings.Join(mergeBuildArgs(spec, in.BaseTag), "\n")),
	}

	timeout := in.Config.JobTimeout
	if spec.Timeout != nil {
		timeout = spec.Timeout.Duration
	}

	// A namespaced owner must live in the Job's namespace; the GC deletes
	// dependents carrying cross-namespace owner references. Out-of-namespace
	// ContainerImages rely on the finalizer's label-based cleanup instead.
	var ownerRefs []metav1.OwnerReference
	if ci.Namespace == in.Config.BuildNamespace {
		ownerRefs = append(ownerRefs, metav1.OwnerReference{
			APIVersion:         v1alpha1.GroupVersion.String(),
			Kind:               "ContainerImage",
			Name:               ci.Name,
			UID:                ci.UID,
			Controller:         ptr.To(true),
			BlockOwnerDeletion: ptr.To(false),
		})
	}

	return &batchv1.Job{
		ObjectMeta: metav1.ObjectMeta{
			Name:      JobName(ci.Name, in.TriggerKey),
			Namespace: in.Config.BuildNamespace,
			Labels: map[string]string{
				LabelContainerImage: ContainerImageLabel(ci),
			},
			Annotations: map[string]string{
				AnnTriggerKey:       in.TriggerKey,
				AnnArtifactRevision: in.ArtifactRev,
				AnnBaseTag:          in.BaseTag,
				AnnSpecHash:         in.SpecHash,
			},
			OwnerReferences: ownerRefs,
		},
		Spec: batchv1.JobSpec{
			BackoffLimit:            ptr.To(int32(0)), // the controller owns retries
			TTLSecondsAfterFinished: ptr.To(int32(in.Config.JobTTL.Seconds())),
			ActiveDeadlineSeconds:   ptr.To(int64(timeout.Seconds())),
			Template: corev1.PodTemplateSpec{
				ObjectMeta: metav1.ObjectMeta{
					Labels: map[string]string{
						LabelContainerImage: ContainerImageLabel(ci),
					},
				},
				Spec: corev1.PodSpec{
					RestartPolicy:                corev1.RestartPolicyNever,
					AutomountServiceAccountToken: ptr.To(false), // the build pod talks to no one but the registry and source-controller
					SecurityContext: &corev1.PodSecurityContext{
						FSGroup: ptr.To(int64(1000)),
					},
					Volumes: []corev1.Volume{{
						Name: "work",
						VolumeSource: corev1.VolumeSource{
							EmptyDir: &corev1.EmptyDirVolumeSource{
								SizeLimit: ptr.To(resourceQuantity("8Gi")),
							},
						},
					}},
					InitContainers: []corev1.Container{{
						Name:            "prepare",
						Image:           prepareImage,
						Command:         []string{"python3", "-c", prepareScript},
						Env:             prepareEnv,
						SecurityContext: nonRootSecurityContext(),
						VolumeMounts:    []corev1.VolumeMount{{Name: "work", MountPath: "/work"}},
					}},
					Containers: []corev1.Container{{
						Name:    "build",
						Image:   in.BuildKitImage,
						Command: []string{"/bin/sh", "-c", buildScript},
						Env:     buildEnv,
						SecurityContext: &corev1.SecurityContext{
							SeccompProfile:  &corev1.SeccompProfile{Type: corev1.SeccompProfileTypeUnconfined},
							AppArmorProfile: &corev1.AppArmorProfile{Type: corev1.AppArmorProfileTypeUnconfined},
							RunAsUser:       ptr.To(int64(1000)),
							RunAsGroup:      ptr.To(int64(1000)),
						},
						WorkingDir:               workingDir,
						TerminationMessagePolicy: corev1.TerminationMessageFallbackToLogsOnError,
						VolumeMounts:             []corev1.VolumeMount{{Name: "work", MountPath: "/work"}},
					}},
				},
			},
		},
	}
}

func mergeBuildArgs(spec v1alpha1.ContainerImageSpec, baseTag string) []string {
	args := make(map[string]string, len(spec.BuildArgs)+1)
	for k, v := range spec.BuildArgs {
		args[k] = v
	}
	if spec.BaseRef != nil && baseTag != "" {
		args["BASE_TAG"] = baseTag
	}
	keys := make([]string, 0, len(args))
	for k := range args {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	lines := make([]string, 0, len(keys))
	for _, k := range keys {
		lines = append(lines, k+"="+args[k])
	}
	return lines
}

func env(name, value string) corev1.EnvVar {
	return corev1.EnvVar{Name: name, Value: value}
}

func nonRootSecurityContext() *corev1.SecurityContext {
	return &corev1.SecurityContext{
		RunAsUser:  ptr.To(int64(1000)),
		RunAsGroup: ptr.To(int64(1000)),
	}
}

func marshalJSON(v any) string {
	var buf bytes.Buffer
	_ = json.NewEncoder(&buf).Encode(v)
	return strings.TrimSpace(buf.String())
}
