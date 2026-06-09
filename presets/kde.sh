# Preset: kde — light Plasma GUI add-on (for QEMU VMs and quick desktops)
#   Plasma desktop + sddm + NetworkManager, nothing else.
# Combine with others: PRESET="minimal,kde" or PRESET="minimal,xeon,kde"
# (kde last, so its profile/USE win). For the full main-system replica
# use the workstation preset instead.

# a desktop needs X: drop the engine's default -X
BASEUSE="iproute2 logrotate"

PRESET_USE="${PRESET_USE} kde plasma qt6 dbus networkmanager pipewire libinput"

# NetworkManager replaces netifrc (configured in the chroot hook)
NETSVC=""
