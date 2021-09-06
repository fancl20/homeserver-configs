#!/bin/bash -e

# Disable root and allow nopassword sudo
sudo sed -i -E 's/^# (.+NOPASSWD: ALL)$/\1/' /etc/sudoers
sudo passwd -l root

# Config Network and hostname
sudo nmcli connection modify enp2s0 connection.autoconnect true ipv4.method manual ipv4.addr 192.168.1.2/24 ipv4.gateway 192.168.1.1 ipv4.dns 192.168.1.1 save persistent
sudo nmcli connection up enp2s0
sudo hostnamectl set-hostname 'homeserver-controller'

# Disable zezere_ignition
sudo systemctl disable zezere_ignition.timer

# Set up ssh login
mkdir -m=700 .ssh
cat > .ssh/authorized_keys <<EOF
.ssh/authorized_keys
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCk/s33bUlRi5Suh51pf5ugCI+ZRi1TViu9J0H6AfSLQa8Wj6vHmUv4Lh4OAupu7Gmkrv8sZErdcCbkZ2KTGvzfqgUA+MaHa4f2Kp69OaRh0ju09RloAk5ICyu30JMakjx0LohgKiK2111OwxbS1g+UQkMzMygGpS6E9z+GOBJMB/Lt9wP25Uu05gd1WpiC5PcIChtsd9di99fm9VTE02qqjlfgwtaTHkiuDAVfcRC92M6m/3LappjA2IW5muy7t3PyHeH4dUxvnFrq9wPIA2uvqmbrPK+lV9OHnvj6IClZUc7aoTmRbyN+7VbyuwqXtVGwPgbSqf8ufLXQtzGJA4/B fancl20@gmail.com
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH/ptWtDtPfPNTsRA8gfmJxMeBBKonWMoxFmpwLKPpMF id_ed25519_cat@ServerCat
EOF
chmod 600 .ssh/authorized_keys

# Update rpm-ostree
sudo rpm-ostree update
sudo rpm-ostree kargs --append mitigations=off

# Sync time
sudo systemctl enable --now chronyd

# Mount disk
mkdir -p /mnt/data
sudo cp systemd/var-mnt-data.mount /etc/systemd/system/
sudo cp systemd/var-mnt-data.automount /etc/systemd/system/
sudo systemctl enable --now var-mnt-data.automount

cat <<"EOF"
Reboot the system to make the change take effect:

sudo systemctl reboot
EOF
