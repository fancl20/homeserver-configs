package build

import (
	_ "embed"

	"k8s.io/apimachinery/pkg/api/resource"
)

// prepareScript runs in the build pod's init container (see prepare.py).
//
//go:embed prepare.py
var prepareScript string

// buildScript runs in the build container (busybox ash). It feeds BUILD_ARGS
// through a heredoc rather than a pipe so the accumulated positional
// parameters survive the loop's (sub)shell, and never evals anything. The
// inline cache is imported from the ref being pushed (which carries the cache
// of previous builds of the same tag).
const buildScript = `set -eu
ref="$REGISTRY_HOST/$IMAGE_NAME:$(cat "$TAG_FILE")"
echo "build: $ref"
set --
if [ -n "${BUILD_ARGS:-}" ]; then
  while IFS='=' read -r k v; do
    [ -n "$k" ] || continue
    set -- "$@" --opt "build-arg:$k=$v"
  done <<EOF
$BUILD_ARGS
EOF
fi
buildctl-daemonless.sh build \
  --frontend dockerfile.v0 \
  --local context=. \
  --local dockerfile=. \
  --output "type=image,name=$ref,push=true" \
  --export-cache type=inline \
  --import-cache "type=registry,ref=$ref" \
  "$@"
printf '%s' "$ref" > /dev/termination-log
`

func resourceQuantity(s string) resource.Quantity {
	return resource.MustParse(s)
}
