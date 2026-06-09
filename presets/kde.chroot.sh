#!/bin/sh
# KDE preset: light Plasma desktop (runs inside the chroot)
set -x

# Plasma desktop profile (if the path changes, check: eselect profile list)
eselect profile set default/linux/amd64/23.0/desktop/plasma || bash
env-update && . /etc/profile

# pick a video driver for VMs; on real hardware combine with a hardware
# preset (e.g. xeon sets nouveau) or set VIDEO_CARDS yourself
if lspci | grep -qi 'virtio\|qxl\|vmware svga'; then
  grep -q '^VIDEO_CARDS=' /etc/portage/make.conf || echo 'VIDEO_CARDS="virtio"' >> /etc/portage/make.conf
fi

# rebuild for the new profile/USE, then the desktop itself
# (binary packages from the Gentoo binhost are used where possible)
time emerge -uvDN -j4 --keep-going y world --exclude gcc --exclude glibc || bash
etc-update --automode -5
time emerge -uv -j4 --keep-going y kde-plasma/plasma-meta kde-apps/kdecore-meta x11-misc/sddm gui-libs/display-manager-init net-misc/networkmanager || bash
etc-update --automode -5

if grep -q '^DISPLAYMANAGER=' /etc/conf.d/display-manager 2>/dev/null; then
  sed -i 's/^DISPLAYMANAGER=.*/DISPLAYMANAGER="sddm"/' /etc/conf.d/display-manager
else
  echo 'DISPLAYMANAGER="sddm"' >> /etc/conf.d/display-manager
fi

for s in dbus NetworkManager display-manager; do
  rc-update add "$s" default
done

# TODO after first boot: create your user, e.g.
#   useradd -m -G wheel,users,audio,video,usb,plugdev <name> && passwd <name>
exit 0
