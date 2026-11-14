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

locals {
  use_kubeconfig = false
  namespace      = "coder"
}

data "coder_provisioner" "me" {}
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

locals {
  deployment_name  = "coder-${lower(data.coder_workspace.me.id)}"
  workspace_image  = "docker.io/library/buildpack-deps:testing-scm"
  git_author_name  = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
  git_author_email = data.coder_workspace_owner.me.email
}

resource "kubernetes_deployment_v1" "main" {
  count            = data.coder_workspace.me.start_count
  wait_for_rollout = false
  metadata {
    name      = local.deployment_name
    namespace = local.namespace
    labels = {
      "app.kubernetes.io/name"     = "coder-fixer-workspace"
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
        "app.kubernetes.io/name" = "coder-fixer-workspace"
      }
    }
    strategy {
      type = "Recreate"
    }

    template {
      metadata {
        labels = {
          "app.kubernetes.io/name" = "coder-fixer-workspace"
        }
      }
      spec {
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

          resources {
            requests = {
              "cpu"    = "250m"
              "memory" = "512Mi"
            }
            limits = {
              "cpu"    = "2"
              "memory" = "4Gi"
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

  startup_script          = <<-EOT
    #!/bin/sh
    set -eu

    # kubectl for read-only cluster inspection. Deliberately best-effort: the
    # fixer must still start when dl.k8s.io is unreachable.
    if [ "$(uname -m)" = x86_64 ]; then arch=amd64; else arch="$(uname -m)"; fi
    ver="$(curl -fsSL https://dl.k8s.io/release/stable.txt || true)"
    if [ -n "$ver" ] && curl -fsSL "https://dl.k8s.io/release/$ver/bin/linux/$arch/kubectl" -o /usr/local/bin/kubectl; then
      chmod +x /usr/local/bin/kubectl
    else
      rm -f /usr/local/bin/kubectl
      echo "kubectl download failed; continuing without it" >&2
    fi

    # Authenticate git as the workspace owner so agent chats can clone and push
    # private repos without extra credentials.
    git config --global core.sshCommand "coder gitssh"
  EOT
  startup_script_behavior = "blocking"

  env = {
    GIT_AUTHOR_NAME     = local.git_author_name
    GIT_AUTHOR_EMAIL    = local.git_author_email
    GIT_COMMITTER_NAME  = local.git_author_name
    GIT_COMMITTER_EMAIL = local.git_author_email
  }
}
