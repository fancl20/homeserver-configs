#!/bin/bash -e

[ $(id -u) == 0 ] ||  exec sudo $0

export VAULT_ADDR="http://vault.local.d20.fan"
export KUBE_CONFIG_PATH="/var/lib/k0s/pki/admin.conf"

terraform_apply() {
  [ -d $1/.terraform/ ] || terraform -chdir=$1 init
  terraform -chdir=$1 apply
}

terraform_apply 00-system
terraform_apply 01-vault
terraform_apply 02-services