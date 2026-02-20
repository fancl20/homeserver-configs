set -eo pipefail

SECRETS="${HOME}/.talos/secrets.yaml"
[ -e "${SECRETS}" ] || op document get Talos --vault Cluster --out-file "${SECRETS}"

if ! talosctl config info &> /dev/null; then
  talosctl gen config --with-secrets "${SECRETS}" \
                      --output-types talosconfig \
                      --output "${HOME}/.talos/config" \
                      --force \
                      homecluster "https://192.168.1.3:6443"
  talosctl config endpoint 192.168.1.3
  talosctl kubeconfig --nodes 192.168.1.3 --force
fi

export TALOS_VERSION="$(talosctl version --client --short | awk '{printf "%s", $2}')"

get_schematic_id() {
  curl -sS --fail -X POST --data-binary @<(cat "$@")  "https://factory.talos.dev/schematics" \
    | python3 -c 'import sys, json; print(json.load(sys.stdin)["id"])'
}

