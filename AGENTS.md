# AGENTS.md - Global Guide for AI Agents

This document serves as a comprehensive guide for AI agents working with this homeserver configuration repository. It provides patterns, conventions, and instructions for making changes across different parts of the infrastructure.

## Table of Contents

- [Overview](#overview)
- [Directory Structure](#directory-structure)
- [Talos Configuration](#talos-configuration)
- [Image Management](#image-management)
- [Application Patterns](#application-patterns)
- [Infrastructure Patterns](#infrastructure-patterns)
- [Common Operations](#common-operations)

## Overview

This repository uses a multi-layered approach to infrastructure and application management:

1. **Components** (`configs/clusters/components/`) - Reusable components shared across clusters
2. **Stages** (`configs/clusters/production/00-stage/` through `05-stage/`) - Bootstrap and core infrastructure
3. **Services** (`configs/clusters/production/99-services/`) - Application manifests and infrastructure services
4. **Talos** (`configs/talos/`) - Talos OS configuration for cluster nodes

## Directory Structure

```
configs/
├── clusters/
│   ├── components/          # Reusable components
│   │   ├── images/          # Image automation
│   │   └── terraform/       # Terraform components
│   └── production/
│       ├── 00-stage/        # Bootstrap stage (Flux, Gateway API, MetalLB, Tofu Controller)
│       ├── 01-stage/        # Core infrastructure (1Password, MetalLB config, Vault)
│       ├── 02-stage/        # Security and networking (cert-manager, external-secrets, nginx-gateway)
│       ├── 03-stage/        # Workload management (Flux image-update, tofu-controller repos)
│       ├── 04-stage/        # Storage and workloads (Argo Workflows, Rook Ceph, Multus CNI)
│       ├── 05-stage/        # Network configuration (Multus macvlan, Rook Ceph cluster)
│       └── 99-services/     # Applications and services
│           ├── 00-libsonnet/    # Jsonnet libraries
│           ├── 01-infrastructure/ # Infrastructure services
│           ├── 02-continuous/    # CI/CD and automation
│           ├── 03-applications/  # User applications
│           └── generated/        # Generated manifests
├── talos/                   # Talos OS configuration
│   ├── configs/             # Node configuration files
│   │   ├── controlplane.yaml     # Control plane node config
│   │   ├── controlplane-network.yaml
│   │   ├── worker-p5.yaml        # CWWK P5 worker config
│   │   ├── worker-p5-network.yaml
│   │   ├── worker-14450hx.yaml   # Intel 14450HX worker config
│   │   ├── worker-14450hx-network.yaml
│   │   └── bootstrap/            # Bootstrap configurations
│   └── scripts/             # Management scripts
│       ├── bootstrap.sh     # Initial cluster bootstrap
│       ├── provision.sh     # Provision new worker nodes
│       ├── apply-config.sh  # Apply configuration changes
│       ├── wipe-user-disks.sh
│       └── rotate-ca.sh
└── edgerouter/              # Edge router configuration
```

## Talos Configuration

### Overview

The cluster runs on Talos OS, an immutable Linux distribution designed specifically for Kubernetes. The configuration is managed in `configs/talos/`.

### Node Types

| Node Type | Config File | Hardware | Notes |
|-----------|-------------|----------|-------|
| Control Plane | `controlplane.yaml` | Raspberry Pi CM4 | Runs on `/dev/mmcblk0` |
| Worker (P5) | `worker-p5.yaml` | CWWK P5 Mini PC | NVMe storage |
| Worker (14450HX) | `worker-14450hx.yaml` | Intel 14450HX | NVMe storage |

### Common Operations

#### Upgrade Nodes

```bash
# Upgrade worker nodes
talosctl upgrade -nodes 192.168.1.{4..7}

# Upgrade Kubernetes version on control plane
talosctl upgrade-k8s --nodes 192.168.1.3
```

#### Bootstrap New Cluster

```bash
cd configs/talos
./scripts/bootstrap.sh
```

#### Provision New Worker Node

```bash
cd configs/talos
./scripts/provision.sh --node 192.168.1.X --type p5 192.168.1.254
```

#### Debug Network Issues

```bash
talosctl -nodes 192.168.1.3 get addressspecs [ID] -o yaml
talosctl -nodes 192.168.1.3 get meta 0x0a
```

#### Wipe Disks for Rook Ceph

```bash
talosctl -n talos-lje-xo8 wipe disk $(talosctl -n 192.168.1.57 get disks | grep -v '256 GB' | awk '{print $4}' | grep nvme)
```

### Configuration Structure

Each node configuration includes:
- **machine.nodeLabels** - Kubernetes node labels for scheduling
- **machine.sysctls** - Kernel parameters (e.g., `user.max_user_namespaces`)
- **machine.install** - Installation settings (disk, image)
- **cluster.controlPlane** - Control plane endpoint

## Image Management

### Adding a New Image

When adding a new container image to the cluster, follow these steps:

#### Step 1: Add to `images.jsonnet`

Add the image definition to [`configs/clusters/production/99-services/images.jsonnet`](configs/clusters/production/99-services/images.jsonnet):

```jsonnet
app.Image('app-name')
.Repository('docker.io/namespace/image')
.Policy(app.DefaultPolicy.Semver())
```

#### Step 2: Add to `kustomization.yaml`

Add the pinned version to [`configs/clusters/components/images/kustomization.yaml`](configs/clusters/components/images/kustomization.yaml):

```yaml
- name: docker.io/namespace/image # {"$imagepolicy": "flux-system:app-name:name"}
  newTag: 'x.y.z' # {"$imagepolicy": "flux-system:app-name:tag"}
```

**Important**: Keep entries sorted by lexical order based on the image name in the jsonnet file.

#### Step 3: Generate and Verify

Run the generation script:
```bash
cd configs/clusters/production/99-services
python3 generate.py
```

### Image Policies

Available policies from `app.DefaultPolicy`:
- `.Semver(range='*', pattern='.*')` - Semantic versioning
- `.LinuxServer(range='*', pattern='.*-ls')` - LinuxServer images
- Custom policies can be defined as needed

### Custom Images

The repository includes custom images built and maintained in the `images/` directory:

| Image | Description | Registry |
|-------|-------------|----------|
| dae | Network proxy tool | `registry.local.d20.fan/fancl20/dae` |
| fava | Beancount web interface | `registry.local.d20.fan/fancl20/fava` |
| roon | Music server | `registry.local.d20.fan/fancl20/roon` |

## Application Patterns

### Directory Structure

Each application in `03-applications/` typically consists of:
- `<app-name>.jsonnet` - Main Jsonnet configuration file
- `<app-name>.tf` - Terraform configuration for secrets (optional)

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
- `.PodAnnotations(annotations)` - Adds pod annotations
- `.PodSecurityContext(securityContext)` - Sets pod security context
- `.RunAsUser(uid=1000, gid=1000)` - Convenience method for user/group IDs
- `.PersistentVolumeClaim(name, spec)` - Creates PVC and adds volume to pod
- `.Service(spec, name, external_dns, load_balancer_ip)` - Creates Service
- `.HTTPRoute(service, port, wildcard, metadata)` - Creates HTTPRoute for gateway
- `.OnePassword(name, spec)` - Creates ExternalSecret for 1Password integration
- `.DNSConfig(config)` - Configures custom DNS for pods
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

#### Application with Multus Network (Static IP)

For applications requiring static IP addresses via Multus CNI:

```jsonnet
app.Base('app-name').Deployment()
  .PodContainers([{
    image: images.app_name,
    // ...
  }])
  .PodAnnotations({
    'k8s.v1.cni.cncf.io/networks': std.manifestJson([
      {
        name: 'macvlan-static',
        ips: ['192.168.1.20/24'],
      },
    ]),
  })
  .DNSConfig({
    nameservers: ['8.8.8.8', '8.8.4.4'],
  })
```

## Infrastructure Patterns

### Infrastructure Services

Infrastructure services in `01-infrastructure/` follow similar patterns to applications but are focused on cluster services:

- **bind9** - DNS server
- **external-dns** - External DNS integration
- **registry** - Container registry
- **shared-data** - Shared PVC for data storage (4Ti)

### Terraform Integration

For applications requiring secrets (database passwords, API keys, etc.), use Terraform:

#### Terraform Pattern

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

#### Secret Usage in Jsonnet

```jsonnet
envFrom: [
  { secretRef: { name: 'app' } },
],
```

### Shared Volumes

The `shared-data` PVC provides shared storage accessible via `app.Volumes.shared_data`:

```jsonnet
volumeMounts: [
  { name: 'data', mountPath: '/data' },
],
volumes: [
  app.Volumes.shared_data,
],
```

## Common Operations

### Adding or Updating a Service

#### Step 1: Create Jsonnet Configuration

Create `<app-name>.jsonnet` following the patterns above.

#### Step 2: Add Terraform (if needed)

Create `<app-name>.tf` for secret management if the application requires credentials.

#### Step 3: Add Image Definition

Add the application's image to [`images.jsonnet`](configs/clusters/production/99-services/images.jsonnet).

#### Step 4: Update Kustomization

Add the image with current version to [`kustomization.yaml`](configs/clusters/components/images/kustomization.yaml).

#### Step 5: Generate and Verify

Run the generation script:
```bash
cd configs/clusters/production/99-services
python3 generate.py
```

Verify the generated files in `generated/03-applications/<app-name>/`.

### Naming Conventions

#### Resources
- **Services**: `<app-name>` or `<app-name>-<purpose>` (e.g., `n8n-postgres`)
- **StatefulSets**: `<app-name>-db` or `<app-name>-postgres`
- **PVCs**: `<app-name>` or `<app-name>-<purpose>`
- **Secrets**: `<app-name>` (shared between app and database)

#### Hostnames
- Default: `<app-name>.local.d20.fan`
- Set via `app.Base()` `Hostname` field in `app.libsonnet`

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
11. **Keep `kustomization.yaml` sorted** by lexical order based on image name

## Existing Applications

| Application | Type | Database | Notes |
|-------------|------|----------|-------|
| beets | Deployment | - | Music library |
| calibre | Deployment | - | eBook library |
| coder | Helm | PostgreSQL | Code server |
| dae | Deployment | - | Network proxy (Multus static IP) |
| jellyfin | Deployment | - | Media server |
| n8n | StatefulSet | PostgreSQL (sidecar) | Workflow automation |
| paperless | Deployment | - | Document management |
| qbittorrent | Deployment | - | Torrent client |
| roon | Deployment | - | Music server (custom image) |
| sftp | Deployment | - | SFTP server |
| unifi | Deployment | MongoDB (sidecar) | Network management |
| velero | Helm | - | Backup tool |
| youtrack | Deployment | - | Issue tracker |
