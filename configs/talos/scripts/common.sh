set -eo pipefail

if ! talosctl config info &> /dev/null; then
  talosctl gen config --with-secrets <(op document get Talos --vault Cluster) \
                      --output-types talosconfig \
                      --output "${HOME}/.talos/config" \
                      --force \
                      homecluster "https://192.168.1.3:6443"
  talosctl config endpoint 192.168.1.3
  talosctl kubeconfig --nodes 192.168.1.3 --force
fi

get_secrets() {
  talosctl gen secrets \
    --from-controlplane-config <(talosctl --nodes 192.168.1.3 get machineconfig v1alpha1 -o jsonpath='{.spec}') \
    --output-file -
}

export TALOS_VERSION="$(talosctl version --client --short | awk '{printf "%s", $2}')"

get_schematic_id() {
  curl -sS --fail -X POST --data-binary @<(cat "$@")  "https://factory.talos.dev/schematics" \
    | python3 -c 'import sys, json; print(json.load(sys.stdin)["id"])'
}

