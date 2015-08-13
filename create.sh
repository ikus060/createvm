#!/bin/bash
# Originally taken from https://github.com/dotzero/vagrant-debian-jessie-64
# 
# Author: unknown
# Modify: Patrik Dufresne
#
declare -rx PROGNAME=${0##*/}
VERSION="1.0"
AUTHOR="Patrik Dufresne"

# Define default arguments value
VM_GUI=0
VRDE=1
MEMORY="512" # 512MiB
DISK="8192" # 8GiB
BOX=""
DOMAIN=""
IP=""
MASK="255.255.255.0"
GW="192.168.14.1"
DEBIAN="jessie"

# location, location, location
FOLDER_BASE=$(pwd)
#FOLDER_ISO="${FOLDER_BASE}/iso"
FOLDER_ISO="$HOME/iso"
FOLDER_BUILD="${FOLDER_BASE}/build"
#FOLDER_VBOX="${FOLDER_BUILD}/vbox"
FOLDER_VBOX="$HOME/VirtualBox VMs"
FOLDER_ISO_CUSTOM="${FOLDER_BUILD}/iso/custom"
FOLDER_ISO_INITRD="${FOLDER_BUILD}/iso/initrd"

RESULT=`getopt --name "$SCRIPT" --options "h,b:,i:,d:" --longoptions "help,box:,domain:,ip:,mask:,gw:,memory:,disk:,dest:,iso:,debian:" -- "$@"`
eval set -- "$RESULT"
while [ $# -gt 0 ] ; do
  case "$1" in
    -h | --help)
	    printf "$PROGNAME version $VERSION by $AUTHOR
Used to create virtual machine.
  -h, --help            display this message.
  -b, --box=hostname    the virtual box name.
  --domain=domain       the domain name (default: none).
  -i, --ip=address      the IP address to be set.
  --mask=mask           the network mask. (default: $MASK)
  --gateway=gateway     the gateway. (default: $GW)
  --memory=size         the memory size in MiB. (default: $MEMORY)
  --disk=size           the disk size in MiB. (default: $DISK)
  -d, --dest=folder     the virtual box destination (default: $FOLDER_VBOX)
  --iso=folder          where to download iso files (default: $FOLDER_ISO)
  --debian=version      the debian version: wheezy or jessie (default: $DEBIAN)
"
      exit 0;;
    -b | --box)
      shift
      BOX=$1;;
     --domain)
      shift
      DOMAIN=$1;;
     -i | --ip)
      shift
      IP=$1;;
     --mask)
      shift
      MASK=$1;;
     --gw)
      shift
      GW=$1;;
     --memory)
      shift
      MEMORY=$1;;
     --disk)
      shift
      DISK=$1;;
     -d | --dest)
      shift
      FOLDER_VBOX=$1;;
     --iso)
      shift
      FOLDER_ISO=$1;;
     --debian)
      shift
      DEBIAN=$1;;
    --)
      shift
      break;;
    *)
      echo "Option $1 not supported. Ignored." >&2;;
  esac
  shift
done

[ ! -z "$BOX" ] || { echo >&2 "ERROR: --box not define.  Aborting."; exit 1; }
[ ! -z "$IP" ] || { echo >&2 "ERROR: --ip not define.  Aborting."; exit 1; }


# make sure we have dependencies
hash vagrant 2>/dev/null || { echo >&2 "ERROR: vagrant not found.  Aborting."; exit 1; }
hash VBoxManage 2>/dev/null || { echo >&2 "ERROR: VBoxManage not found.  Aborting."; exit 1; }
hash 7z 2>/dev/null || { echo >&2 "ERROR: 7z not found. Aborting."; exit 1; }
hash curl 2>/dev/null || { echo >&2 "ERROR: curl not found. Aborting."; exit 1; }
hash cpio 2>/dev/null || { echo >&2 "ERROR: cpio not found. Aborting."; exit 1; }

VBOX_VERSION="$(VBoxManage --version)"

if hash mkisofs 2>/dev/null; then
  MKISOFS="$(which mkisofs)"
elif hash genisoimage 2>/dev/null; then
  MKISOFS="$(which genisoimage)"
else
  echo >&2 "ERROR: mkisofs or genisoimage not found.  Aborting."
  exit 1
fi

set -o nounset
set -o errexit
set -o xtrace

# Configurations

if [ "x$DEBIAN" == "xwheezy" ]; then
  ISO_URL="http://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-8.1.0-amd64-CD-1.iso"
  ISO_MD5="4af143814e0b0ab623289222eddb280d"
elif [ "x$DEBIAN" == "xjessie" ]; then
  ISO_URL="http://cdimage.debian.org/mirror/cdimage/archive/7.8.0/amd64/iso-cd/debian-7.8.0-amd64-CD-1.iso"
  ISO_MD5="0e3d2e7bc3cd7c97f76a4ee8fb335e43"
fi

# Env option: Use headless mode or GUI
VM_GUI="${VM_GUI:-}"
if [ "x${VM_GUI}" == "xyes" ] || [ "x${VM_GUI}" == "x1" ]; then
  STARTVM="VBoxManage startvm ${BOX}"
else
  STARTVM="VBoxManage startvm ${BOX} --type headless"
fi
STOPVM="VBoxManage controlvm ${BOX} poweroff"

# Env option: Use custom preseed.cfg or default
DEFAULT_PRESEED="preseed.cfg"
PRESEED="${PRESEED:-"$DEFAULT_PRESEED"}"
cp "$PRESEED" "/tmp/$$.preseed.cfg"
PRESEED="/tmp/$$.preseed.cfg"
sed -i -e "s/\${hostname}/$BOX/" "$PRESEED"
sed -i -e "s/\${domain}/$DOMAIN/" "$PRESEED"
sed -i -e "s/\${ip}/$IP/" "$PRESEED"
sed -i -e "s/\${mask}/$MASK/" "$PRESEED"
sed -i -e "s/\${gw}/$GW/" "$PRESEED"
sed -i -e "s/\${debian}/$DEBIAN/" "$PRESEED"

# Env option: Use custom late_command.sh or default
DEFAULT_LATE_CMD="${FOLDER_BASE}/late_command.sh"
LATE_CMD="${LATE_CMD:-"$DEFAULT_LATE_CMD"}"

# Parameter changes from 4.2 to 4.3
if [[ "$VBOX_VERSION" < 4.3 ]]; then
  PORTCOUNT="--sataportcount 1"
else
  PORTCOUNT="--portcount 1"
fi

if [ "$OSTYPE" = "linux-gnu" ]; then
  MD5="md5sum"
elif [ "$OSTYPE" = "msys" ]; then
  MD5="md5 -l"
else
  MD5="md5 -q"
fi

# start with a clean slate
if VBoxManage list runningvms | grep "${BOX}" >/dev/null 2>&1; then
  echo "Stopping vm ..."
  ${STOPVM}
fi
if VBoxManage showvminfo "${BOX}" >/dev/null 2>&1; then
  echo "Unregistering vm ..."
  VBoxManage unregistervm "${BOX}" --delete
fi
if [ -d "${FOLDER_BUILD}" ]; then
  echo "Cleaning build directory ..."
  chmod -R u+w "${FOLDER_BUILD}"
  rm -rf "${FOLDER_BUILD}"
fi
ISO_CUSTOM_FILENAME="${ISO_URL##*/}"
ISO_CUSTOM_FILENAME="${ISO_CUSTOM_FILENAME%.iso}-preseed.iso"
if [ -f "${FOLDER_ISO}/${ISO_CUSTOM_FILENAME}" ]; then
  echo "Removing custom iso ..."
  rm "${FOLDER_ISO}/${ISO_CUSTOM_FILENAME}"
fi

# Setting things back up again
mkdir -p "${FOLDER_ISO}"
mkdir -p "${FOLDER_BUILD}"
mkdir -p "${FOLDER_VBOX}"
mkdir -p "${FOLDER_ISO_CUSTOM}"
mkdir -p "${FOLDER_ISO_INITRD}"

ISO_FILENAME="${FOLDER_ISO}/`basename ${ISO_URL}`"
INITRD_FILENAME="${FOLDER_ISO}/initrd.gz"

# download the installation disk if you haven't already or it is corrupted somehow
echo "Downloading `basename ${ISO_URL}` ..."
if [ ! -e "${ISO_FILENAME}" ]; then
  curl --output "${ISO_FILENAME}" -L "${ISO_URL}"
fi

# make sure download is right...
ISO_HASH=$($MD5 "${ISO_FILENAME}" | cut -d ' ' -f 1)
if [ "${ISO_MD5}" != "${ISO_HASH}" ]; then
  echo "ERROR: MD5 does not match. Got ${ISO_HASH} instead of ${ISO_MD5}. Aborting."
  exit 1
fi

# customize it
echo "Creating Custom ISO"

if [ ! -e "${FOLDER_ISO}/${ISO_CUSTOM_FILENAME}" ]; then

  echo "Using 7zip"
  7z x "${ISO_FILENAME}" -o"${FOLDER_ISO_CUSTOM}"

  # If that didn't work, you have to update p7zip
  if [ ! -e $FOLDER_ISO_CUSTOM ]; then
    echo "Error with extracting the ISO file with your version of p7zip. Try updating to the latest version."
    exit 1
  fi

  # backup initrd.gz
  echo "Backing up current init.rd ..."
  FOLDER_INSTALL=$(ls -1 -d "${FOLDER_ISO_CUSTOM}/install."* | sed 's/^.*\///')
  chmod u+w "${FOLDER_ISO_CUSTOM}/${FOLDER_INSTALL}" "${FOLDER_ISO_CUSTOM}/install" "${FOLDER_ISO_CUSTOM}/${FOLDER_INSTALL}/initrd.gz"
  cp -r "${FOLDER_ISO_CUSTOM}/${FOLDER_INSTALL}/"* "${FOLDER_ISO_CUSTOM}/install/"
  mv "${FOLDER_ISO_CUSTOM}/install/initrd.gz" "${FOLDER_ISO_CUSTOM}/install/initrd.gz.org"

  # stick in our new initrd.gz
  echo "Installing new initrd.gz ..."
  cd "${FOLDER_ISO_INITRD}"
  if [ "$OSTYPE" = "msys" ]; then
    gunzip -c "${FOLDER_ISO_CUSTOM}/install/initrd.gz.org" | cpio -i --make-directories || true
  else
    gunzip -c "${FOLDER_ISO_CUSTOM}/install/initrd.gz.org" | cpio -id || true
  fi
  cd "${FOLDER_BASE}"
  if [ "${PRESEED}" != "${DEFAULT_PRESEED}" ] ; then
    echo "Using custom preseed file ${PRESEED}"
  fi
  cp "${PRESEED}" "${FOLDER_ISO_INITRD}/preseed.cfg"
  #rm "${PRESEED}"
  cd "${FOLDER_ISO_INITRD}"
  find . | cpio --create --format='newc' | gzip  > "${FOLDER_ISO_CUSTOM}/install/initrd.gz"

  # clean up permissions
  echo "Cleaning up Permissions ..."
  chmod u-w "${FOLDER_ISO_CUSTOM}/install" "${FOLDER_ISO_CUSTOM}/install/initrd.gz" "${FOLDER_ISO_CUSTOM}/install/initrd.gz.org"

  # replace isolinux configuration
  echo "Replacing isolinux config ..."
  cd "${FOLDER_BASE}"
  chmod u+w "${FOLDER_ISO_CUSTOM}/isolinux" "${FOLDER_ISO_CUSTOM}/isolinux/isolinux.cfg"
  rm "${FOLDER_ISO_CUSTOM}/isolinux/isolinux.cfg"
  cp isolinux.cfg "${FOLDER_ISO_CUSTOM}/isolinux/isolinux.cfg"
  chmod u+w "${FOLDER_ISO_CUSTOM}/isolinux/isolinux.bin"

  # add late_command script
  echo "Add late_command script ..."
  chmod u+w "${FOLDER_ISO_CUSTOM}"
  cp "${LATE_CMD}" "${FOLDER_ISO_CUSTOM}/late_command.sh"

  echo "Running mkisofs ..."
  "$MKISOFS" -r -V "Custom Debian Install CD" \
    -cache-inodes -quiet \
    -J -l -b isolinux/isolinux.bin \
    -c isolinux/boot.cat -no-emul-boot \
    -boot-load-size 4 -boot-info-table \
    -o "${FOLDER_ISO}/${ISO_CUSTOM_FILENAME}" "${FOLDER_ISO_CUSTOM}"
fi

echo "Creating VM Box..."
# create virtual machine
if ! VBoxManage showvminfo "${BOX}" >/dev/null 2>&1; then
  VBoxManage createvm \
    --name "${BOX}" \
    --ostype Debian_64 \
    --register \
    --basefolder "${FOLDER_VBOX}"

  VBoxManage modifyvm "${BOX}" \
    --memory "$MEMORY" \
    --boot1 dvd \
    --boot2 disk \
    --boot3 none \
    --boot4 none \
    --vram 12 \
    --pae off \
    --rtcuseutc on

  VBoxManage storagectl "${BOX}" \
    --name "IDE Controller" \
    --add ide \
    --controller PIIX4 \
    --hostiocache on

  VBoxManage storageattach "${BOX}" \
    --storagectl "IDE Controller" \
    --port 1 \
    --device 0 \
    --type dvddrive \
    --medium "${FOLDER_ISO}/${ISO_CUSTOM_FILENAME}"

  VBoxManage storagectl "${BOX}" \
    --name "SATA Controller" \
    --add sata \
    --controller IntelAhci \
    $PORTCOUNT \
    --hostiocache off

  VBoxManage createhd \
    --filename "${FOLDER_VBOX}/${BOX}/${BOX}.vdi" \
    --size "$DISK"

  VBoxManage storageattach "${BOX}" \
    --storagectl "SATA Controller" \
    --port 0 \
    --device 0 \
    --type hdd \
    --medium "${FOLDER_VBOX}/${BOX}/${BOX}.vdi"

  # Enable remote desktop if required
  VRDE="${VRDE:-}"
  if [ "x${VRDE}" == "xyes" ] || [ "x${VRDE}" == "x1" ]; then
    VBoxManage modifyvm "${BOX}" \
      --vrde on
  fi

  # Configure network as bridge.
  VBoxManage modifyvm "${BOX}" \
    --nic1 bridged --nictype2 82540EM --bridgeadapter1 'bond0'

  ${STARTVM}

  echo -n "Waiting for installer to finish "
  while VBoxManage list runningvms | grep "${BOX}" >/dev/null; do
    sleep 20
    echo -n "."
  done
  echo ""

  # Detach ISO
  VBoxManage storageattach "${BOX}" \
    --storagectl "IDE Controller" \
    --port 1 \
    --device 0 \
    --type dvddrive \
    --medium emptydrive
fi

# references:
# http://blog.ericwhite.ca/articles/2009/11/unattended-debian-lenny-install/
# http://docs-v1.vagrantup.com/v1/docs/base_boxes.html
# http://www.debian.org/releases/stable/example-preseed.txt
