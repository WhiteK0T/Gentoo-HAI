# Preset: workstation — replicate the main Gentoo desktop
#   KDE Plasma 6, NVIDIA + CUDA, NetworkManager, docker/libvirt/samba,
#   Java/Haskell toolchains, media stack.
# Package list and portage config come from workstation.d/ (a dump of the
# main system); the heavy lifting happens in workstation.chroot.sh.

# a desktop needs X: drop the engine's default -X
BASEUSE="iproute2 logrotate"

# global USE from the main system's make.conf
PRESET_USE="${PRESET_USE} -gtk -gnome qt6 dbus rdp ssl networkmanager lm_sensors libinput wifi kde plasma nvenc opengl opencl cuda pipewire screencast java javascript python pdf djvu epub lto pgo graphite x265 vpx ogg opus flac webp matroska jpeg tiff svg png heif exif"

# NetworkManager replaces netifrc (configured in the chroot hook)
NETSVC=""
