terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = "~> 2.0"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
  }
}

provider "coder" {
  url = "https://coder.local.d20.fan"
}
provider "kubernetes" {
  config_path = local.use_kubeconfig == true ? "~/.kube/config" : null
}

# Variables
locals {
  use_kubeconfig = false
  namespace      = "coder"
}

data "coder_provisioner" "me" {}
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

data "coder_parameter" "cpu" {
  type         = "number"
  name         = "cpu"
  display_name = "CPU"
  description  = "CPU limit (cores)."
  default      = "2"
  icon         = "/icon/memory.svg"
  mutable      = true
  validation {
    min = 1
    max = 99999
  }
  order = 1
}

data "coder_parameter" "memory" {
  type         = "number"
  name         = "memory"
  display_name = "Memory"
  description  = "Memory limit (GiB)."
  default      = "8"
  icon         = "/icon/memory.svg"
  mutable      = true
  validation {
    min = 1
    max = 99999
  }
  order = 2
}

data "coder_parameter" "workspaces_volume_size" {
  name         = "workspaces_volume_size"
  display_name = "Workspaces volume size"
  description  = "Size of the `/workspaces` volume (GiB)."
  default      = "32"
  type         = "number"
  icon         = "/emojis/1f4be.png"
  mutable      = false
  validation {
    min = 1
    max = 99999
  }
  order = 3
}

data "coder_parameter" "repo" {
  description  = "Select a repository to clone and run as a dev container."
  display_name = "Repository (auto)"
  mutable      = true
  name         = "repo"
  order        = 4
  type         = "string"
}

data "coder_parameter" "workspace_image" {
  default      = ""
  description  = "Base image that runs the workspace (Docker daemon + devcontainer CLI). Dev containers are built and run on top of it. Empty follows the latest built image."
  display_name = "Workspace Image"
  mutable      = true
  name         = "workspace_image"
  order        = 5
}

# Latest built tag of the base image, resolved from the Flux ImagePolicy so
# workspaces track the current Debian base snapshot without template edits.
data "kubernetes_resource" "workspace_image" {
  api_version = "image.toolkit.fluxcd.io/v1"
  kind        = "ImagePolicy"

  metadata {
    name      = "coder-devcontainer-base"
    namespace = "flux-system"
  }
}

locals {
  # Computed locals
  deployment_name  = "coder-${lower(data.coder_workspace.me.id)}"
  workspace_image  = data.coder_parameter.workspace_image.value != "" ? data.coder_parameter.workspace_image.value : "registry.local.d20.fan/fancl20/coder-devcontainer-base:${data.kubernetes_resource.workspace_image.object.status.latestRef.tag}"
  git_author_name  = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
  git_author_email = data.coder_workspace_owner.me.email
  repo_url         = data.coder_parameter.repo.value
}

resource "kubernetes_persistent_volume_claim_v1" "workspaces" {
  metadata {
    name      = "coder-${lower(data.coder_workspace.me.id)}-workspaces"
    namespace = local.namespace
    labels = {
      "app.kubernetes.io/name"     = "coder-${lower(data.coder_workspace.me.id)}-workspaces"
      "app.kubernetes.io/instance" = "coder-${lower(data.coder_workspace.me.id)}-workspaces"
      "app.kubernetes.io/part-of"  = "coder"
      "com.coder.resource"         = "true"
      "com.coder.workspace.id"     = data.coder_workspace.me.id
      "com.coder.workspace.name"   = data.coder_workspace.me.name
      "com.coder.user.id"          = data.coder_workspace_owner.me.id
      "com.coder.user.username"    = data.coder_workspace_owner.me.name
    }
    annotations = {
      "com.coder.user.email" = data.coder_workspace_owner.me.email
    }
  }
  wait_until_bound = false
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "${data.coder_parameter.workspaces_volume_size.value}Gi"
      }
    }
  }
}

resource "kubernetes_deployment_v1" "main" {
  count = data.coder_workspace.me.start_count
  depends_on = [
    kubernetes_persistent_volume_claim_v1.workspaces
  ]
  wait_for_rollout = false
  metadata {
    name      = local.deployment_name
    namespace = local.namespace
    labels = {
      "app.kubernetes.io/name"     = "coder-workspace"
      "app.kubernetes.io/instance" = local.deployment_name
      "app.kubernetes.io/part-of"  = "coder"
      "com.coder.resource"         = "true"
      "com.coder.workspace.id"     = data.coder_workspace.me.id
      "com.coder.workspace.name"   = data.coder_workspace.me.name
      "com.coder.user.id"          = data.coder_workspace_owner.me.id
      "com.coder.user.username"    = data.coder_workspace_owner.me.name
    }
    annotations = {
      "com.coder.user.email" = data.coder_workspace_owner.me.email
    }
  }

  spec {
    replicas = 1
    selector {
      match_labels = {
        "app.kubernetes.io/name" = "coder-workspace"
      }
    }
    strategy {
      type = "Recreate"
    }

    template {
      metadata {
        labels = {
          "app.kubernetes.io/name" = "coder-workspace"
        }
      }
      spec {
        security_context {}

        service_account_name = "coder-workspace"

        container {
          name              = "dev"
          image             = local.workspace_image
          image_pull_policy = "Always"
          command           = ["/bin/sh", "-c", coder_agent.main.init_script]

          env {
            name  = "CODER_AGENT_TOKEN"
            value = coder_agent.main.token
          }
          env {
            name  = "CODER_AGENT_URL"
            value = "http://coder.coder.svc"
          }
          env {
            name  = "CODER_AGENT_DEVCONTAINERS_PROJECT_DISCOVERY_ENABLE"
            value = "false"
          }

          env_from {
            secret_ref {
              name = data.coder_workspace_owner.me.name
            }
          }
          env {
            name  = "ANTHROPIC_BASE_URL"
            value = "https://api.z.ai/api/anthropic"
          }
          env {
            name  = "API_TIMEOUT_MS"
            value = "3000000"
          }
          env {
            name  = "ANTHROPIC_DEFAULT_OPUS_MODEL"
            value = "glm-5.3[1m]"
          }
          env {
            name  = "ANTHROPIC_DEFAULT_SONNET_MODEL"
            value = "glm-5.3[1m]"
          }
          env {
            name  = "ANTHROPIC_DEFAULT_HAIKU_MODEL"
            value = "glm-5.3-flash[1m]"
          }
          env {
            name  = "ANTHROPIC_ENABLE_TOOL_SEARCH"
            value = "0"
          }
          env {
            name  = "CLAUDE_CODE_EFFORT_LEVEL"
            value = "max"
          }
          env {
            name  = "CLAUDE_CODE_MAX_OUTPUT_TOKENS"
            value = "131072"
          }
          env {
            name  = "CLAUDE_CODE_AUTO_MODE_SERVER"
            value = "0"
          }

          resources {
            requests = {
              "cpu"    = "250m"
              "memory" = "512Mi"
            }
            limits = {
              "cpu"    = "${data.coder_parameter.cpu.value}"
              "memory" = "${data.coder_parameter.memory.value}Gi"
            }
          }
          volume_mount {
            mount_path = "/workspaces"
            name       = "workspaces"
            read_only  = false
          }
          volume_mount {
            mount_path = "/etc/secrets"
            name       = "secrets"
          }
          volume_mount {
            mount_path = "/dev/net/tun"
            name       = "dev-net-tun"
          }

          # privileged for DinD
          security_context {
            privileged = true
          }
        }

        volume {
          name = "workspaces"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.workspaces.metadata.0.name
            read_only  = false
          }
        }

        volume {
          name = "secrets"
          secret {
            secret_name = data.coder_workspace_owner.me.name
            optional    = true
          }
        }

        volume {
          name = "dev-net-tun"
          host_path {
            path = "/dev/net/tun"
            type = "CharDevice"
          }
        }

        affinity {
          // Schedule only on nodes with the specific instance type
          node_affinity {
            required_during_scheduling_ignored_during_execution {
              node_selector_term {
                match_expressions {
                  key      = "node.kubernetes.io/instance-type"
                  operator = "In"
                  values   = ["erying-14450hx"]
                }
              }
            }
          }

          // This affinity attempts to spread out all workspace pods evenly across
          // nodes.
          pod_anti_affinity {
            preferred_during_scheduling_ignored_during_execution {
              weight = 1
              pod_affinity_term {
                topology_key = "kubernetes.io/hostname"
                label_selector {
                  match_expressions {
                    key      = "app.kubernetes.io/name"
                    operator = "In"
                    values   = ["coder-workspace"]
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}

resource "coder_agent" "main" {
  arch = data.coder_provisioner.me.arch
  os   = "linux"
  display_apps {
    vscode          = false
    vscode_insiders = false
    web_terminal    = true
    ssh_helper      = false
  }

  startup_script          = "service docker start"
  startup_script_behavior = "blocking"
  shutdown_script         = "service docker stop"

  env = {
    GIT_AUTHOR_NAME     = local.git_author_name
    GIT_AUTHOR_EMAIL    = local.git_author_email
    GIT_COMMITTER_NAME  = local.git_author_name
    GIT_COMMITTER_EMAIL = local.git_author_email
  }

  metadata {
    display_name = "Workspaces Disk"
    key          = "3_workspaces_disk"
    script       = "coder stat disk --path /workspaces"
    interval     = 60
    timeout      = 1
  }

  metadata {
    display_name = "CPU Usage (Host)"
    key          = "4_cpu_usage_host"
    script       = "coder stat cpu --host"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Memory Usage (Host)"
    key          = "5_mem_usage_host"
    script       = "coder stat mem --host"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Load Average (Host)"
    key          = "6_load_host"
    # get load avg scaled by number of cores
    script   = <<EOT
      echo "`cat /proc/loadavg | awk '{ print $1 }'` `nproc`" | awk '{ printf "%0.2f", $1/$2 }'
    EOT
    interval = 60
    timeout  = 1
  }

  metadata {
    display_name = "Swap Usage (Host)"
    key          = "7_swap_host"
    script       = <<EOT
      free -b | awk '/^Swap/ { printf("%.1f/%.1f", $3/1024.0/1024.0/1024.0, $2/1024.0/1024.0/1024.0) }'
    EOT
    interval     = 10
    timeout      = 1
  }
}

module "git-clone" {
  count      = data.coder_workspace.me.start_count
  source     = "registry.coder.com/modules/git-clone/coder"
  agent_id   = coder_agent.main.id
  url        = local.repo_url
  base_dir   = "/workspaces"
  extra_args = ["--recurse-submodules"]
  post_clone_script = <<-EOT
    #!/usr/bin/env bash
    set -euo pipefail
    repo="$PWD"
    out="/tmp/devcontainer.json"

    src=""
    for c in "$repo/.devcontainer/devcontainer.json" "$repo/.devcontainer.json" "$repo"/.devcontainer/*/devcontainer.json; do
      if [ -f "$c" ]; then
        src="$c"
        break
      fi
    done
    if [ -z "$src" ]; then
      echo "no devcontainer.json under $repo; skipping merge"
      exit 0
    fi
    srcdir="$(dirname "$src")"

    jq --arg srcdir "$srcdir" --argjson base '${jsonencode({
  features = {
    "ghcr.io/devcontainers/features/common-utils:2" = {
      installZsh      = false
      installOhMyZsh  = false
      upgradePackages = false
    }
  }
  runArgs = ["--network=host"]
  # the vscode-desktop module registers its own app on the sub-agent; hide the
  # integration's built-in one so the dashboard shows a single VS Code button
  customizations = {
    coder = {
      displayApps = {
        vscode = false
      }
    }
  }
})}' -s '
      def toAbs($d): if (type == "string") and (startswith("/") | not) then "\($d)/\(.)" else . end;
      .[0] as $repo |
      ($base + {remoteEnv: (env | with_entries(select(.key | test("^ANTHROPIC_|^CLAUDE_CODE_|^API_TIMEOUT_MS|^GIT_(AUTHOR|COMMITTER)_")) | .value = "$${localEnv:\(.key)}"))}) as $base |
      ($base * $repo)
      | .runArgs = ($base.runArgs + ($repo.runArgs // []))
      | if .build then
          .build |= ((if .dockerfile then .dockerfile |= toAbs($srcdir) else . end)
                   | (if .context then .context |= toAbs($srcdir) else . end))
        else . end
      | if .dockerFile then .dockerFile |= toAbs($srcdir) else . end
      | if .dockerComposeFile then .dockerComposeFile |= (if type == "string" then [.] else . end | map(toAbs($srcdir))) else . end
    ' "$src" > "$out"

    echo "merged $src into $out"
  EOT
}

# Installs @devcontainers/cli into the workspace at start; the Dev Containers
# integration invokes `devcontainer` from PATH.
module "devcontainers-cli" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/modules/devcontainers-cli/coder"
  agent_id = coder_agent.main.id
}

resource "coder_devcontainer" "repo" {
  count            = data.coder_workspace.me.start_count
  agent_id         = coder_agent.main.id
  workspace_folder = coalesce(module.git-clone[0].repo_dir, "/")
  config_path      = "/tmp/devcontainer.json"
}

locals {
  vscode_agent_ids = data.coder_workspace.me.start_count > 0 ? {
    main         = coder_agent.main.id
    devcontainer = coder_devcontainer.repo[0].subagent_id
  } : {}
}

module "vscode-desktop" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/vscode-desktop/coder"
  agent_id = coder_devcontainer.repo[0].subagent_id
  folder   = module.git-clone[0].repo_dir
  extensions = [
    "ms-python.python",
    "ms-python.autopep8",
    "ms-toolsai.jupyter",
    "hashicorp.terraform",
    "Grafana.vscode-jsonnet",
    "golang.go",
    "rust-lang.rust-analyzer",
    "anthropic.claude-code",
    "bufbuild.vscode-buf",
    "Lencerf.beancount",
    "dongfg.vscode-beancount-formatter",
  ]
}

resource "coder_app" "vscode_base" {
  count        = data.coder_workspace.me.start_count
  agent_id     = coder_agent.main.id
  display_name = "VS Code Desktop (Base)"
  slug         = "vscode-base"
  icon         = "/icon/code.svg"
  external     = true
  url = join("", [
    "vscode://coder.coder-remote/open",
    "?owner=", data.coder_workspace_owner.me.name,
    "&workspace=", data.coder_workspace.me.name,
    "&folder=", module.git-clone[0].repo_dir,
    "&url=", data.coder_workspace.me.access_url,
    "&token=$SESSION_TOKEN",
  ])
}

# The vscode-desktop module takes no settings; remote (Machine) settings are
# written to the vscode-server directory instead. UI-scoped settings (theme,
# workbench, keybindings) come from the local VS Code.
resource "coder_script" "vscode_desktop_settings" {
  for_each     = local.vscode_agent_ids
  agent_id     = each.value
  display_name = "VS Code Desktop Settings${each.key == "devcontainer" ? " (Dev Container)" : ""}"
  icon         = "/icon/code.svg"
  run_on_start = true
  script = <<-EOT
    #!/usr/bin/env bash
    set -euo pipefail
    dir="$HOME/.vscode-server/data/Machine"
    mkdir -p "$dir"
    printf '%s' '${jsonencode({
  "editor.formatOnSave" : true,
  "editor.tabSize" : 2,
  "editor.guides.bracketPairs" : true,
  "files.trimTrailingWhitespace" : true,
  "terminal.integrated.defaultProfile.linux" : "fish",
  "remote.autoForwardPortsSource" : "hybrid",
  "[python]" : {
    "editor.formatOnType" : true,
    "editor.defaultFormatter" : "ms-python.autopep8"
  },
  "autopep8.args" : ["--indent-size=2"],
  "rust-analyzer.inlayHints.typeHints.enable" : false,
})}' > "$dir/settings.json"
  EOT
}

module "claude-code" {
  count               = data.coder_workspace.me.start_count
  source              = "registry.coder.com/coder/claude-code/coder"
  agent_id            = coder_devcontainer.repo[0].subagent_id
  workdir             = module.git-clone[0].repo_dir
  install_claude_code = true
  managed_settings = {
    attribution = {
      commit = ""
      pr     = ""
    }
  }
}

resource "coder_metadata" "container_info" {
  count       = data.coder_workspace.me.start_count
  resource_id = coder_agent.main.id
  item {
    key   = "workspace image"
    value = local.workspace_image
  }
  item {
    key   = "git url"
    value = local.repo_url
  }
}
