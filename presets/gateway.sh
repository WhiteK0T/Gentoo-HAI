# Preset: network gateway (the original Gentoo-HAI author's stack)
#   DNS (bind, chrooted), DHCP server, mail (postfix, local delivery only),
#   TFTP for PXE boot, SNMP monitoring, network scanning tools.
# Service configuration happens in gateway.chroot.sh.

PRESET_PACKAGES="${PRESET_PACKAGES} net-snmp nmap netkit-telnetd postfix bind dhcp net-ftp/tftp-hpa"
PRESET_USE="${PRESET_USE} snmp"
PRESET_PACKAGE_USE="${PRESET_PACKAGE_USE}
net-dns/bind dlz idn caps threads
net-analyzer/net-snmp lm-sensors"

# the gateway serves its LAN through a bridge: br0 over eth0
NETSVC=net.br0
NETCONF='# https://wiki.gentoo.org/wiki/Netifrc/Brctl_Migration
config_br0="dhcp"
bridge_br0="eth0"
bridge_forward_delay_br0=0
bridge_stp_state_br0=0
dhcp_br0="nodns nontp nonis nosendhost"
config_eth0="null"
rc_net_br0_need="net.eth0"

# static address example:
#config_br0="192.168.0.251/24"
#routes_br0="default via 192.168.0.254"

# VLAN example (second NIC):
#vlans_eth1="101 120"
#config_eth1_101="null"
#config_eth1_120="10.100.20.254/24"'
