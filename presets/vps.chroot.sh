#!/bin/sh
# VPS preset (runs inside the chroot): serial console for the provider's
# console, and the login user. Time sync is handled by the engine (sntp cron).
set -x

# --- serial console (VirtFusion / provider console on ttyS0) ---
# The engine only wires serial console up when the *live* cmdline carried
# console= (true for auto ISOs, not for a plain one). A VPS wants it either
# way, so enforce it here and regenerate grub.cfg. Guard against doubling up
# if the engine already did it.
if ! grep -q 'console=ttyS0' /etc/default/grub; then
  sed -i 's/ panic=30/ panic=30 console=tty0 console=ttyS0,115200/' /etc/default/grub
  sed -i 's/^GRUB_TERMINAL=.*/GRUB_TERMINAL="console serial"/' /etc/default/grub
  grep -q '^GRUB_SERIAL_COMMAND' /etc/default/grub || \
    echo 'GRUB_SERIAL_COMMAND="serial --speed=115200 --unit=0"' >> /etc/default/grub
  grub-mkconfig -o /boot/grub/grub.cfg || bash
fi
# getty on ttyS0 so the provider's serial console gets a login prompt
sed -i 's/^#s0:/s0:/' /etc/inittab

# login user (sam): wheel + sudo. Without a baked ssh key the engine sets
# PermitRootLogin no, so this user is the way in on a headless VPS.
USER_GROUPS="wheel users" . "$(dirname "$0")/adduser.inc"

exit 0
