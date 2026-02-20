#!/usr/bin/env bash
cd "$(git rev-parse --show-toplevel)" && source scripts/common.sh

export TALOS_SCHEMATIC="$(get_schematic_id configs/bootstrap/rpi_generic.yaml)"
export TALOS_SCHEMATIC_BOOTSTRAP="$(get_schematic_id configs/bootstrap/{bootstrap.yaml,rpi_generic.yaml})"

IMAGE_TEMP="$(mktemp --suffix '-talos-metal-arm64.raw.zst')"

for i in {1..3}; do
  curl -L "https://factory.talos.dev/image/${TALOS_SCHEMATIC_BOOTSTRAP}/${TALOS_VERSION}/metal-arm64.raw.zst" | unzstd --force -o "${IMAGE_TEMP}"

  tpi power off --node $i
  tpi flash --image-path "${IMAGE_TEMP}" --node $i
  tpi power on --node $i

  until talosctl get disks --nodes 192.168.1.254 --insecure &> /dev/null; do
    echo "Waiting node ready..."
    sleep 30
  done


  export NODE_ADDRESS="192.168.1.$((3 + $i))"
  talosctl apply-config --nodes 192.168.1.254 --insecure --mode=staged --file <(cat \
    <(talosctl gen config --with-secrets "${SECRETS}" \
                          --config-patch @configs/controlplane.yaml \
                          --output-types controlplane \
                          --output - \
                          homecluster "https://192.168.1.3:6443") \
    configs/controlplane-network.yaml | envsubst)

  # Workaround for https://github.com/siderolabs/talos/discussions/12799
  talosctl upgrade --nodes 192.168.1.254 --insecure --image="factory.talos.dev/installer/${TALOS_SCHEMATIC}:${TALOS_VERSION}"

  until talosctl health --endpoints 192.168.1.3 --nodes "${NODE_ADDRESS}"; do
    sleep 10
  done
done

rm "${IMAGE_TEMP}"
