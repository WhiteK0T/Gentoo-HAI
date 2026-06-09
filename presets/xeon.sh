# Preset: hardware tuning for the Xeon E5450 server
#   8 GB RAM, SSD (system disk) + HDD, old NVIDIA GeForce GT (nouveau).
# This is a hardware add-on, combine it with a package preset:
#   PRESET="minimal,xeon"  or  PRESET="gateway,xeon"
#
# Note: the second disk (HDD) is left untouched by the installer;
# partition and mount it manually after the first boot.

# a 6G build tmpfs is too risky with 8 GB RAM; heavy packages are routed
# to an on-disk tmpdir instead (see xeon.chroot.sh)
TMPFSSIZE=4G

PRESET_PACKAGES="${PRESET_PACKAGES} sys-apps/lm-sensors"

PRESET_KERNEL_EXTRA="${PRESET_KERNEL_EXTRA}
# nouveau for the old GeForce GT (console now, X/KDE later)
CONFIG_DRM_NOUVEAU=m
CONFIG_DRM_FBDEV_EMULATION=y
# Core2-era temperature sensors
CONFIG_HWMON=y
CONFIG_SENSORS_CORETEMP=m"
