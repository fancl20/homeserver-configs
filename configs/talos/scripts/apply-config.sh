#!/usr/bin/env bash
cd "$(git rev-parse --show-toplevel)/configs/talos" && source scripts/common.sh

DRY_RUN="--dry-run"
while [[ $# -gt 0 ]]; do
  case $1 in
    --apply)
      DRY_RUN=""
      shift # past argument
      ;;
    *)
      echo "Unknown option $1"
      exit 1
      ;;
  esac
done

MEMBERS=$(talosctl get members --endpoints "192.168.1.3" --nodes 192.168.1.3 -o yaml)

apply_controlplane() {(
  export TALOS_SCHEMATIC="$(get_schematic_id configs/bootstrap/rpi_generic.yaml)"
  for i in {4..6}; do
    export NODE_ADDRESS="192.168.1.$i"
    grep -q "^[[:space:]]*- ${NODE_ADDRESS//./\\.}$" <<< "$MEMBERS" || continue
    echo "========== ${NODE_ADDRESS} =========="
    talosctl apply-config --endpoints "192.168.1.3" --nodes "${NODE_ADDRESS}" ${DRY_RUN} --file <(cat \
      <(talosctl gen config --with-secrets <(get_secrets)  \
                            --config-patch @configs/controlplane.yaml \
                            --output-types controlplane \
                            --output - \
                            homecluster "https://192.168.1.3:6443") \
      configs/controlplane-network.yaml | envsubst)
  done
)}

apply_worker() {(
  NODE_TYPE=$1
  export NODE_ADDRESS=$2
  echo "========== ${NODE_TYPE}: ${NODE_ADDRESS} =========="
  talosctl apply-config --endpoints "192.168.1.3" --nodes "${NODE_ADDRESS}" ${DRY_RUN} --file <(cat \
    <(talosctl gen config --with-secrets <(get_secrets) \
                          --config-patch "@configs/worker-${NODE_TYPE}".yaml \
                          --output-types worker \
                          --output - \
                          homecluster "https://192.168.1.3:6443") \
    configs/worker-${NODE_TYPE}-network.yaml | envsubst)
)}

apply_controlplane
for NODE_ADDRESS in 192.168.1.{7..7}; do apply_worker p5 ${NODE_ADDRESS}; done
for NODE_ADDRESS in 192.168.1.15; do apply_worker 14450hx ${NODE_ADDRESS}; done
