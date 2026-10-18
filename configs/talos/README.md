# talos-configs
Talos configuration for homecluster

## Upgrade Node
```bash
./scripts/upgrade.sh
talosctl upgrade-k8s --nodes 192.168.1.3
```

## Debug
```bash
# Network Issues
talosctl -nodes 192.168.1.3 get addressspecs [ID] -o yaml
talosctl -nodes 192.168.1.3 get meta 0x0a
```

