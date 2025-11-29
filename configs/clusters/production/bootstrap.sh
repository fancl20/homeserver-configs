#!/bin/bash -e

# Install CRDs first, then reinstall with kustomize.
kubectl apply -f '00-stage/flux/gotk-components.yaml'
kubectl apply -k '00-stage/flux'

# configs will be managed by external-secrets after the bootstrap.
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: configs
  namespace: flux-system
type: Opaque
EOF
