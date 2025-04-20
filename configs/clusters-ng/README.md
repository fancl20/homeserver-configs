# Kubernetes Cluster

Bootstrap a kubernetes cluster from scratch.

## Authentication
### Goolge Cloud
```bash
gcloud --project=home-servers-275405 auth application-default login
```

### 1Password
```bash
mkdir -p ~/.config/1password && cd ~/.config/1password
eval $(op account add --address my1.1password.com --email fancl20@gmail.com --signin)
```

## Bootstrapping
### Flux
```bash
cd production && ./bootstrap.sh
```

### Vault
Initialize vault and store vault root token
```bash
kubectl --namespace=vault exec -it vault-0 -- /bin/sh -e -c '/bin/vault operator init'
bash -c '(read -p "Vault token:" -s VAULT_TOKEN && echo "${VAULT_TOKEN}" | sudo tee ~/.vault-token > /dev/null)'
```

### 1Password
```bash
# op connect server create homeserver --vaults Cluster
# eval $(op signin)
kubectl -n onepassword create secret generic op-credentials --from-literal=1password-credentials.json="$(base64 ./1password-credentials.json)"
kubectl -n onepassword create secret generic onepassword-token --from-literal=token=$(op connect token create --server homeserver --vault Cluster onepassword-operator)
```

### Terraform
```bash
kubectl --namespace=vault port-forward services/vault 8200:8200 & # From stage-02
VAULT_ADDR="http://127.0.0.1:8200" terraform apply
```
