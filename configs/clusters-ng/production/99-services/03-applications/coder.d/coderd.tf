provider "coderd" {}

resource "coderd_template" "templates" {
  name = each.key
  versions = [{
    directory = each.key
    active    = true
  }]
  for_each = toset([for k, _ in fileset(path.module, "*/README.md") : dirname(k)])
}
