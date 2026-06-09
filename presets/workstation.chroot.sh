#!/bin/sh
# Workstation preset: replicate the main system (runs inside the chroot)
set -x
D=$(dirname "$0")/workstation.d

# Plasma desktop profile (if the path changes, check: eselect profile list)
eselect profile set default/linux/amd64/23.0/desktop/plasma || bash
env-update && . /etc/profile

# portage configuration from the main system
cp -r "$D"/portage/. /etc/portage/

# make.conf extras from the main system.
# -march=native instead of the main box's skylake so the same preset
# also works on other hardware and in qemu -cpu host.
# ccache/distcc from the main system are left out on purpose (need per-host setup).
cat >> /etc/portage/make.conf << 'EOF'
COMMON_FLAGS="-march=native -O2 -pipe"
CFLAGS="${COMMON_FLAGS}"
CXXFLAGS="${COMMON_FLAGS}"
ACCEPT_LICENSE="*"
VIDEO_CARDS="nvidia"
INPUT_DEVICES="libinput"
LINGUAS="ru"
L10N="ru"
GENTOO_MIRRORS="https://gentoo-mirror.alexxy.name/ http://gentoo.bloodhost.ru/ https://mirror.yandex.ru/gentoo-distfiles/"
EOF

# rebuild for the new profile/USE and install the main system's world.
# gcc/glibc excluded for time; run a full world update later if you want them rebuilt.
time emerge -uvDN -j4 --keep-going y world $(grep -v '^#' "$D"/world) --exclude gcc --exclude glibc || bash
etc-update --automode -5

# sddm as display manager
if grep -q '^DISPLAYMANAGER=' /etc/conf.d/display-manager 2>/dev/null; then
  sed -i 's/^DISPLAYMANAGER=.*/DISPLAYMANAGER="sddm"/' /etc/conf.d/display-manager
else
  echo 'DISPLAYMANAGER="sddm"' >> /etc/conf.d/display-manager
fi

# services as on the main system: NetworkManager replaces netifrc,
# sysklogd replaces the engine's syslog-ng; distccd left out (needs per-site config)
rc-update del syslog-ng default
for s in NetworkManager chronyd dbus display-manager docker libvirtd samba sysklogd numlock; do
  rc-update add "$s" default
done

# create the user account (initial password = SET_PASS, same as root — change it!)
if [ -n "${INSTALLUSER:-}" ] && ! id "$INSTALLUSER" > /dev/null 2>&1; then
  useradd -m "$INSTALLUSER"
  # add only the groups that exist on this system
  for g in wheel users audio video usb plugdev render input docker libvirt; do
    getent group "$g" > /dev/null && usermod -aG "$g" "$INSTALLUSER"
  done
  echo "${INSTALLUSER}:${SET_PASS:-password}" | chpasswd -c BCRYPT
fi
# let wheel use sudo
[ -f /etc/sudoers ] && sed -i -e 's/^# *%wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' \
  -e 's/^# *%wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/' /etc/sudoers

exit 0
