#!/bin/sh
# Gateway preset: configure services inside the chroot (runs after the main emerge)
set -x

# bind (DNS) in chroot
sed -i 's/^#CHROOT=/CHROOT=/' /etc/conf.d/named
emerge --config net-dns/bind
rc-update add named default

# dhcpd in chroot; it will not start until subnets are configured:
# edit /etc/dhcp/dhcpd.conf on the installed system, then: rc-update add dhcpd default
sed -i 's/^# DHCPD_CHROOT=/DHCPD_CHROOT=/' /etc/conf.d/dhcpd

# TFTP for PXE boot
mkdir -p /tftproot
sed -i 's#^\#INTFTPD_PATH="/tftproot/"#INTFTPD_PATH="/tftproot/"#' /etc/conf.d/in.tftpd
rc-update add in.tftpd default

# postfix: local delivery only (network smtp listener disabled)
sed -i 's/^smtp.*inet/#&/' /etc/postfix/master.cf
printf '# Use newaliases after change\nroot:\t\t%s\n' "${ROOTEMAIL:-root}" >> /etc/mail/aliases
newaliases
rc-update add postfix default

exit 0
