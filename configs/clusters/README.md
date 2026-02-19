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

### Rook Ceph
Cleanup previous installation
```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: disk-clean
  namespace: rook-ceph
spec:
  restartPolicy: Never
  nodeName: talos-lje-xo8
  volumes:
  - name: rook-data-dir
    hostPath:
      path: /var/lib/rook
  containers:
  - name: disk-clean
    image: busybox
    securityContext:
      privileged: true
    volumeMounts:
    - name: rook-data-dir
      mountPath: /node/rook-data
    command: ["/bin/sh", "-c", "rm -rf /node/rook-data/*"]
EOF
kubectl --namespace=rook-ceph delete pod disk-clean
```

Prepare disks
```bash
talosctl -n talos-lje-xo8 wipe disk $(talosctl -n 192.168.1.57 get disks | grep -v '256 GB' | awk '{print $4}' | grep nvme)
```

Toolbox
```
kubectl --namespace=rook-ceph exec -it deploy/rook-ceph-tools -- bash
```

Replace disk
```bash
# remove the disk and wait until cluster return healthy
ceph osd rm {osd-num}
ceph osd crush remove osd.{osd-num}
ceph auth del osd.{osd-num}
# ...then install the new disk
ceph device rm {device} # optional
# if moving disk between nodes only need this step
kubectl --namespace=rook-ceph delete deployments rook-ceph-osd-{osd-num}
```

Find osd
```bash
ceph osd tree
ceph device ls
kubectl --namespace=rook-ceph logs deployment/rook-ceph-osd-{osd-num} --container activate
```

