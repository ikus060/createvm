#!/bin/bash
# Originally taken from https://github.com/dotzero/vagrant-debian-jessie-64
# 
# Author: unknown
# Modify: Patrik Dufresne
#
declare -rx PROGNAME=${0##*/}
declare -rx PROGPATH="$(realpath "${0%/*}")"
VERSION="1.0"
AUTHOR="Patrik Dufresne"

# Define default arguments value
DOMAIN="patrikdufresne.com"
MASK="255.255.255.0"
GW="192.168.14.1"
DEBIAN="stretch"

# location, location, location
FOLDER_BASE="/tmp"
FOLDER_ISO="/var/lib/vz/template/iso/"
FOLDER_BUILD="${TARGET}/build"
FOLDER_ISO_CUSTOM="${FOLDER_BUILD}/iso/custom"
FOLDER_ISO_INITRD="${FOLDER_BUILD}/iso/initrd"

RESULT=`getopt --name "$SCRIPT" --options "h" --longoptions "help,iso:,debian:" -- "$@"`
eval set -- "$RESULT"
while [ $# -gt 0 ] ; do
  case "$1" in
    -h | --help)
	    printf "$PROGNAME version $VERSION by $AUTHOR
Used to create virtual machine.
  -h, --help            display this message.
  --iso=folder          where to download iso files (default: $FOLDER_ISO)
  --debian=version      the debian version: wheezy or jessie (default: $DEBIAN)
"
      exit 0;;
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

# make sure we have dependencies
hash 7z 2>/dev/null || { echo >&2 "ERROR: 7z not found. Aborting."; exit 1; }
hash curl 2>/dev/null || { echo >&2 "ERROR: curl not found. Aborting."; exit 1; }
hash cpio 2>/dev/null || { echo >&2 "ERROR: cpio not found. Aborting."; exit 1; }

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
#set -o xtrace

# Configurations
if [ "x$DEBIAN" == "xwheezy" ]; then
  ISO_URL="http://cdimage.debian.org/mirror/cdimage/archive/7.11.0/amd64/iso-cd/debian-7.11.0-amd64-CD-1.iso"
  ISO_MD5="51853a6fea6f2b2e405956bd713553cd"
elif [ "x$DEBIAN" == "xjessie" ]; then
  ISO_URL="http://cdimage.debian.org/mirror/cdimage/archive/8.9.0/amd64/iso-cd/debian-8.9.0-amd64-CD-1.iso"
  ISO_MD5="be1ec9943ded8d974d535c44230394fe"
elif [ "x$DEBIAN" == "xstretch" ]; then
  ISO_URL="http://cdimage.debian.org/mirror/cdimage/archive/9.0.0/amd64/iso-cd/debian-9.0.0-amd64-netinst.iso"
  ISO_MD5="83253a530270e46a5d6e66daf3431c33"
fi

# Env option: Use custom preseed.cfg or default
PRESEED="/tmp/$$.preseed.cfg"
cp "$PROGPATH/preseed.cfg" "$PRESEED"
sed -i -e "s/\${debian}/$DEBIAN/" "$PRESEED"

if [ "$OSTYPE" = "linux-gnu" ]; then
  MD5="md5sum"
elif [ "$OSTYPE" = "msys" ]; then
  MD5="md5 -l"
else
  MD5="md5 -q"
fi

# start with a clean slate
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
  cp "${PROGPATH}/isolinux.cfg" "${FOLDER_ISO_CUSTOM}/isolinux/isolinux.cfg"
  chmod u+w "${FOLDER_ISO_CUSTOM}/isolinux/isolinux.bin"

  echo "Running mkisofs ..."
  "$MKISOFS" -r -V "Custom Debian Install CD" \
    -cache-inodes -quiet \
    -J -l -b isolinux/isolinux.bin \
    -c isolinux/boot.cat -no-emul-boot \
    -boot-load-size 4 -boot-info-table \
    -o "${FOLDER_ISO}/${ISO_CUSTOM_FILENAME}" "${FOLDER_ISO_CUSTOM}"
fi

# references:
# http://blog.ericwhite.ca/articles/2009/11/unattended-debian-lenny-install/
# http://docs-v1.vagrantup.com/v1/docs/base_boxes.html
# http://www.debian.org/releases/stable/example-preseed.txt

