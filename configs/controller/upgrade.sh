#!/bin/bash -e

[ $(id -u) == 0 ] ||  exec sudo "$0" "$@"

# Upgrade k0s
# Upgrade helm
# Upgrade terraform

# Upgrade version env

# TODO: We should deploy a job instead for applying change
# TODO: init --upgrade will generate a new lock file which should be committed
# with services' versions
export VAULT_ADDR="http://vault.local.d20.fan"
export KUBE_CONFIG_PATH="/var/lib/k0s/pki/admin.conf"

terraform_apply() {
  terraform -chdir=$1 init --upgrade
  terraform -chdir=$1 apply
}

terraform_apply 00-system
terraform_apply 01-services
