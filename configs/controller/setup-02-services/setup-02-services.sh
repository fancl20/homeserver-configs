#!/bin/bash -e

[ $(id -u) == 0 ] ||  exec sudo "$0" "$@"

export VAULT_ADDR="http://vault.local.d20.fan"
export KUBE_CONFIG_PATH="/var/lib/k0s/pki/admin.conf"

curl -s --fail https://raw.githubusercontent.com/k8snetworkplumbingwg/multus-cni/master/deployments/multus-daemonset.yml | k0s kubectl apply -f -

terraform_apply() {
  terraform -chdir=$1 init
  terraform -chdir=$1 apply
}

terraform_apply 00-system
terraform_apply 01-services
