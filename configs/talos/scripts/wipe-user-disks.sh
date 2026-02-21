#!/usr/bin/env bash
cd "$(git rev-parse --show-toplevel)/configs/talos" && source scripts/common.sh

while [[ $# -gt 0 ]]; do
  case $1 in
    --node)
      export NODE_ADDRESS="$2"
      shift # past argument
      shift # past value
      ;;
    *)
      echo "Unknown option $1"
      exit 1
      ;;
  esac
done

SYSTEM_DISK=$(talosctl get --nodes "${NODE_ADDRESS}" systemdisk -o yaml | grep 'diskID:' | awk '{print $2}')
USER_DISKS=$(talosctl get --nodes "${NODE_ADDRESS}" disks | tail -n +2 | grep -v "${SYSTEM_DISK}"'\|loop0' | awk '{print $4}')

echo ${NODE_ADDRESS}: "${USER_DISKS//$'\n'/ }"
read -p "Press Enter to continue..."

echo "${USER_DISKS}" | xargs talosctl wipe --nodes "${NODE_ADDRESS}" disk
