#!/usr/bin/env bash
cd "$(git rev-parse --show-toplevel)" && source scripts/common.sh

POSITIONAL_ARGS=()

while [[ $# -gt 0 ]]; do
  case $1 in
    --node)
      export NODE_ADDRESS="$2"
      shift # past argument
      shift # past value
      ;;
    --type)
      export NODE_TYPE="$2"
      shift # past argument
      shift # past value
      ;;
    -*|--*)
      echo "Unknown option $1"
      exit 1
      ;;
    *)
      MAINTENANCE_ADDRESS="$1"
      shift # past argument
      ;;
  esac
done

talosctl apply-config --nodes "${MAINTENANCE_ADDRESS}" --insecure --file <(cat \
  <(talosctl gen config --with-secrets "${SECRETS}" \
                        --config-patch "@configs/worker-${NODE_TYPE}.yaml" \
                        --output-types worker \
                        --output - \
                        homecluster "https://192.168.1.3:6443") \
  "configs/worker-${NODE_TYPE}-network.yaml" | envsubst)

until talosctl health --nodes "${NODE_ADDRESS}" --server=false; do
  sleep 10
done
