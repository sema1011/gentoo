#!/bin/bash
#-------------------------------------------------------------------------------
# x86_64/remote_gentoo.sh
#-------------------------------------------------------------------------------
# Copyright 2012 Dowd and Associates
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#-------------------------------------------------------------------------------

VOLUME=/dev/sda1
TMPDIR=/mnt/gentoo/tmp
VIRTUAL_ROOT_DEVICE=/dev/sda1

echo "mkfs -t ext4 ${VOLUME}"
mkfs -t ext4 $VOLUME
echo "mkdir -p /mnt/gentoo"
mkdir -p /mnt/gentoo

mount $VOLUME /mnt/gentoo

mkdir -p $TMPDIR
cd $TMPDIR
echo "Download stage3"
LATEST=`curl --silent http://mirror.iawnet.sandia.gov/gentoo/releases/amd64/autobuilds/latest-stage3-amd64.txt | grep stage3-amd64`
curl -O http://mirror.iawnet.sandia.gov/gentoo/releases/amd64/autobuilds/$LATEST
echo "Download portage"
curl -O http://mirror.iawnet.sandia.gov/gentoo/releases/snapshots/current/portage-latest.tar.bz2
echo "Unpack stage3"
tar -xjpf /tmp/stage3-*.tar.bz2 -C /mnt/gentoo
echo "Unpack portage"
tar -xjf /tmp/portage*.tar.bz2 -C /mnt/gentoo/usr

echo "Setup files"

mkdir -p /mnt/gentoo/boot/grub
echo "/boot/grub/menu.lst"
cat <<'EOF'>/mnt/gentoo/boot/grub/menu.lst.tmp
default 0
timeout 3
title EC2
root (hd0)
kernel /boot/bzImage root=/dev/$VRD rootfstype=ext4
EOF
sed -e "s/$VRD/$VIRTUAL_ROOT_DEVICE/" /mnt/gentoo/boot/grub/menu.lst.tmp > /mnt/gentoo/boot/grub/menu.lst
echo "output of menu.lst"
cat /mnt/gentoo/boot/grub/menu.lst
sleep 10

echo "/etc/fstab"
cat <<'EOF'>/mnt/gentoo/etc/fstab.tmp
/dev/$VRD / ext4 defaults 1 1
none /dev/pts devpts gid=5,mode=620 0 0
none /dev/shm tmpfs defaults 0 0
none /proc proc defaults 0 0
none /sys sysfs defaults 0 0
EOF
sed -e "s/$VRD/$VIRTUAL_ROOT_DEVICE/" /mnt/gentoo/etc/fstab.tmp > /mnt/gentoo/etc/fstab
echo "output of fstab"
cat /mnt/gentoo/etc/fstab
sleep 10

mkdir -p /mnt/gentoo/etc/local.d

mkdir -p /mnt/gentoo/etc/portage

CPUS=`cat /proc/cpuinfo |grep processor |wc -l`

echo "/etc/portage/make.conf"
cat <<'EOF'>/mnt/gentoo/etc/portage/make.conf.tmp
# These settings were set by the catalyst build script that automatically
# built this stage.
# Please consult /usr/share/portage/config/make.conf.example for a more
# detailed example.
CFLAGS="-O2 -pipe"
CXXFLAGS="${CFLAGS}"
# WARNING: Changing your CHOST is not something that should be done lightly.
# Please consult http://www.gentoo.org/doc/en/change-chost.xml before changing.
CHOST="x86_64-pc-linux-gnu"
# These are the USE flags that were used in addition to what is provided by the
# profile used for building.
USE="mmx sse sse2"
MAKEOPTS="-j3"
EMERGE_DEFAULT_OPTS="--jobs=$CPUNUM --load-average=3.0"
EOF
sed -e "s/$CPUNUM/$CPUS/" /etc/portage/make.conf.tmp > /etc/portage/make.conf

echo "output of make.conf"
cat /etc/portage/make.conf
sleep 10
echo "/etc/resolv.conf"
cp -L /etc/resolv.conf /mnt/gentoo/etc/resolv.conf

# mkdir -p /mnt/gentoo/etc/sudoers.d
# echo "/etc/sudoers.d/ec2-user"
# cat <<'EOF'>/mnt/gentoo/etc/sudoers.d/ec2-user
# ec2-user  ALL=(ALL) NOPASSWD:ALL
# EOF
# chmod 440 /mnt/gentoo/etc/sudoers.d/ec2-user

# echo "/etc/sudoers.d/_sudo"
# cat <<'EOF'>/mnt/gentoo/etc/sudoers.d/_sudo
# %sudo     ALL=(ALL) ALL
# EOF
# chmod 440 /mnt/gentoo/etc/sudoers.d/_sudo

echo "/usr/src/linux/.config"
mkdir -p /mnt/gentoo/tmp
cp /tmp/.config /mnt/gentoo/tmp/.config

mkdir -p /mnt/gentoo/var/lib/portage
echo "/var/lib/portage/world"
cat <<'EOF'>/mnt/gentoo/var/lib/portage/world
app-admin/logrotate
app-admin/sudo
app-admin/syslog-ng
app-arch/unzip
app-editors/nano
app-misc/screen
app-portage/eix
app-portage/gentoolkit
dev-vcs/git
net-misc/curl
net-misc/dhcpcd
net-misc/ntp
sys-kernel/gentoo-sources
sys-process/fcron
sys-process/htop
EOF

echo "/tmp/build.sh"

cat <<'EOF'>/mnt/gentoo/tmp/build.sh
#!/bin/bash
export
env-update
source /etc/profile

emerge --sync

cp /usr/share/zoneinfo/GMT /etc/localtime

eselect profile set default/linux/amd64/13.0/no-multilib
emerge --oneshot sys-apps/portage
emerge --update --deep --with-bdeps=y --newuse @world

cd /usr/src/linux
mv /tmp/.config ./.config
yes "" | make oldconfig
make -j3 && make -j3 modules_install
cp -L arch/x86_64/boot/bzImage /boot/bzImage

groupadd sudo
useradd -r -m -s /bin/bash gentoo

ln -s /etc/init.d/net.lo /etc/init.d/net.eth0

rc-update add net.eth0 default
rc-update add syslog-ng default
rc-update add fcron default
rc-update add ntpd default

mv /etc/portage/make.conf /etc/portage/make.conf.bkup
sed "s/MAKEOPTS=\"-j.*\"/MAKEOPTS=\"-j3\"/g" /etc/portage/make.conf.bkup > /etc/portage/make.conf
rm /etc/portage/make.conf.bkup

EOF

chmod 755 /mnt/gentoo/tmp/build.sh

mount -t proc none /mnt/gentoo/proc
mount --rbind /dev /mnt/gentoo/dev
mount --rbind /dev/pts /mnt/gentoo/dev/pts

chroot /mnt/gentoo /tmp/build.sh

rm -fR /mnt/gentoo/tmp/*
rm -fR /mnt/gentoo/var/tmp/*
rm -fR /mnt/gentoo/usr/portage/distfiles/*

shutdown -h now
