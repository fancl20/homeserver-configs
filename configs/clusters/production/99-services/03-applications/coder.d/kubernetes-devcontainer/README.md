---
display_name: Kubernetes (Devcontainer)
description: Provision Docker-in-Docker pods as Coder workspaces running dev containers
icon: /icon/k8s.png
maintainer_github: coder
verified: true
tags: [container, kubernetes, devcontainer]
---

# Kubernetes Dev Containers

A workspace is a privileged pod running a Docker daemon. Each repository in the
`repo` parameter is cloned into `/workspaces` and its `devcontainer.json`
environment is built and run as its own sub-agent, with VS Code and Claude Code
inside.

## Parameters

- **Repositories** (mutable, defaults to empty — no dev containers): repository
  URLs, one per project. Each becomes a dev container named after the repo
  basename (basenames must be unique). Add or remove projects by editing this
  parameter; newly added repos are cloned at the next start. Private repos
  authenticate with the workspace owner's Coder SSH key (`coder gitssh`).
- **CPU / Memory**: pod resource limits.
- **Workspaces volume size**: size of the persistent `/workspaces` volume —
  checkouts and Docker images live here and survive restarts.
- **Workspace Image**: empty follows the latest base image built in-cluster
  ([`images/coder-devcontainer-base/`](../../../../../../../images/coder-devcontainer-base/));
  set a tag to pin.

## Dev containers

Each repo's `devcontainer.json` (strict JSON, no comments) is merged with a
shared base that adds the common-utils feature, host networking (the container
shares the pod network and cluster DNS), and forwards `ANTHROPIC_*`,
`CLAUDE_CODE_*`, and git identity from the workspace environment — secrets
never land on disk. A repo's own `features`, `runArgs`, and `remoteEnv` extend
the base, with the repo winning per key.

The dashboard manages each container's lifecycle: status and rebuild on
`devcontainer.json` changes, no workspace recreate needed. Ad-hoc dev
containers can be started from the dashboard as well.

VS Code (extensions come from the template — `customizations.vscode` in
`devcontainer.json` is not applied over the coder-remote connection) and Claude
Code run inside each dev container. The parent agent keeps a web terminal on
the base environment as the fallback when a container build fails.

## Notes

- Repo devcontainer images must create and switch to a uid-1000 `coder` user
  (`useradd --uid 1000 …` then `USER coder`), or git inside the dev container
  rejects the checkout with "dubious ownership".
- On start, `docker system prune --filter until=168h` bounds the image store;
  tagged images survive, so unchanged repos start without a rebuild.
- Workspace pods run with read-only, cluster-wide Kubernetes access (the
  built-in `view` role via the `coder-workspace` service account).
