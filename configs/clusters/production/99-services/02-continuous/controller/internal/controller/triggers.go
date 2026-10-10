package controller

import (
	"fmt"
	"regexp"
	"strings"
	"time"

	"github.com/robfig/cron/v3"

	"github.com/fluxcd/pkg/apis/meta"

	"image-controller/api/v1alpha1"
	"image-controller/internal/build"
)

// TriggerCause identifies why a build was triggered.
type TriggerCause string

const (
	TriggerFirst    TriggerCause = "first"
	TriggerSpec     TriggerCause = "spec"
	TriggerArtifact TriggerCause = "artifact"
	TriggerManual   TriggerCause = "manual"
	TriggerSchedule TriggerCause = "schedule"
	TriggerBase     TriggerCause = "base"
)

// Trigger is a pending reason to build.
type Trigger struct {
	Cause TriggerCause
	Token string
}

// EvaluateTrigger applies the trigger matrix: first build, spec change, new
// artifact revision, manual reconcile request, schedule tick, or base tag
// change. First match wins.
func EvaluateTrigger(ci *v1alpha1.ContainerImage, revision, baseTag string, now time.Time) *Trigger {
	switch {
	case ci.Status.LastBuiltRevision == "":
		return &Trigger{Cause: TriggerFirst}
	case build.SpecHash(ci.Spec) != ci.Status.LastSpecHash:
		return &Trigger{Cause: TriggerSpec}
	case revision != ci.Status.LastBuiltRevision && artifactChangesTag(ci, revision, baseTag):
		return &Trigger{Cause: TriggerArtifact}
	case manualRequested(ci) != "":
		return &Trigger{Cause: TriggerManual, Token: manualRequested(ci)}
	case scheduleDue(ci, now):
		// The token identifies the tick, so every night gets a fresh trigger
		// key (and Job name) even when the inputs are unchanged — otherwise
		// the previous night's completed Job, retained by its TTL, would
		// collide with the new one and swallow the tick.
		return &Trigger{Cause: TriggerSchedule, Token: ci.Status.NextScheduleRun.UTC().Format(time.RFC3339)}
	case ci.Spec.BaseRef != nil && baseTag != "" && baseTag != ci.Status.LastBaseTag:
		return &Trigger{Cause: TriggerBase}
	}
	return nil
}

// artifactChangesTag reports whether a build for the given revision would push
// a different tag than the last successful build. Static-version images whose
// rendered tag is unchanged are skipped: re-pushing an identical tag silently
// mutates its digest (defeating rollbacks) while the ImagePolicy sees no
// change, so nothing rolls out either. Update-command images always build —
// their version is discovered at build time, so the tag cannot be compared
// upfront.
func artifactChangesTag(ci *v1alpha1.ContainerImage, revision, baseTag string) bool {
	rendered := renderableTag(ci, revision, baseTag)
	return rendered == "" || rendered != ci.Status.LastTag
}

// renderableTag substitutes the tag template when every variable's value is
// known without building: static version, resolved base tag, and no {{ date }}
// (which is stamped at build time). It returns "" when the tag cannot be
// derived up front.
func renderableTag(ci *v1alpha1.ContainerImage, revision, baseTag string) string {
	if ci.Spec.Update != nil {
		return ""
	}
	template := ci.Spec.Tag
	if template == "" {
		template = "{{ " + v1alpha1.TagVarVersion + " }}"
	}
	variables := map[string]string{
		v1alpha1.TagVarVersion: ci.Spec.Version,
		v1alpha1.TagVarBase:    baseTag,
		v1alpha1.TagVarSHA:     build.ShortSHA(revision),
	}
	for _, match := range tagVarPattern.FindAllStringSubmatch(template, -1) {
		if match[1] == v1alpha1.TagVarDate {
			return ""
		}
	}
	rendered := tagVarPattern.ReplaceAllStringFunc(template, func(match string) string {
		return variables[tagVarPattern.FindStringSubmatch(match)[1]]
	})
	if strings.ContainsAny(rendered, "{}") {
		return ""
	}
	return rendered
}

// manualRequested returns the requestedAt annotation value when it has not
// been consumed yet (Flux's lastHandledReconcileAt convention).
func manualRequested(ci *v1alpha1.ContainerImage) string {
	requested := ci.Annotations[meta.ReconcileRequestAnnotation]
	if requested != "" && requested != ci.Status.LastHandledReconcileAt {
		return requested
	}
	return ""
}

// scheduleDue reports whether the schedule tick passed since the recorded
// next run. A nil NextScheduleRun is not due on its own; the controller seeds
// it on the next build or in-sync reconcile.
func scheduleDue(ci *v1alpha1.ContainerImage, now time.Time) bool {
	return ci.Spec.Schedule != "" &&
		ci.Status.NextScheduleRun != nil &&
		!now.Before(ci.Status.NextScheduleRun.Time)
}

var cronParser = cron.NewParser(cron.Minute | cron.Hour | cron.Dom | cron.Month | cron.Dow | cron.Descriptor)

// ParseSchedule validates a cron expression.
func ParseSchedule(spec string) error {
	_, err := cronParser.Parse(spec)
	return err
}

// NextScheduleRun computes the next fire time of spec in the given time zone.
func NextScheduleRun(spec, timeZone string, defaultLocation *time.Location, from time.Time) (time.Time, error) {
	schedule, err := cronParser.Parse(spec)
	if err != nil {
		return time.Time{}, fmt.Errorf("invalid schedule: %w", err)
	}
	location := defaultLocation
	if timeZone != "" {
		if loc, err := time.LoadLocation(timeZone); err == nil {
			location = loc
		}
	}
	return schedule.Next(from.In(location)), nil
}

// tagVarPattern matches a single template variable.
var tagVarPattern = regexp.MustCompile(`\{\{\s*([a-zA-Z]+)\s*\}\}`)

// ValidateSpec enforces the rules the CRD schema cannot express.
func ValidateSpec(spec *v1alpha1.ContainerImageSpec) string {
	switch {
	case spec.Context == "" || spec.Image == "":
		return "context and image are required"
	case strings.HasPrefix(spec.Context, "/") || strings.Contains(spec.Context, ".."):
		return "context must be a relative path inside the source artifact"
	case spec.Update != nil && spec.Version != "":
		return "update and version are mutually exclusive"
	case spec.Update == nil && spec.Version == "":
		return "one of update or version is required"
	case spec.Interval.Duration <= 0:
		return "interval must be positive"
	}
	if spec.Schedule != "" {
		if err := ParseSchedule(spec.Schedule); err != nil {
			return fmt.Sprintf("invalid schedule: %v", err)
		}
	}
	tag := spec.Tag
	if tag == "" {
		tag = "{{ version }}"
	}
	usesBase := false
	for _, match := range tagVarPattern.FindAllStringSubmatch(tag, -1) {
		switch match[1] {
		case v1alpha1.TagVarVersion:
		case v1alpha1.TagVarBase:
			usesBase = true
		case v1alpha1.TagVarSHA, v1alpha1.TagVarDate:
		default:
			return fmt.Sprintf("unknown template variable %q in tag", match[1])
		}
	}
	if usesBase && spec.BaseRef == nil {
		return "tag uses {{ base }} but baseRef is not set"
	}
	return ""
}
