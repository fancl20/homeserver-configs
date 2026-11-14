---
display_name: Fixer
description: Bare Linux workspace for Coder Agents chats — git, shell, and read-only kubectl for repo maintenance, debugging, and fixing homeserver-configs. Stop the workspace when the chat is done with it.
icon: /emojis/1f916.png
tags: [agent]
---

# Fixer

Workspace for [Coder Agents](https://coder.com/docs/ai-coder/agents/) chats
that fix this repo when the devcontainer workspaces are broken. The agent loop
(model calls, tool orchestration) runs in the Coder control plane; this
workspace only executes shell commands and file edits over the workspace
connection.

- Runs the public `buildpack-deps:bookworm-scm` image (git, curl, openssh) —
  no dependency on the local registry, the in-cluster image build, or any
  ImagePolicy. The coder CLI and kubectl are downloaded at start.
- Git authenticates as the workspace owner via `coder gitssh` (their Coder SSH
  key), so private repos clone and push with no extra credentials.
- `kubectl` (cluster-wide read-only via the `coder-workspace` service account)
  is downloaded at start for inspecting rollout state and pod logs; if the
  download fails the workspace still starts, without kubectl.
- No persistent volume: chats survive workspace stops in the Coder database,
  and a new workspace re-clones the repo it needs.

Stop the workspace when the chat no longer needs it — agent chats provision
workspaces on demand.
