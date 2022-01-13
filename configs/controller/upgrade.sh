#!/bin/bash -e

[ $(id -u) == 0 ] ||  exec sudo "$0" "$@"

# Upgrade k0s
sudo k0s stop
curl -sSLf https://get.k0s.sh | sudo sh
sudo k0s start

# Upgrade helm
curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash

# Upgrade terraform
sudo ./setup-01-k0s/install_terraform.py

# Upgrade version env

# Apply terraform configs
(cd ./setup-02-services && ./setup-02-services.sh)
