#!/bin/bash -e

[ $(id -u) == 0 ] ||  exec sudo "$0" "$@"

export VAULT_ADDR="http://vault.local.d20.fan"
export KUBE_CONFIG_PATH="/var/lib/k0s/pki/admin.conf"

# The domain used for vault require bind9 and external-dns running, which
# depends on vault-injector. To break the loop, we can manually forward
# the vault service during the initial setup:
# kubectl --namespace=vault port-forward vault-0 8200:8200
# export VAULT_ADDR="http://127.0.0.1:8200"

curl -s --fail https://raw.githubusercontent.com/k8snetworkplumbingwg/multus-cni/master/deployments/multus-daemonset.yml | k0s kubectl apply -f -

terraform_apply() {
  terraform -chdir=$1 init --upgrade
  terraform -chdir=$1 apply
}

terraform_apply 00-system
terraform_apply 01-services
