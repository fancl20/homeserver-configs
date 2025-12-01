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
    #!/bin/sh
    set -e

    KEEP_TAGS=3

    cleanup_old_tags() {
      repo_path="$1"
      tags_dir="$repo_path/_manifests/tags"

      if [ ! -d "$tags_dir" ]; then
        echo "No tags directory found at $tags_dir"
        return
      fi

      echo "Processing repository: $repo_path"

      # Remove old tags using tail to skip the first KEEP_TAGS tags
      ls -t "$tags_dir" 2>/dev/null | tail -n +$((KEEP_TAGS + 1)) | while read -r tag; do
        if [ -n "$tag" ]; then
          tag_path="$tags_dir/$tag"
          echo "    Removing old tag: $tag"
          rm -rf "$tag_path"
        fi
      done
    }

    run_cleanup() {
      echo "Starting registry cleanup at $(date)"

      for repo in /var/lib/registry/docker/registry/v2/repositories/*/*; do
        if [ -d "$repo" ]; then
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
