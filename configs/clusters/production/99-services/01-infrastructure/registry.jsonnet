local app = import '../app.libsonnet';
local images = import '../images.jsonnet';

app.Base('registry').Deployment()
.PodContainers([{
  image: images.registry,
  env: [
    { name: 'OTEL_TRACES_EXPORTER', value: 'none' },
    { name: 'REGISTRY_LOG_LEVEL', value: 'info' },
  ],
  volumeMounts: [
    { name: 'registry', mountPath: '/var/lib/registry' },
  ],
}, {
  name: 'cleanup',
  image: images.registry,
  command: ['/bin/sh', '-c', |||
    #!/bin/bash
    set -euo pipefail

    KEEP_TAGS=3

    cleanup_old_tags() {
      local repo_path="$1"
      local tags_dir="$repo_path/_manifests/tags"

      if [[ ! -d "$tags_dir" ]]; then
        echo "No tags directory found at $tags_dir"
        return
      fi

      echo "Processing repository: $repo_path"

      # Get all tags and sort by modification time (newest first)
      local tags=($(ls -t "$tags_dir" 2>/dev/null || true))

      if [[ ${#tags[@]} -le $KEEP_TAGS ]]; then
        echo "  Repository has ${#tags[@]} tags (<= $KEEP_TAGS), skipping cleanup"
        return
      fi

      echo "  Found ${#tags[@]} tags, keeping only $KEEP_TAGS most recent"

      # Remove old tags (keep the first KEEP_TAGS tags)
      for ((i=$KEEP_TAGS; i<${#tags[@]}; i++)); do
        local tag="${tags[$i]}"
        local tag_path="$tags_dir/$tag"

        echo "    Removing old tag: $tag"
        rm -rf "$tag_path"
      done
    }

    run_cleanup() {
      echo "Starting registry cleanup at $(date)"

      for repo in /var/lib/registry/docker/registry/v2/repositories/*/*; do
        if [[ -d "$repo" ]]; then
          cleanup_old_tags "$repo"
        fi
      done

      echo "Running garbage collection..."
      registry garbage-collect /etc/distribution/config.yml --delete-untagged=true

      echo "Registry cleanup completed at $(date)"
    }

    while true; do
      run_cleanup
      echo "Sleeping for 7 days until next cleanup..."
      sleep 604800
    done
  |||],
  volumeMounts: [
    { name: 'registry', mountPath: '/var/lib/registry' },
  ],
}])
.RunAsUser()
.PersistentVolumeClaim(spec={
  resources: {
    requests: { storage: '32Gi' },
  },
})
.Service({
  ports: [
    { name: 'http', protocol: 'TCP', port: 80, targetPort: 5000 },
  ],
})
.HTTPRoute()
