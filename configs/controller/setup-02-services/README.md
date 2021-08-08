## 00-system

### Before applying the config:

- Initialized k0s
- Generated gcloud credential

### After applying the config:

- Installed Metallb as Load Balancer
- Installed ingress-nginx as Ingress Controller
- Installed vault and configured auto unseal by Google Cloud KMS

### Appendix:

```shell
# Generate gcloud credential:
podman run --rm -it --security-opt label=disable \
           -v /root/.config/gcloud/:/root/.config/gcloud/ \
           gcr.io/google.com/cloudsdktool/cloud-sdk \
           gcloud --project=home-servers-275405 auth application-default login
```

## 02-services

### Before applying the config:

- All the requirements and the results of previous step(s)
- Initialized vault and generate root token
- Added vault secrets used by services

### After applying the config:

- Deployed all services

### Appendix:

```shell
# Initialize vault and store vault root token
kubectl --namespace=vault exec -it vault-0 -- /bin/sh -e -c '/bin/vault operator init'
(read -p "Vault token:" -s VAULT_TOKEN && echo "${VAULT_TOKEN}" | sudo tee /root/.vault-token > /dev/null)
```
