#!/bin/bash -e

kubectl apply -k '00-stage/flux'

# configs will be managed by vault-secrets-operator after the bootstrap.
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: configs
  namespace: flux-system
type: Opaque
EOF