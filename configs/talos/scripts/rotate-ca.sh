#!/usr/bin/env bash
cd "$(git rev-parse --show-toplevel)/configs/talos" && source scripts/common.sh

talosctl gen secrets -o - | op document create - --vault Cluster --title Talos --file-name secrets.yaml
# https://github.com/siderolabs/talos/issues/12816
# talosctl --node 192.168.1.3 rotate-ca --with-secrets <(op document get Talos --vault Cluster)
