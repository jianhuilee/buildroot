#!/bin/bash

set -e

BOARD_DIR="$(dirname $0)"
BOARD_NAME="$(basename ${BOARD_DIR})"
# GENIMAGE_CFG="${BOARD_DIR}/genimage-${BOARD_NAME}.cfg"
GENIMAGE_CFG="$(mktemp --suffix genimage.cfg)"
GENIMAGE_TMP="${BUILD_DIR}/genimage.tmp"

genimage_type()
{
	echo "genimage-raspberrypi.cfg.template"
}

dtb_list()
{
	local DTB_LIST="$(sed -n 's/^BR2_LINUX_KERNEL_INTREE_DTS_NAME="\([\/a-z0-9 \-]*\)"$/\1/p' ${BR2_CONFIG})"

	for dt in $DTB_LIST; do
		echo -n "\"`basename $dt`.dtb\", "
	done
}

extras_list()
{

	case "${BOARD_NAME}" in
		"raspberry"| "raspberrypi0" | "raspberrypi2")
		echo -n "\"rpi-firmware\/bootcode.bin\", "
		echo -n "\"rpi-firmware\/fixup.dat\", "
		echo -n "\"rpi-firmware\/start.elf\", "
		;;
		"raspberrypi0w" | "raspberrypi3_64" | "raspberrypi3")
		echo -n "\"rpi-firmware\/bootcode.bin\", "
		echo -n "\"rpi-firmware\/fixup.dat\", "
		echo -n "\"rpi-firmware\/start.elf\", "
		echo -n "\"rpi-firmware\/overlays\", "
		;;
		"raspberrypi4")
		echo -n "\"rpi-firmware\/fixup4.dat\", "
		echo -n "\"rpi-firmware\/start4.elf\", "
		echo -n "\"rpi-firmware\/overlays\", "
		;;
	esac
}

linux_image()
{
	case "${BOARD_NAME}" in
		"raspberrypi3_64")
		echo "\"Image\""
		;;
		*)
		echo "\"zImage\""
		;;
	esac
}

genimage_cfg()
{
	local DTB_FILES="$(dtb_list)"
    local KIMAGE="$(linux_image)"
    local EXTRAS="$(extras_list)"

    echo "DEBUG: ${GENIMAGE_CFG}"
	sed -e "s/%DTB_FILES%/${DTB_FILES}/" \
		-e "s/%EXTRAS%/${EXTRAS}/" \
		-e "s/%KIMAGE%/${KIMAGE}/" \
		board/raspberrypi/$(genimage_type) > ${GENIMAGE_CFG}
}

dtb_config()
{
	if grep -Eq "^BR2_LINUX_KERNEL_LATEST_VERSION=y$" ${BR2_CONFIG}; then
		local DTB_NAME="$(sed -n \
						's/^BR2_LINUX_KERNEL_INTREE_DTS_NAME="\([a-z0-9\-]*\).*"$/\1/p' \
						${BR2_CONFIG}).dtb"
		cat << __EOF__ >> "${BINARIES_DIR}/rpi-firmware/config.txt"
			device_tree=${DTB_NAME}
__EOF__
	fi
}

for arg in "$@"
do
	case "${arg}" in
		--add-pi3-miniuart-bt-overlay)
		if ! grep -qE '^dtoverlay=' "${BINARIES_DIR}/rpi-firmware/config.txt"; then
			echo "Adding 'dtoverlay=pi3-miniuart-bt' to config.txt (fixes ttyAMA0 serial console)."
			cat << __EOF__ >> "${BINARIES_DIR}/rpi-firmware/config.txt"

# fixes rpi3 ttyAMA0 serial console
dtoverlay=pi3-miniuart-bt
__EOF__
		fi
		;;
		--aarch64)
		# Run a 64bits kernel (armv8)
		sed -e '/^kernel=/s,=.*,=Image,' -i "${BINARIES_DIR}/rpi-firmware/config.txt"
		if ! grep -qE '^arm_64bit=1' "${BINARIES_DIR}/rpi-firmware/config.txt"; then
			cat << __EOF__ >> "${BINARIES_DIR}/rpi-firmware/config.txt"

# enable 64bits support
arm_64bit=1
__EOF__
		fi

		# Enable uart console
		if ! grep -qE '^enable_uart=1' "${BINARIES_DIR}/rpi-firmware/config.txt"; then
			cat << __EOF__ >> "${BINARIES_DIR}/rpi-firmware/config.txt"

# enable rpi3 ttyS0 serial console
enable_uart=1
__EOF__
		fi
		;;
		--gpu_mem_256=*|--gpu_mem_512=*|--gpu_mem_1024=*)
		# Set GPU memory
		gpu_mem="${arg:2}"
		sed -e "/^${gpu_mem%=*}=/s,=.*,=${gpu_mem##*=}," -i "${BINARIES_DIR}/rpi-firmware/config.txt"
		;;
	esac

done

# Pass an empty rootpath. genimage makes a full copy of the given rootpath to
# ${GENIMAGE_TMP}/root so passing TARGET_DIR would be a waste of time and disk
# space. We don't rely on genimage to build the rootfs image, just to insert a
# pre-built one in the disk image.

trap 'rm -rf "${ROOTPATH_TMP}"' EXIT
ROOTPATH_TMP="$(mktemp -d)"

genimage_cfg
dtb_config

rm -rf "${GENIMAGE_TMP}"

genimage \
	--rootpath "${ROOTPATH_TMP}"   \
	--tmppath "${GENIMAGE_TMP}"    \
	--inputpath "${BINARIES_DIR}"  \
	--outputpath "${BINARIES_DIR}" \
	--config "${GENIMAGE_CFG}"

# rm -f ${GENIMAGE_CFG}

exit $?
