// Package config holds the controller's runtime configuration.
package config

import (
	"flag"
	"fmt"
	"time"
)

// Config is the resolved controller configuration.
type Config struct {
	// RegistryHost is the registry images are pushed to (also the host the
	// kubelet pulls from).
	RegistryHost string

	// BuildNamespace is where build Jobs are created.
	BuildNamespace string

	// Location is the default time zone for schedules and date template vars.
	Location *time.Location

	// PrepareImage is the default image for the prepare init container and
	// update commands (python).
	PrepareImage string

	// BuildKitRepo is the buildkit image repository; the tag is resolved from
	// BuildKitImagePolicy.
	BuildKitRepo string

	// BuildKitPolicyNamespace and BuildKitPolicyName select the ImagePolicy
	// tracking the buildkit image.
	BuildKitPolicyNamespace string
	BuildKitPolicyName      string

	// BuildKitFallbackImage is used when the policy has no latestRef yet.
	BuildKitFallbackImage string

	// JobTTL is ttlSecondsAfterFinished for build Jobs.
	JobTTL time.Duration

	// JobTimeout is the default activeDeadlineSeconds for build Jobs.
	JobTimeout time.Duration

	// MaxAttempts is the retry budget per trigger before backing off to the
	// interval.
	MaxAttempts int

	// ConcurrentBuilds is MaxConcurrentReconciles.
	ConcurrentBuilds int
}

// FromFlags parses command line flags into a Config.
func FromFlags(fs *flag.FlagSet, args []string) (*Config, error) {
	var (
		registryHost   = fs.String("registry-host", "registry.local.d20.fan", "registry images are pushed to")
		buildNamespace = fs.String("build-namespace", "continuous", "namespace build Jobs run in")
		timeZone       = fs.String("timezone", "Australia/Sydney", "default time zone for schedules and dates")
		prepareImage   = fs.String("prepare-image", "docker.io/library/python:3.14.2-slim", "image for the prepare init container")
		buildkitRepo   = fs.String("buildkit-repo", "docker.io/moby/buildkit", "buildkit image repository")
		buildkitPolicy = fs.String("buildkit-image-policy", "flux-system/buildkit", "ImagePolicy tracking the buildkit image tag (namespace/name)")
		buildkitPinned = fs.String("buildkit-image", "docker.io/moby/buildkit:v0.32.2-rootless", "buildkit image used when the policy has no tag yet")
		jobTTL         = fs.Duration("job-ttl", 24*time.Hour, "how long finished build Jobs are kept")
		jobTimeout     = fs.Duration("job-timeout", time.Hour, "default build timeout")
		maxAttempts    = fs.Int("max-attempts", 5, "build retries per trigger")
		concurrent     = fs.Int("concurrent-builds", 4, "concurrent reconciles")
	)
	if err := fs.Parse(args); err != nil {
		return nil, err
	}

	loc, err := time.LoadLocation(*timeZone)
	if err != nil {
		return nil, fmt.Errorf("invalid --timezone: %w", err)
	}

	policyNamespace, policyName, ok := splitNamespacedName(*buildkitPolicy)
	if !ok {
		return nil, fmt.Errorf("invalid --buildkit-image-policy %q: want namespace/name", *buildkitPolicy)
	}

	return &Config{
		RegistryHost:            *registryHost,
		BuildNamespace:          *buildNamespace,
		Location:                loc,
		PrepareImage:            *prepareImage,
		BuildKitRepo:            *buildkitRepo,
		BuildKitPolicyNamespace: policyNamespace,
		BuildKitPolicyName:      policyName,
		BuildKitFallbackImage:   *buildkitPinned,
		JobTTL:                  *jobTTL,
		JobTimeout:              *jobTimeout,
		MaxAttempts:             *maxAttempts,
		ConcurrentBuilds:        *concurrent,
	}, nil
}

func splitNamespacedName(s string) (string, string, bool) {
	for i := 0; i < len(s); i++ {
		if s[i] == '/' {
			if i == 0 || i == len(s)-1 || contains(s[i+1:], '/') {
				return "", "", false
			}
			return s[:i], s[i+1:], true
		}
	}
	return "", "", false
}

func contains(s string, c byte) bool {
	for i := 0; i < len(s); i++ {
		if s[i] == c {
			return true
		}
	}
	return false
}
