#!/usr/bin/env bash
cd "$(git rev-parse --show-toplevel)/configs/talos" && source scripts/common.sh

upgrade() {
  local NODE_ADDRESS=$1
  local TALOS_IMAGE
  local SERVER_VERSION
  SERVER_VERSION=$(talosctl version -n "${NODE_ADDRESS}" | awk '/\tTag:/{v=$2} END{print v}')

  if [[ "${SERVER_VERSION}" == "${TALOS_VERSION}" ]]; then
    echo "========== ${NODE_ADDRESS}: already on ${TALOS_VERSION}, skipping =========="
    return
  fi

  # The install image is the only factory.talos.dev reference in the machine
  # config, so the image is grabbed by registry match.
  TALOS_IMAGE=$(talosctl --nodes "${NODE_ADDRESS}" get machineconfig v1alpha1 -o jsonpath='{.spec}' \
    | grep -m1 -o 'factory\.talos\.dev[^[:space:]]*')
  TALOS_IMAGE="${TALOS_IMAGE%:*}:${TALOS_VERSION}"

  echo "========== ${NODE_ADDRESS}: upgrading ${SERVER_VERSION} -> ${TALOS_VERSION} =========="
  talosctl upgrade --endpoints 192.168.1.3 --nodes "${NODE_ADDRESS}" --image "${TALOS_IMAGE}"
}

for NODE_ADDRESS in 192.168.1.{4..7} 192.168.1.15; do upgrade "${NODE_ADDRESS}"; done
