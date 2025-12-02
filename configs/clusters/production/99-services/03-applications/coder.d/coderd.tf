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
  }]
  for_each = toset([for k, _ in fileset(path.module, "*/README.md") : dirname(k)])
}
