# 03-applications - Agent Documentation

This directory contains Kubernetes application manifests defined using Jsonnet, following the project's standard patterns.

## Directory Structure

Each application typically consists of:
- `<app-name>.jsonnet` - Main Jsonnet configuration file
- `<app-name>.tf` - Terraform configuration for secrets (optional, if needed)

## Jsonnet Organization

### Base Pattern

All applications follow a consistent pattern using the `app.Base()` helper:

```jsonnet
local app = import '../app.libsonnet';
local images = import '../images.jsonnet';

app.Base('app-name').Deployment()
  .PodContainers([{
    // Container configuration
  }])
  .PersistentVolumeClaim()
  .Service({ /* ports */ })
  .HTTPRoute()
```

### Available Methods

From `app.Base()`:
- `.Deployment()` - Creates a Deployment resource
- `.StatefulSet(service_name=name)` - Creates a StatefulSet resource
- `.Helm(repo, chart, values)` - Creates HelmRelease and HelmRepository (for chart-based deployments)
- `.Nested(name)` - Creates nested resources (e.g., for databases)
- `.PodContainers(containers)` - Configures pod containers
- `.PodInitContainers(containers)` - Configures init containers
- `.PodVolumes(volumes)` - Adds volumes to pod spec
- `.PersistentVolumeClaim(name, spec)` - Creates PVC and adds volume to pod
- `.Service(spec, name, external_dns, load_balancer_ip)` - Creates Service
- `.HTTPRoute(service, port, wildcard, metadata)` - Creates HTTPRoute for gateway
- `.OnePassword(name, spec)` - Creates ExternalSecret for 1Password integration
- `.Role(name, rules)` - Creates Role/RoleBinding for RBAC
- `.Kustomize()` - Enables Kustomize features (ConfigMap, etc.)
- `.Config(file, content)` - Creates ConfigMap from file content

### Common Patterns

#### Simple Application (Single Container)

```jsonnet
app.Base('app-name').Deployment()
  .PodContainers([{
    image: images.app_name,
    env: [ /* environment variables */ ],
    volumeMounts: [ /* volume mounts */ ],
  }])
  .PersistentVolumeClaim()
  .Service({ ports: [ /* ports */ ] })
  .HTTPRoute()
```

#### Application with Sidecar Database

For applications that don't require database replication, use a StatefulSet with the database as a sidecar container in the same Pod:

```jsonnet
app.Base('app-name').StatefulSet()
  .PodContainers([
    {
      name: 'app-name',
      image: images.app_name,
      env: [
        { name: 'DB_HOST', value: '127.0.0.1' },
        { name: 'DB_PORT', value: '5432' },
      ],
      envFrom: [
        { secretRef: { name: 'app-name' } },
      ],
      volumeMounts: [
        { name: 'app-name', mountPath: '/app/data', subPath: 'app' },
      ],
    },
    {
      name: 'postgres',
      image: images.postgres,
      env: [
        { name: 'POSTGRES_DB', value: 'appname' },
      ],
      envFrom: [
        { secretRef: { name: 'app-name' } },
      ],
      volumeMounts: [
        { name: 'app-name', mountPath: '/var/lib/postgresql/data', subPath: 'db' },
      ],
    },
  ])
  .PersistentVolumeClaim()
  .Service({ ports: [ /* app ports */ ] })
  .HTTPRoute()
```

#### Application with Separate Database

For applications requiring a separate database deployment (e.g., for scaling or shared access):

```jsonnet
app.Base('app-name').Deployment()
  .PodContainers([{
    image: images.app_name,
    env: [
      { name: 'DB_HOST', value: 'db-service.default.svc.cluster.local' },
    ],
    envFrom: [
      { secretRef: { name: 'app-name' } },
    ],
  }])
  .PersistentVolumeClaim()
  .Service({ ports: [ /* ports */ ] })
  .HTTPRoute()
  .Nested('app-db').StatefulSet()
  .PodContainers([{
    name: 'postgres',
    image: images.postgres,
    envFrom: [
      { secretRef: { name: 'app-name' } },
    ],
    volumeMounts: [
      { name: 'app-db', mountPath: '/var/lib/postgresql/data' },
    ],
  }])
  .PersistentVolumeClaim()
  .Service({ ports: [ /* postgres ports */ ] })
```

#### Helm-based Application

```jsonnet
app.Base('app-name', 'app-name', create_namespace=true).Helm('https://helm.example.com', 'chart-name', {
  chart: {
    // Helm values
  },
})
.HTTPRoute()
```

## Terraform Integration

For applications requiring secrets (database passwords, API keys, etc.), use Terraform:

### Terraform Pattern

```hcl
resource "random_password" "app_db" {
  length = 32
  special = false
}

resource "kubernetes_secret_v1" "app" {
  metadata {
    name      = "app"
    namespace = "default"
  }
  data = {
    DB_USER     = "app"
    DB_PASSWORD = random_password.app_db.result
    # Additional keys as needed
  }
}
```

### Secret Usage in Jsonnet

```jsonnet
envFrom: [
  { secretRef: { name: 'app' } },
],
```

## Image Management

### Adding a New Image

1. **Add to [`images.jsonnet`](../images.jsonnet)**:
   ```jsonnet
   app.Image('app-name')
   .Repository('docker.io/namespace/image')
   .Policy(app.DefaultPolicy.Semver())
   ```

2. **Add to [`kustomization.yaml`](../../components/images/kustomization.yaml)**:
   ```yaml
   - name: docker.io/namespace/image # {"$imagepolicy": "flux-system:app-name:name"}
     newTag: 'x.y.z' # {"$imagepolicy": "flux-system:app-name:tag"}
   ```

### Image Policies

Available policies from `app.DefaultPolicy`:
- `.Semver(range='*', pattern='.*')` - Semantic versioning
- `.LinuxServer(range='*', pattern='.*-ls')` - LinuxServer images
- Custom policies can be defined as needed

## Naming Conventions

### Resources
- **Services**: `<app-name>` or `<app-name>-<purpose>` (e.g., `n8n-postgres`)
- **StatefulSets**: `<app-name>-db` or `<app-name>-postgres`
- **PVCs**: `<app-name>` or `<app-name>-<purpose>`
- **Secrets**: `<app-name>` (shared between app and database)

### Hostnames
- Default: `<app-name>.local.d20.fan`
- Set via `app.Base()` `Hostname` field in `app.libsonnet`

## Adding or Updating a Service

### Step 1: Create Jsonnet Configuration

Create `<app-name>.jsonnet` following the patterns above.

### Step 2: Add Terraform (if needed)

Create `<app-name>.tf` for secret management if the application requires credentials.

### Step 3: Add Image Definition

Add the application's image to [`images.jsonnet`](../images.jsonnet).

### Step 4: Update Kustomization

Add the image with current version to [`kustomization.yaml`](../../components/images/kustomization.yaml).

### Step 5: Generate and Verify

Run the generation script:
```bash
cd configs/clusters/production/99-services
python3 generate.py
```

Verify the generated files in `generated/03-applications/<app-name>/`.

## Best Practices

1. **Use `envFrom` for secrets** instead of individual `valueFrom` entries when possible
2. **Keep database in same namespace** as the application for simpler networking
3. **Use sidecar databases** (StatefulSet with multiple containers) for single-replica applications to simplify deployment and networking
4. **Use `Nested()` for related resources** (databases, sidecars) instead of separate files when resources need to be deployed separately
5. **Use `subPath`** when multiple containers share the same PVC to avoid conflicts
6. **Follow naming conventions** consistently across resources
7. **Document external dependencies** (databases, caches) in this file
8. **Use `PersistentVolumeClaim()`** helper for storage to ensure consistent volume naming
9. **Add `HTTPRoute()`** for all web-facing applications
10. **Use `create_namespace=true`** only when the application needs its own namespace

## Existing Applications

| Application | Type | Database | Notes |
|-------------|------|----------|--------|
| beets | Deployment | - | Music library |
| calibre | Deployment | - | eBook library |
| coder | Helm | PostgreSQL | Code server |
| dae | Deployment | - | Network tool |
| jellyfin | Deployment | - | Media server |
| n8n | StatefulSet | PostgreSQL (sidecar) | Workflow automation |
| paperless | Deployment | - | Document management |
| qbittorrent | Deployment | - | Torrent client |
| roon | Deployment | - | Music server |
| sftp | Deployment | - | SFTP server |
| unifi | Deployment | MongoDB (sidecar) | Network management |
| velero | Helm | - | Backup tool |
| youtrack | Deployment | - | Issue tracker |

## Troubleshooting

### Common Issues

**Issue**: Generated files don't appear
- **Solution**: Check that the `.jsonnet` file is valid and doesn't have syntax errors

**Issue**: Image not updating
- **Solution**: Verify the image is added to both `images.jsonnet` and `kustomization.yaml`

**Issue**: Database connection fails
- **Solution**: Check that service names match between Deployment and StatefulSet, and that secrets are properly configured

**Issue**: HTTPRoute not working
- **Solution**: Verify the Gateway exists and that the hostname matches DNS configuration
