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

    ./build.sh

This should do everything you need. If you don't have `mkisofs` or `p7zip`:

    sudo apt-get install genisoimage p7zip-full curl

## Environment variables

You can affect the default behaviour of the script using environment variables:

    VAR=value ./build.sh

The following variables are supported:

* `PRESEED` — path to custom preseed file. May be useful when if you need some customizations for your private base box (user name, passwords etc.);

* `LATE_CMD` — path to custom late_command.sh. May be useful when if you need some customizations for your private base box (user name, passwords etc.);

* `VM_GUI` — if set to `yes` or `1`, disables headless mode for vm. May be useful for debugging installer;
