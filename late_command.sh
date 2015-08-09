#!/bin/bash

# speed up ssh
echo "UseDNS no" >> /etc/ssh/sshd_config

# Display login promt after boot -- skip GRUB
sed "s/quiet splash//" /etc/default/grub > /tmp/grub
sed "s/GRUB_TIMEOUT=[0-9]/GRUB_TIMEOUT=0/" /tmp/grub > /etc/default/grub
update-grub

# Enable syntaxe highlight vimrc
sed -i 's/^"syntax on$/syntax on/' /etc/vim/vimrc

# Configure APT
cat > /etc/apt/apt.conf.d/02periodic <<EOL
// Enable the update/upgrade script (0=disable)
APT::Periodic::Enable "1";

// Do "apt-get update" automatically every n-days (0=disable)
APT::Periodic::Update-Package-Lists "1";

// Do "apt-get upgrade --download-only" every n-days (0=disable)
APT::Periodic::Download-Upgradeable-Packages "1";

// Run the "unattended-upgrade" security upgrade script
// every n-days (0=disabled)
// Requires the package "unattended-upgrades" and will write
// a log in /var/log/unattended-upgrades
//APT::Periodic::Unattended-Upgrade "1";

// Do "apt-get autoclean" every n-days (0=disable)
//APT::Periodic::AutocleanInterval "7";
EOL

# clean up
apt-get clean
