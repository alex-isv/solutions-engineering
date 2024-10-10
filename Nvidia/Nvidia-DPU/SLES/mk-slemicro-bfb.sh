#!/bin/bash
# Copyright (c) 2024 SUSE LLC
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#
set -e

BOOTIMGS_RPM=mlxbf-bootimages-signed-4.5.0-12993.aarch64.rpm
BOOTIMGS_RPM_URL=https://linux.mellanox.com/public/repo/bluefield/4.5.0-12993/bootimages/prod/${BOOTIMGS_RPM}
MLX_MKBFB_URL=https://raw.githubusercontent.com/Mellanox/bfscripts/master/mlx-mkbfb
BFB_INSTALL_URL=https://raw.githubusercontent.com/Mellanox/rshim-user-space/master/scripts/bfb-install

usage () {
    echo "$0 <SLE-Micro.raw.xz>"
    exit 1
}

if [ "$EUID" -ne 0 ]; then
    echo "Please run as root"
    exit 1
fi

if ! (which wget > /dev/null 2>&1); then
	echo "wget is required to build BFB"
	exit 1
fi

if [ "$#" -ne 1 ]; then
    usage
fi

SUSE_MEDIA=$1
if [ ! -f ${SUSE_MEDIA} ]; then
    echo "${SUSE_MEDIA} is missing"
    exit 1
fi

#===========================================
echo "Using ${SUSE_MEDIA}"

WORK_DIR=$(pwd)

FILE_NAME=$(basename -- "$1")
FILE_EXT="${FILE_NAME##*.}"

case $FILE_EXT in

    "iso")
    OS_IMAGE=${SUSE_MEDIA}
    # Not ready
    exit 1
    ;;

    "xz")
    OS_IMAGE="${SUSE_MEDIA%.*}"
    echo "Unpacking ${SUSE_MEDIA} ..."
    if [ ! -f ${OS_IMAGE} ]; then
        xz -d -k ${SUSE_MEDIA}
    fi
    ;;

    *)
    usage
    ;;
esac

cat > suse-install.sh << EOF
#!/bin/sh

PATH=$PATH:/usr/bin

echo 'V' > /dev/watchdog
xz -d OS.raw.xz

# BF3 has nvme

if [ -b /dev/nvme0n1 ]; then
	dd bs=4M if=/OS.raw of=/dev/nvme0n1 iflag=fullblock oflag=sync
else
dd bs=4M if=/OS.raw of=/dev/mmcblk0 iflag=fullblock oflag=sync
sync
echo "Rebooting ..."
reboot -f
echo b > /proc/sysrq-trigger
EOF

cat > suse-install.service << EOF
[Unit]
Description=SUSE Instalation
#After=

[Service]
Type=simple
ExecStart=/bin/bash /scripts/suse-install.sh
StandardOutput=journal+console

[Install]
WantedBy=initrd.target
EOF

chmod +x suse-install.sh
chown root:root suse-install.sh suse-install.service

if [ ! -f default.bfb ] || [ ! -f boot_update2.cap ]; then
    echo "Downloading default.bfb and boot_update2.cap ..."
    wget --quiet ${BOOTIMGS_RPM_URL}
    rpm2cpio ${BOOTIMGS_RPM} | cpio -dium --quiet
    mv ./lib/firmware/mellanox/boot/default.bfb ./lib/firmware/mellanox/boot/capsule/boot_update2.cap .
    rm -rf ./lib ${BOOTIMGS_RPM}
fi

if [ ! -x mlx-mkbfb ]; then
    echo "Downloading mlx-mkbfb tool ..."
    wget --quiet ${MLX_MKBFB_URL}
    chmod +x mlx-mkbfb
fi

if [ ! -x bfb-install ]; then
    echo "Downloading bfb-install tool ..."
    wget --quiet ${BFB_INSTALL_URL}
    chmod +x bfb-install
fi

#===========================================
echo "Extracting kernel image and initramfs ..."

MNT_DIR=${WORK_DIR}/mnt
mkdir -p ${MNT_DIR}

LODEV=$(/usr/sbin/losetup --show -f -P ${OS_IMAGE})
KNAME=$(lsblk -o kname $LODEV | tail -n 1)
mount /dev/${KNAME} ${MNT_DIR}

case $FILE_EXT in
    "iso")
    cp ${MNT_DIR}/boot/aarch64/linux suse-kernel
    cp ${MNT_DIR}/boot/aarch64/initrd suse-initrd
    ;;

    "xz")
    cp $(ls ${MNT_DIR}/boot/Image-*) suse-kernel
    cp $(ls ${MNT_DIR}/boot/initrd-*) suse-initrd
    ;;
esac

# # Update /etc/default/grub console=
# for file in "${MNT_DIR}/boot/grub2/grub.cfg ${MNT_DIR}/etc/default/grub"; do
#     sed -i -e 's/console=ttyS0,115200n8//' $file
#     sed -i -e 's/console=tty0/console=ttyAMA0,115200n8 console=ttyAMA1,115200n8 console=hvc0 earlycon/' $file
#     # Temporary
#     sed -i -e 's/security=selinux//' -e 's/selinux=1//' $file
#     sed -i -e 's/loglevel=3/ignore_loglevel/' -e 's/splash=silent//g' $file
# done

umount ${MNT_DIR}
/usr/sbin/losetup -d ${LODEV}
rm -rf ${MNT_DIR}

#===========================================
echo "Copping ${SUSE_MEDIA} into initramfs ..."

INITRD_DIR=${WORK_DIR}/ramfs
mkdir -p ${INITRD_DIR}

unzstd -df suse-initrd -o suse-initrd.cpio
pushd ${INITRD_DIR} > /dev/null
cpio -id --quiet < ${WORK_DIR}/suse-initrd.cpio
rm -f ${WORK_DIR}/suse-initrd*

cp ${WORK_DIR}/${SUSE_MEDIA} OS.raw.xz

mkdir -p scripts
mv ${WORK_DIR}/suse-install.sh scripts/suse-install.sh
mv ${WORK_DIR}/suse-install.service usr/lib/systemd/system/
ln -sf /usr/lib/systemd/system/suse-install.service etc/systemd/system/initrd.target.wants/suse-install.service

#===========================================
echo "Rebuilding initramfs ..."

find . -print0 | cpio --null -o --quiet --format=newc | gzip -9 > ${WORK_DIR}/new-initrd
popd > /dev/null
rm -rf ${INITRD_DIR}

#===========================================
echo "Preparing bootstream artefacs ... "

printf "console=ttyAMA1,115200n8 console=hvc0 console=ttyAMA0,115200n8 earlycon=pl011,0x01000000 earlycon=pl011,0x01800000 initrd=initramfs rd.shell rd.break=mount" > boot_args.txt
printf "console=ttyAMA1,115200n8 console=hvc0 console=ttyAMA0,115200n8 earlycon=pl011,0x13010000 initrd=initramfs rd.shell rd.break=mount" > boot_args2.txt
printf "VenHw(F019E406-8C9C-11E5-8797-001ACA00BFC4)/Image" > boot_path.txt
printf "Linux from rshim" > boot_desc.txt

if [ $FILE_EXT == "iso" ]; then
    echo " nomodeset linemode=1 textmode=1 instsys.complain=0 ignore_loglevel usessh=1 sshpassword=linux linuxrc.debug=4 linuxrc.log=/dev/console " >> boot_args.txt
fi

#===========================================
echo "Assembling bitstream file ..."

./mlx-mkbfb --image suse-kernel \
	--initramfs new-initrd \
	--capsule boot_update2.cap \
	--boot-args-v0 boot_args.txt \
	--boot-args-v2 boot_args2.txt \
	--boot-path boot_path.txt \
	--boot-desc boot_desc.txt \
	default.bfb ${OS_IMAGE}.bfb

rm -f boot_*txt new-initrd default.bfb boot_update2.cap \
        mlx-mkbfb suse-kernel ${OS_IMAGE}

#===========================================
echo "${OS_IMAGE}.bfb is ready!"

echo "Example command to flash your DPU device"
echo "./bfb-install -b ${OS_IMAGE}.bfb -r rshimX"
