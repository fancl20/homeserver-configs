---
display_name: Kubernetes (Devcontainer)
description: Provision Docker-in-Docker pods as Coder workspaces running dev containers
icon: /icon/k8s.png
maintainer_github: coder
verified: true
tags: [container, kubernetes, devcontainer]
---

# Remote Development on Kubernetes Pods (with Dev Containers)

Provision workspaces on Kubernetes that run `devcontainer.json` environments with
Coder's [Dev Containers integration](https://coder.com/docs/admin/integrations/devcontainers):
the `@devcontainers/cli` and a Docker daemon run inside the workspace, and dev
containers are built and run on top of it.

## Prerequisites

### Infrastructure

**Cluster**: This template requires an existing Kubernetes cluster.

**Container Image**: The `workspace_image` parameter defaults to
`registry.local.d20.fan/fancl20/coder-devcontainer-base`, built in-cluster by its
[`ContainerImage` CR](../../../02-continuous/container-images.yaml) from
[`images/coder-devcontainer-base/`](../../../../../../../images/coder-devcontainer-base/).
It ships the Docker daemon (with `data-root` on the `/workspaces` volume), Node.js
for `@devcontainers/cli` (installed at start by the
[devcontainers-cli module](https://registry.coder.com/modules/devcontainers-cli)),
and the coder CLI. Rebuilds follow the Debian base tag;
bump the version in `update.py` for Dockerfile changes.

### Authentication

This template authenticates using a `~/.kube/config`, if present on the server, or via built-in authentication if the Coder provisioner is running on Kubernetes with an authorized ServiceAccount. To use another [authentication method](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs#authentication), edit the template.

## Kubernetes Access

Workspace pods run as the `coder-workspace` ServiceAccount in the `coder` namespace
(defined in [`../coderd.yaml`](../coderd.yaml)), bound to the built-in `view`
ClusterRole for cluster-wide read-only access. Existing workspaces pick this up after a
restart once the template is updated.

## Architecture

The workspace pod runs the base image directly with `NET_ADMIN` and `SYS_ADMIN`
capabilities, which the Docker daemon needs for the `docker0` bridge and overlay
mounts. The agent startup script starts the daemon; its data-root lives on the
`/workspaces` PVC so image layers persist across workspace restarts (the container
root is overlayfs, which the overlay2 storage driver cannot layer on).

This template provisions the following resources:

- Kubernetes deployment (ephemeral)
- Kubernetes persistent volume claim (persistent on `/workspaces`)

The `repo` parameter is cloned into `/workspaces` by the
[git-clone module](https://registry.coder.com/modules/git-clone); private repos
authenticate with the workspace owner's Coder SSH key (`coder gitssh`). A
`coder_devcontainer` resource then runs the
repo's `devcontainer.json` and creates a sub-agent inside it; the dashboard manages
its lifecycle (status, rebuild), so `devcontainer.json` changes no longer require
recreating the workspace. Additional dev containers can be added from the dashboard.

The main agent (terminals, VS Code, Claude Code) runs in the base image, not inside
the dev container; if the dev container build fails the workspace stays usable in
the base environment.

> **Note**
> This template is designed to be a starting point! Edit the Terraform to extend the template to support your use case.
