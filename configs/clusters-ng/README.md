# Kubernetes Cluster

Bootstrap a kubernetes cluster from scratch.

## Authentication
```bash
# Goolge Cloud
gcloud --project=home-servers-275405 auth application-default login

# 1Password
mkdir -p ~/.config/1password && cd ~/.config/1password
eval $(op account add --address my1.1password.com --email fancl20@gmail.com --signin)
op connect server create homeserver --vaults Cluster
kubectl -n one-password create secret generic op-credentials --from-file=1password-credentials.json=./1password-credentials.json
kubectl -n one-password create secret generic onepassword-token --from-literal=token=$(op connect token create --server homeserver --vault Cluster onepassword-operator)
```

## Bootstrapping
### Flux
```bash
cd production && ./bootstrap.sh
```

## Vault
```bash
# Initialize vault and store vault root token
kubectl --namespace=vault exec -it vault-0 -- /bin/sh -e -c '/bin/vault operator init'
(read -p "Vault token:" -s VAULT_TOKEN && echo "${VAULT_TOKEN}" | sudo tee /root/.vault-token > /dev/null)
```
