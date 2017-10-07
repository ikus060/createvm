## About

This script will:

 1. Download the `Debian 8.0 "Jessie"` server, 64bit iso
 2. Do some magic to turn it into a vagrant box file
 3. Output `debian-jessie` virtual machine

## Requirements

 * Oracle VM VirtualBox
 * mkisofs
 * 7zip
 * curl

## Usage on Linux

    ./build.sh --box computername --ip 192.168.14.25

This should do everything you need. If you don't have `mkisofs` or `p7zip`:

    sudo apt-get install genisoimage p7zip-full curl

## Access VM

You may then access the virtual machin via SSH.
 * username: debian
 * password: debian



