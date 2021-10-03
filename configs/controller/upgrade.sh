#!/bin/bash -e

[ $(id -u) == 0 ] ||  exec sudo "$0" "$@"

# Upgrade k0s
sudo k0s stop
curl -sSLf https://get.k0s.sh | sudo sh
sudo k0s start

# Upgrade helm
curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash

# Upgrade terraform
sudo ./setup-01-k0s/install_terraform.py

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

terraform_apply setup-02-services/00-system
terraform_apply setup-02-services/01-services
