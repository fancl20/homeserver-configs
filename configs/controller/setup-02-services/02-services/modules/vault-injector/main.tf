variable "role" {
  type = string
}
variable "secrets" {
  type = map(object({ path = string, template = string }))
}

output "annotations" {
  value = merge(
    length(var.secrets) == 0 ? {} : {
      "vault.hashicorp.com/agent-inject" = "true"
      "vault.hashicorp.com/agent-pre-populate-only": "true"
      "vault.hashicorp.com/role" = var.role
    },
    {
      for k, v in var.secrets :
      "vault.hashicorp.com/agent-inject-secret-${k}" => v.path
    },
    {
      for k, v in var.secrets :
      "vault.hashicorp.com/agent-inject-template-${k}" => v.template if v.template != ""
    },
  )
}