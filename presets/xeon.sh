# Preset: hardware tuning for the Xeon E5450 server
#   8 GB RAM, SSD (system disk) + HDD (data disk), old NVIDIA GeForce GT
#   (nouveau). This is a hardware add-on, combine it with a package preset:
#   PRESET="minimal,xeon"  or  PRESET="gateway,xeon"

# The system goes to the SSD no matter how the BIOS enumerates the disks:
# pick the first non-removable non-rotational disk as the install target.
for d in /sys/block/sd*; do
  [ -e "$d" ] || continue
  [ "$(cat "$d/removable")" = "1" ] && continue
  [ "$(cat "$d/queue/rotational")" = "0" ] && IDEV=${IDEV:-/dev/${d##*/}}
done

# The HDD becomes the data disk: one ext4 partition labelled "data" mounted
# at /srv (samba shares, backups, VM images — see xeon.chroot.sh). A blank
# disk is partitioned and formatted; an existing filesystem labelled "data"
# is reused untouched, so the data survives system reinstalls; a disk with
# anything else on it is left alone with a warning. Override the device with
# DATADEV=/dev/sdX, disable with DATADEV=none (or datadev= on the cmdline).
DATADEV=${DATADEV:-}
for w in $(cat /proc/cmdline); do case $w in datadev=*) DATADEV=${w#datadev=};; esac; done

xeon_data_disk() {
  [ "$DATADEV" = "none" ] && echo "xeon: data disk disabled" && return 0
  if [ -z "$DATADEV" ]; then
    for d in /sys/block/sd* /sys/block/vd*; do
      [ -e "$d" ] || continue
      [ "/dev/${d##*/}" = "$IDEV" ] && continue
      [ "$(cat "$d/removable")" = "1" ] && continue
      DATADEV=/dev/${d##*/} && break
    done
  fi
  [ -z "$DATADEV" ] && echo "xeon: no second disk found, skipping /srv data disk" && return 0
  DATAP=$DATADEV
  echo $DATADEV | grep -q -e "[0-9]$" && DATAP=${DATADEV}p
  if [ "$(blkid -o value -s LABEL ${DATAP}1 2>/dev/null)" = "data" ]; then
    echo "xeon: keeping existing data filesystem on ${DATAP}1"
  elif [ -z "$(blkid ${DATADEV} ${DATAP}1 2>/dev/null)" ]; then
    echo "xeon: formatting blank disk ${DATADEV} as the data disk"
    echo -e "g\nn\n1\n\n\nw\n" | fdisk ${DATADEV} || return 1
    sleep 1
    echo y | mkfs.ext4 -L data ${DATAP}1 || return 1
  else
    echo "xeon: ${DATADEV} is not blank and not labelled 'data' — leaving it alone."
    echo "xeon: to use it: e2label <partition> data, or wipe the disk (wipefs -a) and reinstall"
    return 0
  fi
  PRESET_FSTAB="${PRESET_FSTAB}
LABEL=data		/srv		ext4		noatime		0 2"
  mkdir -p /mnt/gentoo/srv
  mount LABEL=data /mnt/gentoo/srv || return 1
}
PRESET_DISKSETUP="${PRESET_DISKSETUP} xeon_data_disk"

# a 6G build tmpfs is too risky with 8 GB RAM; heavy packages are routed
# to an on-disk tmpdir instead (see xeon.chroot.sh)
TMPFSSIZE=4G

PRESET_PACKAGES="${PRESET_PACKAGES} sys-apps/lm-sensors app-admin/sudo"

PRESET_KERNEL_EXTRA="${PRESET_KERNEL_EXTRA}
# nouveau for the old GeForce GT (console now, X/KDE later)
CONFIG_DRM_NOUVEAU=m
CONFIG_DRM_FBDEV_EMULATION=y
# Core2-era temperature sensors
CONFIG_HWMON=y
CONFIG_SENSORS_CORETEMP=m"
