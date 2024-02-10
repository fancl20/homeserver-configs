#!/bin/bash -e

# Install k0s
curl -sSLf https://get.k0s.sh | sudo sh
echo 'kubectl() { sudo k0s kubectl "$@"; }; export -f kubectl' >> $HOME/.bashrc

# Install flux
curl -sSLf https://fluxcd.io/install.sh | sudo bash
echo 'flux() { sudo flux --kubeconfig /var/lib/k0s/pki/admin.conf "$@"; }; export -f flux' >> $HOME/.bashrc

# Install terraform
sudo ./install_terraform.py

# Create local data volumes
mkdir -p /mnt/vault

# Initialize k0s
mkdir -p /etc/k0s && cp k0s.yaml /etc/k0s/k0s.yaml
sudo k0s install controller --enable-worker --no-taints --kubelet-extra-args='--allowed-unsafe-sysctls=net.ipv4.*,net.ipv6.*'
sudo k0s start

# Allow connections to kube-apiserver and trust Pod networking
sudo firewall-cmd --permanent --add-service=kube-apiserver
sudo firewall-cmd --permanent --zone=trusted --add-source=10.244.0.0/24
sudo firewall-cmd --permanent --zone=trusted --add-source=192.168.1.0/24

# Wait until k0s available
until sudo k0s status &> /dev/null; do sleep 1; done

sudo sed 's/localhost:6443/192.168.1.2:6443/' /var/lib/k0s/pki/admin.conf