# Preset: minimal server (default)
#
# The engine base already installs everything a minimal server needs:
#   sshd (PermitRootLogin no), cron, syslog-ng, logrotate, smartmontools,
#   iotop/iftop/tcpdump, mc, watchdog, dhcpcd, iptables/nftables, git.
# Network: plain DHCP on eth0 (engine default).
#
# This file intentionally adds nothing — it exists so that PRESET=minimal
# is explicit and so it can serve as a template for new presets.
#
# Available variables (append, do not overwrite):
#   PRESET_PACKAGES     - extra packages for the main emerge
#   PRESET_USE          - extra global USE flags for make.conf
#   PRESET_PACKAGE_USE  - lines for /etc/portage/package.use/preset
#   PRESET_KERNEL_EXTRA - lines appended to the kernel .config
#   TMPFSSIZE           - size of the /var/tmp build tmpfs
#   NETCONF             - full content of /etc/conf.d/net
#   NETSVC              - the net.* service added to the default runlevel
# Optional: presets/<name>.chroot.sh runs inside the chroot after the
# main emerge (service configuration etc.).
