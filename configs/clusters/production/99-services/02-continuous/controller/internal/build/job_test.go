package build

import (
	"regexp"
	"strings"
	"testing"
	"time"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"

	"image-controller/api/v1alpha1"
	"image-controller/internal/config"
)

func testConfig() *config.Config {
	return &config.Config{
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
		MaxAttempts:             5,
	}
}

func TestTriggerKeyDeterminism(t *testing.T) {
	args := func(attempts int) string {
		return TriggerKey("continuous", "dae", "spechash", "main@sha1:abc", "testing-1", "", attempts)
	}
	if args(0) != args(0) {
		t.Fatal("same inputs must yield the same key")
	}
	if args(0) == args(1) {
		t.Fatal("attempt bump must change the key (Jobs are immutable)")
	}
	other := TriggerKey("continuous", "dae", "spechash2", "main@sha1:abc", "testing-1", "", 0)
	if other == args(0) {
		t.Fatal("spec change must change the key")
	}
	manual := TriggerKey("continuous", "dae", "spechash", "main@sha1:abc", "testing-1", "tok", 0)
	if manual == args(0) {
		t.Fatal("token change must change the key")
	}
}

func TestJobName(t *testing.T) {
	key := TriggerKey("continuous", "dae", "h", "r", "b", "", 0)
	name := JobName("dae", key)
	if !strings.HasPrefix(name, "dae-") || len(name) != len("dae-")+7 {
		t.Fatalf("job name %q must be <name>-<7 hex>", name)
	}
	if !regexp.MustCompile(`^dae-[0-9a-f]{7}$`).MatchString(name) {
		t.Fatalf("job name %q is not DNS-safe", name)
	}
	if JobName("dae", key) != name {
		t.Fatal("job name must be deterministic")
	}
}

func TestShortSHA(t *testing.T) {
	if got := ShortSHA("main@sha1:8fdae8812345"); got != "8fdae88" {
		t.Fatalf("ShortSHA = %q", got)
	}
	if got := ShortSHA("v1.2.3"); len(got) != 7 {
		t.Fatalf("fallback ShortSHA = %q", got)
	}
}

// TestBuildJobGolden pins the Job shape against the proven Argo template.
func TestBuildJobGolden(t *testing.T) {
	ci := &v1alpha1.ContainerImage{
		ObjectMeta: metav1.ObjectMeta{
			Name:      "dae",
			Namespace: "continuous",
			UID:       "test-uid",
		},
		Spec: v1alpha1.ContainerImageSpec{
			SourceRef: v1alpha1.SourceRef{Kind: "GitRepository", Name: "configs", Namespace: "flux-system"},
			Context:   "images/dae",
			Image:     "fancl20/dae",
			Tag:       "{{ version }}-{{ base }}",
			Update: &v1alpha1.UpdateSpec{
				Command:     []string{"python3", "update.py", "version"},
				VersionFile: "VERSION",
			},
			BaseRef:   &v1alpha1.PolicyRef{Name: "debian", Namespace: "flux-system"},
			BuildArgs: map[string]string{"FETCHER": "docker.io/library/python:3.14.2-slim"},
			Interval:  metav1.Duration{Duration: 10 * time.Minute},
		},
	}
	job := BuildJob(JobInput{
		ContainerImage: ci,
		TriggerKey:     TriggerKey("continuous", "dae", "h", "main@sha1:8fdae88", "testing-20260824", "", 0),
		SpecHash:       "h",
		ArtifactURL:    "http://source-controller.flux-system.svc.cluster.local./gitrepository/flux-system/configs/main@sha1:8fdae88.tar.gz",
		ArtifactDigest: "sha256:abc123",
		ArtifactRev:    "main@sha1:8fdae8812345678",
		BaseTag:        "testing-20260824",
		BuildKitImage:  "docker.io/moby/buildkit:v0.32.2-rootless",
		Config:         testConfig(),
		Now:            time.Date(2026, 8, 31, 3, 0, 0, 0, time.UTC),
	})

	if job.Namespace != "continuous" {
		t.Fatalf("job namespace = %q", job.Namespace)
	}
	if got := job.Labels[LabelContainerImage]; got != "continuous.dae" {
		t.Fatalf("job label = %q", got)
	}
	if job.Spec.Template.Labels[LabelContainerImage] != "continuous.dae" {
		t.Fatalf("pod label = %q", job.Spec.Template.Labels[LabelContainerImage])
	}
	if job.Annotations[AnnArtifactRevision] != "main@sha1:8fdae8812345678" {
		t.Fatalf("artifact revision annotation = %q", job.Annotations[AnnArtifactRevision])
	}
	if job.Annotations[AnnSpecHash] != "h" {
		t.Fatalf("spec hash annotation = %q", job.Annotations[AnnSpecHash])
	}
	if *job.Spec.BackoffLimit != 0 {
		t.Fatal("backoffLimit must be 0; the controller owns retries")
	}
	if *job.Spec.TTLSecondsAfterFinished != 86400 {
		t.Fatalf("ttl = %d", *job.Spec.TTLSecondsAfterFinished)
	}
	if *job.Spec.ActiveDeadlineSeconds != 3600 {
		t.Fatalf("deadline = %d", *job.Spec.ActiveDeadlineSeconds)
	}

	pod := job.Spec.Template.Spec
	if *pod.AutomountServiceAccountToken {
		t.Fatal("build pod must not mount a service account token")
	}
	if pod.RestartPolicy != "Never" {
		t.Fatalf("restart policy = %q", pod.RestartPolicy)
	}
	if len(pod.InitContainers) != 1 || len(pod.Containers) != 1 {
		t.Fatalf("want 1 init + 1 main container, got %d/%d", len(pod.InitContainers), len(pod.Containers))
	}

	prepare := pod.InitContainers[0]
	if prepare.Name != "prepare" || prepare.Image != "docker.io/library/python:3.14.2-slim" {
		t.Fatalf("prepare container = %s %s", prepare.Name, prepare.Image)
	}
	if len(prepare.Command) != 3 || prepare.Command[0] != "python3" || prepare.Command[1] != "-c" {
		t.Fatalf("prepare command = %v", prepare.Command)
	}
	if !strings.Contains(prepare.Command[2], "ARTIFACT_URL") {
		t.Fatal("prepare script missing")
	}
	prepareEnvs := envMap(prepare.Env)
	if prepareEnvs["ARTIFACT_DIGEST"] != "sha256:abc123" {
		t.Fatalf("digest env = %q", prepareEnvs["ARTIFACT_DIGEST"])
	}
	if prepareEnvs["UPDATE_CMD"] != `["python3","update.py","version"]` {
		t.Fatalf("update cmd env = %q", prepareEnvs["UPDATE_CMD"])
	}
	if prepareEnvs["VAR_SHA"] != "8fdae88" {
		t.Fatalf("sha env = %q", prepareEnvs["VAR_SHA"])
	}
	if prepareEnvs["VERSION_FILE"] != "VERSION" {
		t.Fatalf("version file env = %q", prepareEnvs["VERSION_FILE"])
	}
	if prepareEnvs["VERSION_LITERAL"] != "" {
		t.Fatalf("version literal env = %q", prepareEnvs["VERSION_LITERAL"])
	}

	build := pod.Containers[0]
	if build.Name != "build" || build.Image != "docker.io/moby/buildkit:v0.32.2-rootless" {
		t.Fatalf("build container = %s %s", build.Name, build.Image)
	}
	if build.WorkingDir != "/work/src/images/dae" {
		t.Fatalf("working dir = %q", build.WorkingDir)
	}
	if build.TerminationMessagePolicy != "FallbackToLogsOnError" {
		t.Fatalf("termination message policy = %q", build.TerminationMessagePolicy)
	}
	sc := build.SecurityContext
	if sc.SeccompProfile == nil || sc.SeccompProfile.Type != "Unconfined" {
		t.Fatal("build seccomp must be Unconfined")
	}
	if sc.AppArmorProfile == nil || sc.AppArmorProfile.Type != "Unconfined" {
		t.Fatal("build apparmor must be Unconfined")
	}
	if sc.RunAsUser == nil || *sc.RunAsUser != 1000 || sc.RunAsGroup == nil || *sc.RunAsGroup != 1000 {
		t.Fatal("build must run as uid/gid 1000 (rootless)")
	}
	buildEnvs := envMap(build.Env)
	if buildEnvs["BUILDKITD_FLAGS"] != "--oci-worker-no-process-sandbox" {
		t.Fatalf("buildkit flags = %q", buildEnvs["BUILDKITD_FLAGS"])
	}
	// BASE_TAG must be merged into BUILD_ARGS alongside spec.buildArgs.
	wantArgs := "BASE_TAG=testing-20260824\nFETCHER=docker.io/library/python:3.14.2-slim"
	if buildEnvs["BUILD_ARGS"] != wantArgs {
		t.Fatalf("build args = %q, want %q", buildEnvs["BUILD_ARGS"], wantArgs)
	}
	if !strings.Contains(build.Command[2], "buildctl-daemonless.sh") {
		t.Fatal("build script must invoke buildctl-daemonless.sh")
	}
	if !strings.Contains(build.Command[2], `--import-cache "type=registry,ref=$ref"`) {
		t.Fatal("cache must be imported from the pushed ref (name:tag), not a tag-less repo")
	}
	if !strings.Contains(build.Command[2], "/dev/termination-log") {
		t.Fatal("build script must report the pushed ref via termination log")
	}

	owner := job.OwnerReferences[0]
	if owner.Kind != "ContainerImage" || owner.Name != "dae" || owner.Controller == nil || !*owner.Controller {
		t.Fatalf("owner reference = %+v", owner)
	}
	if owner.BlockOwnerDeletion != nil && *owner.BlockOwnerDeletion {
		t.Fatal("blockOwnerDeletion must be false")
	}
}

// TestBuildJobOutOfNamespaceOwner covers a ContainerImage outside the build
// namespace: the Job carries no owner reference (the GC deletes dependents
// with cross-namespace owners) and the label stays unambiguous.
func TestBuildJobOutOfNamespaceOwner(t *testing.T) {
	ci := &v1alpha1.ContainerImage{
		ObjectMeta: metav1.ObjectMeta{Name: "dae", Namespace: "default", UID: "test-uid"},
		Spec: v1alpha1.ContainerImageSpec{
			SourceRef: v1alpha1.SourceRef{Kind: "GitRepository", Name: "configs", Namespace: "flux-system"},
			Context:   "images/dae",
			Image:     "fancl20/dae",
			Version:   "1.0.0",
			Interval:  metav1.Duration{Duration: 10 * time.Minute},
		},
	}
	job := BuildJob(JobInput{
		ContainerImage: ci,
		TriggerKey:     TriggerKey("default", "dae", "h", "main@sha1:8fdae88", "", "", 0),
		SpecHash:       "h",
		ArtifactRev:    "main@sha1:8fdae8812345678",
		BuildKitImage:  "docker.io/moby/buildkit:v0.32.2-rootless",
		Config:         testConfig(),
	})
	if len(job.OwnerReferences) != 0 {
		t.Fatalf("cross-namespace owner reference must be omitted, got %+v", job.OwnerReferences)
	}
	if got := job.Labels[LabelContainerImage]; got != "default.dae" {
		t.Fatalf("job label = %q", got)
	}
}

// TestTemplateVarParity guards against the Go validator and the Python
// renderer drifting apart.
func TestTemplateVarParity(t *testing.T) {
	goVars := []string{v1alpha1.TagVarVersion, v1alpha1.TagVarBase, v1alpha1.TagVarSHA, v1alpha1.TagVarDate}
	for _, v := range goVars {
		if !strings.Contains(prepareScript, `"`+v+`"`) {
			t.Errorf("prepare.py does not substitute %q", v)
		}
	}
	if !strings.Contains(prepareScript, "unresolved template variable") {
		t.Error("prepare.py must reject unresolved variables")
	}
}

func envMap(envs []corev1.EnvVar) map[string]string {
	out := make(map[string]string, len(envs))
	for _, e := range envs {
		out[e.Name] = e.Value
	}
	return out
}
