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
# Networking: DHCP on eth0 by default (engine default — most VirtFusion
# providers hand the IP out over DHCP). For a STATIC address, pass a CIDR
# in VPS_IP (and a gateway in VPS_GW) at ISO-build time; gentoocd_unpack.sh
# bakes VPS_IP/VPS_GW/VPS_DNS into the CD so they survive an unattended
# install:
#   VPS_IP=203.0.113.10/24 VPS_GW=203.0.113.1 \
#     sh gentoocd_unpack.sh --preset minimal,vps
# VPS_DNS defaults to public resolvers; override with a space-separated list.

if [ -n "${VPS_IP:-}" ]; then
  : "${VPS_DNS:=1.1.1.1 8.8.8.8}"
  NETCONF="# static config baked by the vps preset (net.ifnames=0 -> eth0)
config_eth0=\"${VPS_IP}\""
  [ -n "${VPS_GW:-}" ] && NETCONF="${NETCONF}
routes_eth0=\"default via ${VPS_GW}\""
  NETCONF="${NETCONF}
dns_servers_eth0=\"${VPS_DNS}\""
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
