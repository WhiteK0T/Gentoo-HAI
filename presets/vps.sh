# Preset: KVM VPS (VirtFusion / libvirt-style provider)
#
#   Tuned for a virtio KVM guest on an AMD host with nested virtualization
#   (e.g. Ryzen 9 7950X3D, 16 GB RAM, single NVMe/virtio system disk).
#   Headless, remote-only: access over ssh, recovery over the provider's
#   serial/VNC console. This is a role add-on — combine with the base:
#       PRESET="minimal,vps"
#
#   The system disk is auto-detected by the engine (nvme0n1 -> vda -> sda),
#   so it works whether the provider exposes the 200 GB as virtio-blk,
#   virtio-scsi or emulated NVMe. Nothing to set here for the disk.
#
# Networking: DHCP on eth0 by default (engine default — many VirtFusion
# providers hand the IP out over DHCP). For a STATIC address, pass a CIDR in
# VPS_IP (plus VPS_GW / VPS_DNS / VPS_MTU) at ISO-build time; gentoocd_unpack.sh
# bakes them into the CD so they survive an unattended install:
#   VPS_IP=89.106.89.196/28 VPS_GW=11.0.0.1 VPS_DNS="1.1.1.1 1.0.0.1" \
#     VPS_MTU=1448  sh gentoocd_unpack.sh --preset minimal,vps
#
# Three gotchas seen on real DDoS-scrubbed VirtFusion hosts, all handled here:
#   * off-link gateway — the gateway (e.g. 11.0.0.1) is NOT inside the IP's
#     subnet. A plain "default via GW" fails ("nexthop has invalid gateway");
#     the 'onlink' flag tells the kernel the gateway is reachable on the link.
#   * reduced MTU — traffic is tunnelled, so the real MTU is <1500 (often
#     1448/1400). With 1500, small packets pass but large ones (stage3 fetch,
#     TLS) black-hole and the install hangs. Set VPS_MTU to the provider's MTU.
#   * static-only — the LIVE installer itself has no DHCP here, so the block
#     below also brings the installer's own NIC up statically *before* any
#     download, otherwise the unattended install stalls fetching stage3.
# VPS_DNS defaults to Cloudflare; override with a space-separated list.

if [ -n "${VPS_IP:-}" ]; then
  : "${VPS_DNS:=1.1.1.1 1.0.0.1}"

  # --- config for the INSTALLED system (/etc/conf.d/net, netifrc) ---
  NETCONF="# static config baked by the vps preset (net.ifnames=0 -> eth0)
config_eth0=\"${VPS_IP}\""
  # onlink: gateway may sit outside the subnet on scrubbed/tunnelled providers
  [ -n "${VPS_GW:-}" ] && NETCONF="${NETCONF}
routes_eth0=\"default via ${VPS_GW} onlink\""
  NETCONF="${NETCONF}
dns_servers_eth0=\"${VPS_DNS}\""
  [ -n "${VPS_MTU:-}" ] && NETCONF="${NETCONF}
mtu_eth0=\"${VPS_MTU}\""

  # --- bring the LIVE installer NIC up now, before the engine downloads
  # stage3/portage. Skip if something already gave us a default route (e.g.
  # DHCP worked). net.ifnames=0 on the live cmdline -> the NIC is eth0, but
  # detect it anyway and fall back to eth0. This runs on the LiveCD only
  # (*.sh is sourced pre-chroot); the .chroot.sh hook handles the rest.
  if ! ip route 2>/dev/null | grep -q '^default'; then
    _ifc=$(ip -o link 2>/dev/null | awk -F': ' '$2!="lo"{sub(/@.*/,"",$2); print $2; exit}')
    _ifc=${_ifc:-eth0}
    echo "vps: no default route — configuring ${_ifc} statically for the installer"
    ip addr add "${VPS_IP}" dev "$_ifc" 2>/dev/null
    [ -n "${VPS_MTU:-}" ] && ip link set "$_ifc" mtu "${VPS_MTU}"
    ip link set "$_ifc" up
    [ -n "${VPS_GW:-}" ] && ip route replace default via "${VPS_GW}" dev "$_ifc" onlink
    : > /etc/resolv.conf
    for _ns in ${VPS_DNS}; do echo "nameserver $_ns" >> /etc/resolv.conf; done
    ip route
  fi
fi

# sudo for the login user (see vps.chroot.sh)
PRESET_PACKAGES="${PRESET_PACKAGES} app-admin/sudo"

# Nested virtualization: KVM host on an AMD cpu (KVM_INTEL kept as a module
# so the same image also boots on an Intel host — it just won't load on AMD),
# plus vhost/tun for the guest VMs' networking. The qemu/libvirt userland is
# left out on purpose (hours of build); the kernel is ready, emerge them when
# needed:  emerge app-emulation/qemu app-emulation/libvirt
#
# The second block pins the virtio guest transport explicitly. The engine
# defconfig usually has it, but on a KVM VPS a missing VIRTIO_PCI means no
# disk and no network, i.e. an unbootable box — so be explicit.
PRESET_KERNEL_EXTRA="${PRESET_KERNEL_EXTRA}
# --- KVM host (nested virtualization) ---
CONFIG_KVM=y
CONFIG_KVM_AMD=m
CONFIG_KVM_INTEL=m
CONFIG_VHOST=m
CONFIG_VHOST_NET=m
CONFIG_TUN=m
CONFIG_BRIDGE=m
# --- virtio guest transport (belt-and-suspenders for a KVM VPS) ---
CONFIG_PCI=y
CONFIG_VIRTIO_PCI=y
CONFIG_VIRTIO_PCI_LEGACY=y
CONFIG_VIRTIO_BALLOON=y
CONFIG_VIRTIO_CONSOLE=y
CONFIG_SCSI_VIRTIO=y
CONFIG_HW_RANDOM_VIRTIO=y
CONFIG_VIRTIO_NET=y
CONFIG_VIRTIO_BLK=y"
