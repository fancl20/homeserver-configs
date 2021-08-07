#!/bin/bash -e

# Install k0s
curl -sSLf https://get.k0s.sh | sudo sh
echo 'kubectl() { sudo k0s kubectl "$@"; }; export -f kubectl' >> $HOME/.bashrc

# Install helm
curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash
echo 'helm() { sudo helm --kubeconfig /var/lib/k0s/pki/admin.conf "$@"; }; export -f helm' >> $HOME/.bashrc

# Install terraform
sudo ./install_terraform.py

# Initialize k0s
sudo k0s install controller --enable-worker -c k0s.yaml
sudo k0s start

# Allow connections to kube-apiserver and trust Pod networking
sudo firewall-cmd --permanent --add-service=kube-apiserver
sudo firewall-cmd --permanent --add-source=10.244.0.0/24

# Wait until k0s available
until sudo k0s status &> /dev/null; do sleep 1; done

sudo sed 's/localhost:6443/192.168.1.2:6443/' /var/lib/k0s/pki/admin.conf