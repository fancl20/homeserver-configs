terraform {
  required_providers {
    coderd = {
      source = "coder/coderd"
    }
  }
}

provider "coderd" {}

resource "coderd_template" "templates" {
  name = each.key
  icon = "/icon/k8s.png"
  versions = [{
    directory = each.key
    active    = true
    tf_vars = toset([
      for v in local.template_variables[each.key] : {
        name  = v.name
        value = v.value
      }
    ])
  }]
  for_each = toset([for k, _ in fileset(path.module, "*/README.md") : dirname(k)])
}

locals {
  template_variables = {
    kubernetes-devcontainer = [
      { name = "cache_repo", value = "registry.default.svc/coder/cache" },
      { name = "insecure_cache_repo", value = "true" },
    ]
  }
}
