#!/usr/bin/env bash
cd "$(git rev-parse --show-toplevel)" && source scripts/common.sh

talosctl gen secrets -o - | op document create - --vault Cluster --title Talos --file-name secrets.yaml
op document get Talos --vault Cluster --out-file "${SECRETS}"
# https://github.com/siderolabs/talos/issues/12816
# talosctl --node 192.168.1.3 rotate-ca --with-secrets "${SECRETS}"
