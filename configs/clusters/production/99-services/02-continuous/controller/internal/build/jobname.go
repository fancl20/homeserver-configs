package build

import (
	"crypto/sha256"
	"encoding/hex"
	"strconv"
	"strings"
)

// TriggerKey returns the deterministic hash identifying a build attempt. The
// same inputs always yield the same key, which makes Job creation idempotent
// (Jobs are immutable), and the attempts component gives retries a fresh name.
func TriggerKey(namespace, name, specHash, revision, baseTag, token string, attempts int) string {
	parts := []string{namespace, name, specHash, revision, baseTag, token, strconv.Itoa(attempts)}
	sum := sha256.Sum256([]byte(strings.Join(parts, "\x00")))
	return hex.EncodeToString(sum[:])
}

// JobName derives the build Job name from a ContainerImage name and trigger
// key: <name>-<first 7 hex chars>.
func JobName(name, triggerKey string) string {
	suffix := triggerKey
	if len(suffix) > 7 {
		suffix = suffix[:7]
	}
	return name + "-" + suffix
}
