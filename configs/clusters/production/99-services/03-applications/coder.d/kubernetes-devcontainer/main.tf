terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = "~> 2.0"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
    envbuilder = {
      source = "coder/envbuilder"
    }
  }
}

provider "coder" {
  url = "http://coder.coder.svc"
}
provider "kubernetes" {
  config_path = local.use_kubeconfig == true ? "~/.kube/config" : null
}
provider "envbuilder" {}

# Variables
locals {
  use_kubeconfig         = false
  namespace              = "coder"
  cache_repo             = "registry.default.svc/coder/cache"
  insecure_cache_repo    = true
  cache_repo_secret_name = "disabled"
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
  default      = "10"
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
  description  = "Select a repository to automatically clone and start working with a devcontainer."
  display_name = "Repository (auto)"
  mutable      = true
  name         = "repo"
  order        = 4
  type         = "string"
}

data "coder_parameter" "fallback_image" {
  default      = "codercom/enterprise-base:ubuntu"
  description  = "This image runs if the devcontainer fails to build."
  display_name = "Fallback Image"
  mutable      = true
  name         = "fallback_image"
  order        = 6
}

data "coder_parameter" "devcontainer_builder" {
  description  = <<-EOT
    Image that will build the devcontainer.
    We highly recommend using a specific release as the `:latest` tag will change.
    Find the latest version of Envbuilder here: https://github.com/coder/envbuilder/pkgs/container/envbuilder
  EOT
  display_name = "Devcontainer Builder"
  mutable      = true
  name         = "devcontainer_builder"
  default      = "ghcr.io/coder/envbuilder:latest"
  order        = 7
}


data "kubernetes_secret" "cache_repo_dockerconfig_secret" {
  count = local.cache_repo_secret_name == "disabled" ? 0 : 1
  metadata {
    name      = local.cache_repo_secret_name
    namespace = local.namespace
  }
}

locals {
  # Computed locals
  deployment_name            = "coder-${lower(data.coder_workspace.me.id)}"
  devcontainer_builder_image = data.coder_parameter.devcontainer_builder.value
  git_author_name            = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
  git_author_email           = data.coder_workspace_owner.me.email
  repo_url                   = data.coder_parameter.repo.value
  # The envbuilder provider requires a key-value map of environment variables.
  envbuilder_env = {
    "CODER_AGENT_TOKEN" : coder_agent.main.token,
    "CODER_AGENT_URL" : data.coder_workspace.me.access_url,
    # ENVBUILDER_GIT_URL and ENVBUILDER_CACHE_REPO will be overridden by the provider
    # if the cache repo is enabled.
    "ENVBUILDER_GIT_URL" : local.cache_repo == "" ? local.repo_url : "",
    # Used for when SSH is an available authentication mechanism for git providers
    "ENVBUILDER_GIT_SSH_PRIVATE_KEY_BASE64" : base64encode(try(data.coder_workspace_owner.me.ssh_private_key, "")),
    "ENVBUILDER_INIT_SCRIPT" : coder_agent.main.init_script,
    "ENVBUILDER_FALLBACK_IMAGE" : data.coder_parameter.fallback_image.value,
    "ENVBUILDER_DOCKER_CONFIG_BASE64" : base64encode(try(data.kubernetes_secret.cache_repo_dockerconfig_secret[0].data[".dockerconfigjson"], "")),
    "ENVBUILDER_PUSH_IMAGE" : local.cache_repo == "" ? "" : "true"
    "ENVBUILDER_IGNORE_PATHS" : "/etc/secrets,/var/run"
  }
}

# Check for the presence of a prebuilt image in the cache repo
# that we can use instead.
resource "envbuilder_cached_image" "cached" {
  count         = local.cache_repo == "" ? 0 : data.coder_workspace.me.start_count
  builder_image = local.devcontainer_builder_image
  git_url       = local.repo_url
  cache_repo    = local.cache_repo
  extra_env     = local.envbuilder_env
  insecure      = local.insecure_cache_repo
}

resource "kubernetes_persistent_volume_claim" "workspaces" {
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

resource "kubernetes_deployment" "main" {
  count = data.coder_workspace.me.start_count
  depends_on = [
    kubernetes_persistent_volume_claim.workspaces
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

        container {
          name              = "dev"
          image             = local.cache_repo == "" ? local.devcontainer_builder_image : envbuilder_cached_image.cached.0.image
          image_pull_policy = "Always"
          # Set the environment using cached_image.cached.0.env if the cache repo is enabled.
          # Otherwise, use the local.envbuilder_env.
          # You could alternatively write the environment variables to a ConfigMap or Secret
          # and use that as `env_from`.
          dynamic "env" {
            for_each = nonsensitive(
              local.cache_repo == "" ?
              local.envbuilder_env :
              merge(envbuilder_cached_image.cached.0.env_map, {
                # Workaround for https://github.com/coder/terraform-provider-envbuilder/issues/83
                "ENVBUILDER_GIT_SSH_PRIVATE_KEY_BASE64" : local.envbuilder_env["ENVBUILDER_GIT_SSH_PRIVATE_KEY_BASE64"],
              })
            )
            content {
              name  = env.key
              value = env.value
            }
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
        }

        volume {
          name = "workspaces"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.workspaces.metadata.0.name
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

        affinity {
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
  dir  = "/workspaces"
  display_apps {
    vscode          = false
    vscode_insiders = false
    web_terminal    = true
    ssh_helper      = false
  }

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

module "vscode-web" {
  count           = data.coder_workspace.me.start_count
  source          = "registry.coder.com/coder/code-server/coder"
  agent_id        = coder_agent.main.id
  additional_args = "--disable-workspace-trust"
  extensions = [
    "vscodevim.vim",
    "ms-python.python",
    "ms-python.autopep8",
    "ms-toolsai.jupyter",
    "hashicorp.terraform",
    "Grafana.vscode-jsonnet",
    "golang.go",
    "RooVeterinaryInc.roo-cline",
    "Lencerf.beancount",
  ]
  settings = {
    "workbench.colorTheme" : "Solarized Light"
    "explorer.autoReveal" : false
    "editor.minimap.enabled" : false
    "editor.formatOnSave" : true
    "editor.tabSize" : 2
    "editor.guides.bracketPairs" : true
    "files.trimTrailingWhitespace" : true
    "terminal.integrated.defaultProfile.linux" : "fish"
    "terminal.integrated.stickyScroll.enabled" : false
    "extensions.ignoreRecommendations" : true
    "vim.handleKeys" : {
      "<D-c>" : false
    }
    "[python]" : {
      "editor.formatOnType" : true
      "editor.defaultFormatter" : "ms-python.autopep8"
    }
    "roo-cline" : {
      "autoImportSettingsPath" : "/etc/secrets/roo-code-settings.json"
    }
  }
}

resource "coder_metadata" "container_info" {
  count       = data.coder_workspace.me.start_count
  resource_id = coder_agent.main.id
  item {
    key   = "workspace image"
    value = local.cache_repo == "" ? local.devcontainer_builder_image : envbuilder_cached_image.cached.0.image
  }
  item {
    key   = "git url"
    value = local.repo_url
  }
  item {
    key   = "cache repo"
    value = local.cache_repo == "" ? "not enabled" : local.cache_repo
  }
}
