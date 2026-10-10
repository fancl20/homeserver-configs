package controller

import (
	"testing"
	"time"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"

	fluxmeta "github.com/fluxcd/pkg/apis/meta"

	"image-controller/api/v1alpha1"
	"image-controller/internal/build"
)

// triggerCI returns the standard test ContainerImage with the status starting
// in sync with the spec (LastSpecHash snapshotted before the mutation runs),
// so the spec trigger only fires for subtests that change the spec. Subtests
// building a differently-shaped spec can re-sync by setting LastSpecHash to
// build.SpecHash of their final spec.
func triggerCI(mutate func(*v1alpha1.ContainerImage)) *v1alpha1.ContainerImage {
	ci := &v1alpha1.ContainerImage{
		ObjectMeta: metav1.ObjectMeta{Name: "dae", Namespace: "continuous", Generation: 1},
		Spec: v1alpha1.ContainerImageSpec{
			SourceRef: v1alpha1.SourceRef{Kind: "GitRepository", Name: "configs", Namespace: "flux-system"},
			Context:   "images/dae",
			Image:     "fancl20/dae",
			Tag:       "{{ version }}-{{ base }}",
			Update: &v1alpha1.UpdateSpec{
				Command:     []string{"python3", "update.py", "version"},
				VersionFile: "VERSION",
			},
			BaseRef:  &v1alpha1.PolicyRef{Name: "debian", Namespace: "flux-system"},
			Interval: metav1.Duration{Duration: 10 * time.Minute},
			Schedule: "0 3 * * *",
			TimeZone: "Australia/Sydney",
		},
	}
	ci.Status.LastSpecHash = build.SpecHash(ci.Spec)
	if mutate != nil {
		mutate(ci)
	}
	return ci
}

func TestEvaluateTriggerMatrix(t *testing.T) {
	now := time.Date(2026, 8, 31, 12, 0, 0, 0, time.UTC)
	revision := "main@sha1:8fdae8812345678"

	t.Run("first build", func(t *testing.T) {
		if got := EvaluateTrigger(triggerCI(nil), revision, "testing-1", now); got == nil || got.Cause != TriggerFirst {
			t.Fatalf("want first trigger, got %+v", got)
		}
	})

	t.Run("no trigger when in sync", func(t *testing.T) {
		ci := triggerCI(func(ci *v1alpha1.ContainerImage) {
			ci.Status.LastBuiltRevision = revision
			ci.Status.LastBaseTag = "testing-1"
			ci.Status.NextScheduleRun = ptrTime(now.Add(12 * time.Hour))
		})
		if got := EvaluateTrigger(ci, revision, "testing-1", now); got != nil {
			t.Fatalf("want no trigger, got %+v", got)
		}
	})

	t.Run("artifact revision change", func(t *testing.T) {
		ci := triggerCI(func(ci *v1alpha1.ContainerImage) {
			ci.Status.LastBuiltRevision = "main@sha1:older"
		})
		got := EvaluateTrigger(ci, revision, "testing-1", now)
		if got == nil || got.Cause != TriggerArtifact {
			t.Fatalf("want artifact trigger, got %+v", got)
		}
	})

	t.Run("manual request", func(t *testing.T) {
		ci := triggerCI(func(ci *v1alpha1.ContainerImage) {
			ci.Status.LastBuiltRevision = revision
			ci.Annotations = map[string]string{
				fluxmeta.ReconcileRequestAnnotation: "2026-08-31T12:00:00Z",
			}
		})
		got := EvaluateTrigger(ci, revision, "testing-1", now)
		if got == nil || got.Cause != TriggerManual {
			t.Fatalf("want manual trigger, got %+v", got)
		}
		if got.Token != "2026-08-31T12:00:00Z" {
			t.Fatalf("manual trigger token = %q", got.Token)
		}
	})

	t.Run("manual request already handled", func(t *testing.T) {
		ci := triggerCI(func(ci *v1alpha1.ContainerImage) {
			ci.Status.LastBuiltRevision = revision
			ci.Status.LastBaseTag = "testing-1"
			ci.Status.NextScheduleRun = ptrTime(now.Add(12 * time.Hour))
			ci.Status.LastHandledReconcileAt = "2026-08-31T12:00:00Z"
			ci.Annotations = map[string]string{
				fluxmeta.ReconcileRequestAnnotation: "2026-08-31T12:00:00Z",
			}
		})
		if got := EvaluateTrigger(ci, revision, "testing-1", now); got != nil {
			t.Fatalf("want no trigger for consumed request, got %+v", got)
		}
	})

	t.Run("schedule tick", func(t *testing.T) {
		due := now.Add(-time.Minute)
		ci := triggerCI(func(ci *v1alpha1.ContainerImage) {
			ci.Status.LastBuiltRevision = revision
			ci.Status.LastBaseTag = "testing-1"
			ci.Status.NextScheduleRun = ptrTime(due)
		})
		got := EvaluateTrigger(ci, revision, "testing-1", now)
		if got == nil || got.Cause != TriggerSchedule {
			t.Fatalf("want schedule trigger, got %+v", got)
		}
		// The tick identifies the trigger: each night gets a fresh key and
		// Job name, even when the inputs are unchanged.
		if want := due.UTC().Format(time.RFC3339); got.Token != want {
			t.Fatalf("schedule trigger token = %q, want %q", got.Token, want)
		}
	})

	t.Run("schedule not seeded is not due", func(t *testing.T) {
		ci := triggerCI(func(ci *v1alpha1.ContainerImage) {
			ci.Status.LastBuiltRevision = revision
			ci.Status.LastBaseTag = "testing-1"
		})
		if got := EvaluateTrigger(ci, revision, "testing-1", now); got != nil {
			t.Fatalf("want no trigger with unseeded schedule, got %+v", got)
		}
	})

	t.Run("base tag change", func(t *testing.T) {
		ci := triggerCI(func(ci *v1alpha1.ContainerImage) {
			ci.Status.LastBuiltRevision = revision
			ci.Status.LastBaseTag = "testing-1"
			ci.Status.NextScheduleRun = ptrTime(now.Add(12 * time.Hour))
		})
		got := EvaluateTrigger(ci, revision, "testing-2", now)
		if got == nil || got.Cause != TriggerBase {
			t.Fatalf("want base trigger, got %+v", got)
		}
	})

	t.Run("artifact change wins over base change", func(t *testing.T) {
		ci := triggerCI(func(ci *v1alpha1.ContainerImage) {
			ci.Status.LastBuiltRevision = "main@sha1:older"
			ci.Status.LastBaseTag = "testing-1"
		})
		got := EvaluateTrigger(ci, revision, "testing-2", now)
		if got == nil || got.Cause != TriggerArtifact {
			t.Fatalf("want artifact trigger to win, got %+v", got)
		}
	})

	t.Run("spec change", func(t *testing.T) {
		ci := triggerCI(func(ci *v1alpha1.ContainerImage) {
			ci.Status.LastBuiltRevision = revision
			ci.Status.LastBaseTag = "testing-1"
			ci.Status.NextScheduleRun = ptrTime(now.Add(12 * time.Hour))
			ci.Spec.BuildArgs = map[string]string{"FETCHER": "docker.io/library/python:3.14.2-slim"}
		})
		if got := EvaluateTrigger(ci, revision, "testing-1", now); got == nil || got.Cause != TriggerSpec {
			t.Fatalf("want spec trigger, got %+v", got)
		}
	})

	t.Run("static version: artifact change with identical tag is skipped", func(t *testing.T) {
		// The image-controller case: version 0.1.0 + unchanged debian base
		// render the same tag for every revision; rebuilding would silently
		// mutate the pushed digest with nothing rolling out.
		ci := triggerCI(func(ci *v1alpha1.ContainerImage) {
			ci.Spec.Update = nil
			ci.Spec.Version = "0.1.0"
			ci.Status.LastSpecHash = build.SpecHash(ci.Spec)
			ci.Status.LastBuiltRevision = "main@sha1:older"
			ci.Status.LastBaseTag = "testing-1"
			ci.Status.LastTag = "0.1.0-testing-1"
			ci.Status.NextScheduleRun = ptrTime(now.Add(12 * time.Hour))
		})
		if got := EvaluateTrigger(ci, revision, "testing-1", now); got != nil {
			t.Fatalf("want no trigger for an unchanged rendered tag, got %+v", got)
		}
	})

	t.Run("static version: artifact change with a new tag builds", func(t *testing.T) {
		ci := triggerCI(func(ci *v1alpha1.ContainerImage) {
			ci.Spec.Update = nil
			ci.Spec.Version = "0.1.1"
			ci.Status.LastBuiltRevision = "main@sha1:older"
			ci.Status.LastBaseTag = "testing-1"
			ci.Status.LastTag = "0.1.0-testing-1"
			ci.Status.NextScheduleRun = ptrTime(now.Add(12 * time.Hour))
		})
		got := EvaluateTrigger(ci, revision, "testing-1", now)
		if got == nil || got.Cause != TriggerSpec {
			t.Fatalf("want spec trigger (new version), got %+v", got)
		}
	})

	t.Run("static version: artifact change building a different tag", func(t *testing.T) {
		ci := triggerCI(func(ci *v1alpha1.ContainerImage) {
			ci.Spec.Update = nil
			ci.Spec.Version = "0.1.0"
			ci.Status.LastSpecHash = build.SpecHash(ci.Spec)
			ci.Status.LastBuiltRevision = "main@sha1:older"
			ci.Status.LastBaseTag = "testing-1"
			ci.Status.LastTag = "0.1.0-testing-1"
			ci.Status.NextScheduleRun = ptrTime(now.Add(12 * time.Hour))
		})
		got := EvaluateTrigger(ci, revision, "testing-2", now)
		if got == nil || got.Cause != TriggerArtifact {
			t.Fatalf("want artifact trigger (base moved the rendered tag), got %+v", got)
		}
	})

	t.Run("static version: sha tags always build on revision change", func(t *testing.T) {
		ci := triggerCI(func(ci *v1alpha1.ContainerImage) {
			ci.Spec.Update = nil
			ci.Spec.Version = "0.1.0"
			ci.Spec.Tag = "{{ version }}-{{ sha }}"
			ci.Spec.BaseRef = nil
			ci.Status.LastSpecHash = build.SpecHash(ci.Spec)
			ci.Status.LastBuiltRevision = "main@sha1:older"
			ci.Status.LastTag = "0.1.0-olderab"
			ci.Status.NextScheduleRun = ptrTime(now.Add(12 * time.Hour))
		})
		got := EvaluateTrigger(ci, revision, "", now)
		if got == nil || got.Cause != TriggerArtifact {
			t.Fatalf("want artifact trigger (sha tag moves with the revision), got %+v", got)
		}
	})
}

func TestValidateSpec(t *testing.T) {
	cases := []struct {
		name        string
		mutate      func(*v1alpha1.ContainerImageSpec)
		wantInvalid bool
	}{
		{"valid with update", nil, false},
		{"valid with static version", func(s *v1alpha1.ContainerImageSpec) {
			s.Update = nil
			s.Version = "0.1.0"
		}, false},
		{"update and version are exclusive", func(s *v1alpha1.ContainerImageSpec) {
			s.Version = "0.1.0"
		}, true},
		{"neither update nor version", func(s *v1alpha1.ContainerImageSpec) {
			s.Update = nil
		}, true},
		{"context must not escape", func(s *v1alpha1.ContainerImageSpec) {
			s.Context = "../elsewhere"
		}, true},
		{"unknown template variable", func(s *v1alpha1.ContainerImageSpec) {
			s.Tag = "{{ flavour }}"
		}, true},
		{"base variable without baseRef", func(s *v1alpha1.ContainerImageSpec) {
			s.BaseRef = nil
		}, true},
		{"sha and date variables allowed", func(s *v1alpha1.ContainerImageSpec) {
			s.Tag = "{{ version }}-{{ sha }}-{{ date }}"
			s.BaseRef = nil
		}, false},
		{"bad schedule", func(s *v1alpha1.ContainerImageSpec) {
			s.Schedule = "not a cron"
		}, true},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			ci := triggerCI(nil)
			if tc.mutate != nil {
				tc.mutate(&ci.Spec)
			}
			got := ValidateSpec(&ci.Spec)
			if tc.wantInvalid && got == "" {
				t.Fatal("want validation error, got none")
			}
			if !tc.wantInvalid && got != "" {
				t.Fatalf("want valid, got %q", got)
			}
		})
	}
}

func TestNextScheduleAcrossDST(t *testing.T) {
	sydney, err := time.LoadLocation("Australia/Sydney")
	if err != nil {
		t.Skip("tzdata unavailable")
	}
	// 2026-04-05 03:00 AEDT -> 02:00 AEST; a 03:00 cron on that Sunday runs
	// once, in AEST.
	before := time.Date(2026, 4, 4, 12, 0, 0, 0, sydney)
	next, err := NextScheduleRun("0 3 * * *", "Australia/Sydney", sydney, before)
	if err != nil {
		t.Fatal(err)
	}
	want := time.Date(2026, 4, 5, 3, 0, 0, 0, sydney)
	if !next.Equal(want) {
		t.Fatalf("next = %v, want %v", next, want)
	}
}

func ptrTime(t time.Time) *metav1.Time {
	return &metav1.Time{Time: t}
}
