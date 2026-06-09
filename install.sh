#!/bin/bash
# Copyleft Christian Nilsson
# Please do what you want! Use on your own risk and all that!
#
# This script partitions ${IDEV}, creates filesystem and installs gentoo.
# Everything is done including the first reboot (just before reboot it will stop and let you edit the network configuration)
#
# root password will be set to SET_PASS parameter or "password" if not given
# ssh server will be started on the live medium directly after the password have been set.
#
# Hostname will be set to the same as the host
# Keyboard layout, timezone and ntp server see settings below
#

# Make sure our root mountpoint exists
mkdir -p /mnt/gentoo

TIMEZONE=${TIMEZONE:-Europe/Moscow}
NTPSERVER=${NTPSERVER:-ru.pool.ntp.org}
KEYMAP=${KEYMAP:-ru}
ROOTEMAIL=${ROOTEMAIL:-uyiraqoyir041@gmail.com}
# size of the tmpfs mounted on /var/tmp (build space); reduce on low-RAM machines
TMPFSSIZE=${TMPFSSIZE:-6G}

# ---- Preset loading --------------------------------------------------------
# Select with PRESET env var or preset= on the kernel cmdline.
# Combine several with commas: PRESET="gateway,xeon" sh install.sh
PRESET=${PRESET:-}
for w in $(cat /proc/cmdline); do case $w in preset=*) PRESET=${w#preset=};; esac; done
PRESET=${PRESET:-minimal}
PRESET=${PRESET//,/ }

# interface filled in by preset files (presets/<name>.sh)
PRESET_PACKAGES=""
PRESET_USE=""
PRESET_PACKAGE_USE=""
PRESET_KERNEL_EXTRA=""
PRESET_HOOKS=""
BASEUSE="-X iproute2 logrotate"
NETSVC=net.eth0
NETCONF='# Simple DHCP on eth0 (net.ifnames=0 is set on the kernel cmdline)
config_eth0="dhcp"'

SCRIPTDIR=$(cd "$(dirname "$0")" && pwd)
PRESETDIR=
for d in "$SCRIPTDIR/presets" ./presets /mnt/cdrom/presets /run/initramfs/live/presets; do
  [ -d "$d" ] && PRESETDIR=$d && break
done
for p in $PRESET; do
  if [ -n "$PRESETDIR" ] && [ -f "$PRESETDIR/$p.sh" ]; then
    echo "Loading preset: $p"
    . "$PRESETDIR/$p.sh"
    [ -f "$PRESETDIR/$p.chroot.sh" ] && PRESET_HOOKS="$PRESET_HOOKS $PRESETDIR/$p.chroot.sh"
  elif [ "$p" == "minimal" ]; then
    echo "No presets dir found, continuing with built-in minimal defaults"
  else
    echo "ERROR: preset '$p' not found (looked in '${PRESETDIR:-<no presets dir>}')"
    exit 1
  fi
done

# ---- SSH key baking ---------------------------------------------------------
# Provide a public key via SSHKEY (key string or path to a .pub file) or put
# an authorized_keys file next to install.sh / on the cd. With a baked key,
# ssh becomes key-only: PermitRootLogin prohibit-password and password
# authentication off (console password login still works); keep password
# authentication for ordinary users with SSHPASSAUTH=yes.
# Without a key: password logins, root over ssh disabled (as before).
SSHKEY=${SSHKEY:-}
SSHPASSAUTH=${SSHPASSAUTH:-no}
[ -n "$SSHKEY" ] && [ -f "$SSHKEY" ] && SSHKEY=$(cat "$SSHKEY")
if [ -z "$SSHKEY" ]; then
  for f in "$SCRIPTDIR/authorized_keys" ./authorized_keys /mnt/cdrom/authorized_keys /run/initramfs/live/authorized_keys; do
    [ -f "$f" ] && SSHKEY=$(cat "$f") && break
  done
fi
[ -n "$SSHKEY" ] && echo "Will bake ssh authorized_keys ($(echo "$SSHKEY" | wc -l) line(s)) for root and /etc/skel"
# -----------------------------------------------------------------------------

if [ -b /dev/nvme0n1 ]; then
  IDEV=${IDEV:-/dev/nvme0n1}
  NVMETOOLS=sys-apps/nvme-cli
  NVMEKERNEL=CONFIG_BLK_DEV_NVME=y
fi
[[ -b /dev/vda ]] && [[ ! -b /dev/sda ]] && IDEV=${IDEV:-/dev/vda}

IDEV=${IDEV:-/dev/sda}
IDEVP=${IDEV}
# if disk name ends with number, then partition is sepparated with p
echo ${IDEV} | grep -q -e "[0-9]$" && IDEVP=${IDEV}p

# Decide the hostname of the installed system. Order: INSTALL_HOSTNAME env,
# hostname= on the kernel cmdline, the current livecd hostname (if changed from
# the default), or gtestinst when auto-installing. We capture it in a variable
# because NetworkManager on the livecd keeps resetting the live hostname back to
# "livecd", so $(hostname) is unreliable later when we write conf.d/hostname.
INSTALL_HOSTNAME=${INSTALL_HOSTNAME:-}
for w in $(cat /proc/cmdline); do case $w in hostname=*) INSTALL_HOSTNAME=${w#hostname=};; esac; done
if [ -z "$INSTALL_HOSTNAME" ]; then
  if [ "$(hostname)" != "livecd" ]; then
    INSTALL_HOSTNAME=$(hostname)
  elif grep -q autoinstall /proc/cmdline; then
    INSTALL_HOSTNAME=gtestinst
  else
    echo Change hostname before you continue since it will be used for the created host.
    echo "Or set it explicitly: INSTALL_HOSTNAME=myhost sh install.sh"
    exit 1
  fi
fi
hostname "$INSTALL_HOSTNAME"
#IF NOT SET_PASS is set then the password will be "password"
SET_PASS=${SET_PASS:-password}
# user account auto-created by the desktop presets (workstation/kde)
INSTALLUSER=${INSTALLUSER:-sam}

set -x -u
GHBASEURL="https://raw.githubusercontent.com/ASoft-se/Gentoo-HAI/refs/heads/master"
# Try to update to a correct system time
touch /var/db/ntp-kod
sntp -S $NTPSERVER &
pid_ntp=$!

[ -d /sys/firmware/efi ] && PLATFORM=efi || PLATFORM=pcbios

# (upstream used a pipe to while which lost the variable in a subshell)
APCUPSDTOOLS=""
for f in $(find /sys/devices/ -name "idVendor" -exec grep -l "051d" {} + 2>/dev/null); do
    echo we have an APC device, probably UPS add apcupsd
    cat "$(dirname "$f")/manufacturer" "$(dirname "$f")/product"
    APCUPSDTOOLS=apcupsd
done

BATTERYDEV=$(grep -l "Battery" /sys/class/power_supply/*/type)
if [[ ! -z "${BATTERYDEV:=}" ]]; then
    BATTERYTOOLS=sys-power/acpi
fi

#Create bios boot, 128MB boot, 128MB EFI, 4GB Swap and the rest root on ${IDEV}
echo "gpt
print
new
99

+2M
type
21686148-6449-6E6F-744E-656564454649
xpert
A
return
new
1

+128M
new
2

+128M
type
2
uefi
new
3

+4G
type
3
swap
new
4


type
4
4F68BCE3-E8CD-4DB1-96E7-FBCAF984B709
xpert
name
1
/boot
name
2
/boot/efi
name
3
swap0
name
4
/
name
99
GRUB BIOS Data
return
print
write
" | fdisk ${IDEV} || exit 1
sfdisk -d ${IDEV}
file -s ${IDEV}
# Wait a bit for the dust to settle on the new devices
sleep 1

#we should detect and use md if we multiple disks with same size...
#sfdisk -d ${IDEV} | sfdisk --force /dev/sdb || exit 1
#for a in /dev/md*; do mdadm -S $a; done

#mdadm --help
#mdadm -C --help

#mdadm -Cv /dev/md1 -l1 -n2 /dev/sd[ab]1 --metadata=0.90 || exit 1
#mdadm -Cv /dev/md3 -l1 -n2 /dev/sd[ab]3 --metadata=0.90 || exit 1
#mdadm -Cv /dev/md4 -l4 -n3 /dev/sd[ab]4 missing --metadata=0.90 || exit 1

mkswap -L swap0 ${IDEVP}3 || exit 1
swapon -p1 ${IDEVP}3 || exit 1
echo y | mkfs.ext2 ${IDEVP}1 || exit 1
mkfs.vfat ${IDEVP}2 || exit 1
echo y | mkfs.ext4 ${IDEVP}4 || exit 1

mount ${IDEVP}4 /mnt/gentoo -o discard,noatime || exit 1
mkdir -p /mnt/gentoo/boot || exit 1
mount ${IDEVP}1 /mnt/gentoo/boot || exit 1
mkdir -p /mnt/gentoo/boot/efi || exit 1
mount ${IDEVP}2 /mnt/gentoo/boot/efi || exit 1

# wait to make sure sntp is done
wait $pid_ntp
[ -f portagehelper.sh ] && cp portagehelper.sh /mnt/gentoo
cd /mnt/gentoo || exit 1
#cleanup in case of previous try...
rm -f stage3-*.tar.bz2 stage3-*.tar.xz 2>/dev/null
[ -f portagehelper.sh ] || curl -L --remote-name-all ${GHBASEURL}/portagehelper.sh -O
sha512sum -c <<<"fc4727ec899d46b53637917bf6fe69d51645d28d1fd2cd10bd989aa0787af8fc236bcc517d83e0ee575a15f70a641c597000cf53fc25039e3caec9690848c152  portagehelper.sh" || bash
. ./portagehelper.sh || bash
DISTBASE=${DISTMIRROR}/releases/amd64/autobuilds/current-stage3-amd64-openrc/
ensure_key_and_snap_source || bash

mkdir -p $pathrepo
mkdir -p $pathsnapshots
update_snapshot &

FILE=$(curl -q $DISTBASE --output - | grep -o -E 'stage3-amd64-openrc-\w*\.tar\.xz' | sort -r | head -1)
[ -z "$FILE" ] && echo -e "\e[91mNo stage3 found on $DISTBASE\e[0m" && exit 1
echo -e "\e[93mdownload latest stage file $FILE\e[0m"
curl -L -C - --remote-name-all --parallel-immediate --parallel \
  $DISTBASE$FILE $DISTBASE$FILE.DIGESTS $DISTBASE$FILE.asc || bash

gpg --output $FILE.DIGESTS.verified --verify $FILE.DIGESTS && rm $FILE.DIGESTS
gpg --verify $FILE.asc || bash
echo "Verifying stage3 SHA512 ..."
# grab SHA512 lines and line after, then filter out line that ends with iso
echo "$(grep -A1 SHA512 $FILE.DIGESTS.verified | grep $FILE\$)" | sha512sum -c || bash
echo -e "- \e[92mAwesome!\e[0m stage3 verification looks good."
rm $FILE.DIGESTS.verified
rm $FILE.asc
time tar xpf $FILE --xattrs-include='*.*' --numeric-owner && rm $FILE

wait || exit 1
mkdir root/.gnupg; chmod 700 root/.gnupg; cp ~/.gnupg/trustdb.gpg root/.gnupg/
mount_current_snapshot || bash
cp /etc/resolv.conf etc
# make sure we are done with root unpack...

echo "# Set to the hostname of this machine
hostname=\"${INSTALL_HOSTNAME}\"
" > etc/conf.d/hostname
#change fstab to match disk layout
echo -e "
${IDEVP}1		/boot		ext2		noauto,noatime	1 2
${IDEVP}2		/boot/efi		vfat		noauto,noatime	1 2
${IDEVP}4		/		ext4		discard,noatime	0 1
LABEL=swap0		none		swap		sw		0 0

none			/var/tmp	tmpfs		size=${TMPFSSIZE},nr_inodes=1M 0 0
" >> etc/fstab
sed -i '/\/dev\/BOOT.*/d' etc/fstab
sed -i '/\/dev\/ROOT.*/d' etc/fstab
sed -i '/\/dev\/SWAP.*/d' etc/fstab
mount --types proc /proc proc
for p in sys dev; do mount --rbind /$p $p; mount --make-rslave $p; done  || exit 1
for p in run; do mount --bind /$p $p; mount --make-slave $p; done  || exit 1

MAKECONF=etc/portage/make.conf
[ ! -f $MAKECONF ] && [ -f etc/make.conf ] && MAKECONF=etc/make.conf
echo $MAKECONF

# CPU_FLAGS_X86 should be handled but must be done inside chroot, see below

#Updating Makefile
echo >> $MAKECONF
echo "# add valid -march= to CFLAGS" >> $MAKECONF
echo "MAKEOPTS=\"-j$(nproc)\"" >> $MAKECONF
echo "EMERGE_DEFAULT_OPTS=\"\${EMERGE_DEFAULT_OPTS} --getbinpkg --jobs-tmpdir-require-free-gb=1\"" >> $MAKECONF
echo "FEATURES=\"parallel-fetch buildpkg\"" >> $MAKECONF
echo "USE=\"\${USE} ${BASEUSE} ${PRESET_USE}\"" >> $MAKECONF

grep -q autoinstall /proc/cmdline || nano $MAKECONF

echo "keymap=\"$KEYMAP\"" >> etc/conf.d/keymaps

echo "rc_logger=\"YES\"" >> etc/rc.conf
echo "rc_sys=\"\"" >> etc/rc.conf

# network config comes from the active preset (default: plain DHCP on eth0)
echo "${NETCONF}" > etc/conf.d/net
grep -q autoinstall /proc/cmdline || nano etc/conf.d/net

#generate chroot script
cat > chrootstart.sh << EOF
#!/bin/bash
env-update
source /etc/profile
echo "root:${SET_PASS}" | chpasswd -c BCRYPT
set -x
mount /var/tmp

vardb=/var/db
. ./portagehelper.sh || bash
ensure_snapshot_fstab
time getuto & > /dev/null

# fix for new mtab init
ln -snf /proc/self/mounts /etc/mtab

[ -d /etc/portage/repos.conf ] || mkdir -p /etc/portage/repos.conf
[ -d /etc/portage/package.accept_keywords ] || mkdir -p /etc/portage/package.accept_keywords
[ -d /etc/portage/package.use ] || mkdir -p /etc/portage/package.use
[ -d /etc/portage/package.mask ] || mkdir -p /etc/portage/package.mask

mkdir -p /etc/portage/package.accept_keywords
mkdir -p /etc/portage/package.use
grep -q gentoo-sources /etc/portage/package.accept_keywords/* || echo sys-kernel/gentoo-sources > /etc/portage/package.accept_keywords/kernel &
# package.use entries provided by the active presets
echo "${PRESET_PACKAGE_USE}" > /etc/portage/package.use/preset
echo touch to disable the unpredictable "PredictableNetworkInterfaceNames"
mkdir -p /etc/udev/rules.d/
touch /etc/udev/rules.d/80-net-name-slot.rules &
touch /etc/udev/rules.d/80-net-setup-link.rules &
wait
time USE=-snmp emerge -uvN1 -j8 --keep-going y portage curl ntp gentoolkit cpuid2cpuflags || bash
touch /var/db/ntp-kod
sntp -S $NTPSERVER
if [[ ! -z "${APCUPSDTOOLS:=}" ]]; then
    #snmp support in current apcupsd is buggy
    grep -q sys-power/apcupsd /etc/portage/package.use/* || echo sys-power/apcupsd -snmp >> /etc/portage/package.use/apcupsd
    # apcupsd requires wall which is included in util-linux iif tty-helpers is set
    grep -q sys-apps/util-linux /etc/portage/package.use/* || echo sys-apps/util-linux tty-helpers >> /etc/portage/package.use/apcupsd
fi
grep -q net-firewall/nftables /etc/portage/package.use/* || echo net-firewall/nftables xtables >> /etc/portage/package.use/nftables
grep -q sys-kernel/installkernel /etc/portage/package.use/* || echo sys-kernel/installkernel grub >> /etc/portage/package.use/grub
[[ ! -z "${NVMETOOLS:=}" ]] && (grep -q nvme /etc/portage/package.accept_keywords/* || echo ${NVMETOOLS} > /etc/portage/package.accept_keywords/nvme) &

#add new CPU_FLAGS_X86
echo "*/* \$(cpuid2cpuflags)" > /etc/portage/package.use/00cpuflags
# prefetch some packages
emerge -fq pciutils gentoo-sources > /dev/null &

#start out with being up2date
#we expect that this can fail
time emerge -uvDN -j4 --keep-going y world --exclude gcc glibc
etc-update --automode -5

[ -f /etc/portage/package.mask/gentoo.conf ] || cp /usr/share/portage/config/repos.conf /etc/portage/repos.conf/gentoo.conf

wait
time emerge -uv -j8 app-arch/lz4 sys-kernel/installkernel dosfstools gentoo-sources pciutils usbutils ntp iproute2 sys-apps/memtest86+ ${NVMETOOLS} || bash
lspci

eselect kernel set 1
cd /usr/src/linux
#getting a base kernel config
wget ${GHBASEURL}/krn330.conf -O .config
echo "
# Gentoo Linux
CONFIG_GENTOO_LINUX=y
CONFIG_GENTOO_LINUX_UDEV=y
CONFIG_GENTOO_LINUX_INIT_SCRIPT=y
CONFIG_SQUASHFS=m
CONFIG_SQUASHFS_XZ=y

CONFIG_TRACEPOINTS=y
CONFIG_FTRACE=y
CONFIG_BLK_DEV_IO_TRACE=y
CONFIG_TRACING=y

# Modern USB
CONFIG_USB_XHCI_HCD=y
CONFIG_USB_XHCI_SIDEBAND=y
CONFIG_USB_OHCI_HCD=m
CONFIG_USBIP_CORE=m
CONFIG_USBIP_VHCI_HCD=m
CONFIG_USBIP_HOST=m
CONFIG_USB_ACM=m
CONFIG_USB_SERIAL=m
CONFIG_USB_SERIAL_GENERIC=y
CONFIG_USB_SERIAL_SIMPLE=m
CONFIG_USB_SERIAL_CP210X=m
CONFIG_USB_SERIAL_FTDI_SIO=m
CONFIG_USB_SERIAL_OPTION=m

#Mouse modules
CONFIG_INPUT_MOUSEDEV=m
CONFIG_MOUSE_PS2=m
CONFIG_MOUSE_SYNAPTICS_I2C=m
CONFIG_MOUSE_SYNAPTICS_USB=m
CONFIG_HID_RMI=m
CONFIG_RMI4_CORE=m
CONFIG_RMI4_I2C=m
CONFIG_RMI4_SPI=m
CONFIG_RMI4_SMB=m
CONFIG_RMI4_F03=y
CONFIG_RMI4_F03_SERIO=m
CONFIG_RMI4_2D_SENSOR=y
CONFIG_RMI4_F11=y
CONFIG_RMI4_F12=y
CONFIG_RMI4_F1A=y
CONFIG_RMI4_F21=y
CONFIG_RMI4_F30=y
CONFIG_RMI4_F34=y
CONFIG_RMI4_F3A=y
CONFIG_RMI4_F55=y

#fix hotplug (vmware)
CONFIG_HOTPLUG_PCI_SHPC=y
#no use for sound in virtual machine
CONFIG_SOUND=n
#scsi support vmware but also intel sas card
CONFIG_FUSION=y
#CONFIG_FUSION_SPI=y
#CONFIG_FUSION_FC=y
#CONFIG_FUSION_SAS=y
CONFIG_FUSION_CTL=m
#vmware -only- scsi
#CONFIG_VMWARE_PVSCSI=y
#CONFIG_SCSI_BUSLOGIC=y
#CONFIG_SCSI_SYM53C8XX_2=y
#CONFIG_I2C_PIIX4=y
CONFIG_SCSI_DH=y
CONFIG_FSCACHE=y
#vmware ensure network
CONFIG_VMXNET3=m
CONFIG_NET_VENDOR_AMD=y
CONFIG_PCNET32=m
CONFIG_NET_VENDOR_INTEL=y
CONFIG_E1000=m
CONFIG_E1000E=y
CONFIG_IGB=m
CONFIG_IGBVF=m
CONFIG_NLMON=y
CONFIG_R8169=m
#KVM/XEN Virtio
CONFIG_VIRTIO=y
CONFIG_VIRTIO_BLK=y
CONFIG_VIRTIO_BLK_SCSI=y
CONFIG_VIRTIO_NET=y
CONFIG_VIRTIO_INPUT=y
CONFIG_VIRTIO_MMIO=m
#ups support...
CONFIG_HIDRAW=y
#iotop stuff
CONFIG_TASK_IO_ACCOUNTING=y
CONFIG_TASK_DELAY_ACCT=y
CONFIG_TASKSTATS=y
CONFIG_VM_EVENT_COUNTERS=y
#qemu kvm_stat need
CONFIG_DEBUG_FS=y

CONFIG_HYPERVISOR_GUEST=y
CONFIG_PARAVIRT=y
CONFIG_PARAVIRT_SPINLOCKS=y
CONFIG_KVM_GUEST=y
CONFIG_PARAVIRT_TIME_ACCOUNTING=y
CONFIG_VIRTIO_RTC=y

# optimize kernel compression for speed
CONFIG_X86_NATIVE_CPU=y
# unset GZIP
CONFIG_KERNEL_GZIP=n
CONFIG_KERNEL_LZ4=y
CONFIG_DMI_SYSFS=m
CONFIG_SOFT_WATCHDOG=m
CONFIG_IT87_WDT=m
CONFIG_INTEL_OC_WATCHDOG=m
CONFIG_INTEL_MEI_WDT=m
CONFIG_IPMI_SI=m
CONFIG_IPMI_SSIF=m
CONFIG_IPMI_WATCHDOG=m
CONFIG_IPMI_POWEROFF=m
CONFIG_IPMI_HANDLER=m
CONFIG_TCG_TPM=m
CONFIG_NFS_FS=m
CONFIG_NFSD=m
CONFIG_SMB_SERVER=m
CONFIG_FW_LOADER_COMPRESS=y
CONFIG_FW_LOADER_COMPRESS_XZ=y
CONFIG_EFI_CAPSULE_LOADER=m

# use old vesa, vga= mode
CONFIG_FB_VESA=y
# and make uvesafb a module instead
CONFIG_FB_UVESA=m

# make sure the kernel supports EFI boot
CONFIG_EFI_STUB=y
CONFIG_FB_EFI=y
CONFIG_SYSFB_SIMPLEFB=y
CONFIG_DRM=y
CONFIG_DRM_SIMPLEDRM=y
CONFIG_FB_SIMPLE=y
CONFIG_FB_FOREIGN_ENDIAN=y
CONFIG_FB_TILEBLITTING=y
# DEFERRED_TAKEOVER hides penguins
#CONFIG_FRAMEBUFFER_CONSOLE_DEFERRED_TAKEOVER=y
CONFIG_EFI_BOOTLOADER_CONTROL=m
CONFIG_EFI_RCI2_TABLE=y

# New Netfilter (to get iptables nat working)
CONFIG_NF_TABLES=m
CONFIG_NFT_MASQ=m
CONFIG_NFT_REDIR=m
CONFIG_NFT_NAT=m
CONFIG_NFT_COMPAT=m
CONFIG_NETFILTER_XT_NAT=m
CONFIG_NETFILTER_XT_TARGET_REDIRECT=m
CONFIG_NF_TABLES_IPV4=y
CONFIG_NFT_CHAIN_ROUTE_IPV4=m
CONFIG_NF_NAT_IPV4=m
CONFIG_NFT_CHAIN_NAT_IPV4=m
CONFIG_NF_NAT_MASQUERADE_IPV4=m
CONFIG_NFT_MASQ_IPV4=m
CONFIG_NFT_REDIR_IPV4=m
CONFIG_IP_NF_NAT=m
CONFIG_IP_NF_TARGET_MASQUERADE=m
CONFIG_IP_NF_TARGET_REDIRECT=m
CONFIG_NF_TABLES_IPV6=y
CONFIG_NFT_CHAIN_ROUTE_IPV6=m
CONFIG_IPV6_SIT=m
CONFIG_NF_CT_NETLINK_HELPER=m
CONFIG_NF_CT_NETLINK_TIMEOUT=m

CONFIG_IPV6_OPTIMISTIC_DAD=y
CONFIG_IPV6_TUNNEL=m
CONFIG_BONDING=m
CONFIG_WIREGUARD=m
CONFIG_OVPN=m
CONFIG_MACVLAN=m
CONFIG_IPVLAN=m
CONFIG_VXLAN=m
CONFIG_TUN=m
CONFIG_VETH=m
CONFIG_VLAN_8021Q=m

CONFIG_NET_SCH_QFQ=m
CONFIG_NET_SCH_CODEL=m
CONFIG_NET_SCH_FQ_CODEL=m

# if we have nvme hardware
${NVMEKERNEL:-}

# preset kernel extras
${PRESET_KERNEL_EXTRA}

# Serial console
CONFIG_SERIAL_8250=y
CONFIG_SERIAL_8250_CONSOLE=y
CONFIG_SERIAL_8250_DEPRECATED_OPTIONS=n

# Include some stuff to simplify for iwd
CONFIG_RFKILL=m
CONFIG_ASYMMETRIC_KEY_TYPE=y
CONFIG_ASYMMETRIC_PUBLIC_KEY_SUBTYPE=y
CONFIG_KEY_DH_OPERATIONS=y
CONFIG_PKCS7_MESSAGE_PARSER=y
CONFIG_PKCS8_PRIVATE_KEY_PARSER=y
CONFIG_X509_CERTIFICATE_PARSER=y
CONFIG_CRYPTO_USER_API_HASH=y
CONFIG_CRYPTO_USER_API_SKCIPHER=y
CONFIG_CRYPTO_RSA=y
CONFIG_CRYPTO_DES3_EDE_X86_64=y
CONFIG_CRYPTO_SHA1_SSSE3=y
CONFIG_CRYPTO_SHA256_SSSE3=y
CONFIG_CRYPTO_SHA512_SSSE3=y

# XATTR and ACL enable
CONFIG_EXT2_FS_XATTR=y
CONFIG_EXT4_FS_POSIX_ACL=y
CONFIG_EXT4_FS_SECURITY=y
CONFIG_TMPFS_POSIX_ACL=y
" >> .config

DISK_COUNT=\$(readlink -f /sys/block/[sv]d* 2>/dev/null | grep -v "usb" | wc -l)
if [ "\$DISK_COUNT" -le 1 ]; then
    echo "Single disk detected. change MD/RAID to modules"
    sed -i 's/CONFIG_BLK_DEV_MD=./CONFIG_BLK_DEV_MD=m/' .config
    sed -i '/^CONFIG_MD_RAID/s/=./=m/' .config
fi

# Remove old low CPU core count
sed -i "/^CONFIG_NR_CPUS=.*$/d" .config

# v86d is dead so remove its initramfs
sed -i 's#/usr/share/v86d/initramfs##' .config

# Add missing PCI config options
SEARCH_PATHS="/usr/src/linux/drivers/ /usr/src/linux/arch/x86/"
for drv in \$(lspci -k | grep -E "Kernel (driver in use|modules):" | sed 's/.*: //' | tr '_,[:upper:]' '-\n[:lower:]' | sort -u); do
    SYMBOL=\$(find /usr/src/linux/ -name "Makefile" -exec grep "[[:space:]]+=[[:space:]]*\${drv/-/.}\.o" {} \; | sed -n 's/.*\(CONFIG_[A-Z0-9_]*\).*/\1/p')

    # Search for the DRV_NAME string in .c files
    if [ -z "\$SYMBOL" ]; then
        SRC_FILE=\$(grep -rlE "(\.name[[:space:]]*=[[:space:]]*\"|#define DRV_NAME[[:space:]]*\"|MODULE_ALIAS.*)\${drv/-/.}\"" \$SEARCH_PATHS | head -n 1)
        if [ -n "\$SRC_FILE" ]; then
            OBJ_NAME=\$(basename "\$SRC_FILE" .c).o
            DIR_PATH=\$(dirname "\$SRC_FILE")
            SYMBOL=\$(grep -E "obj-\\\\$\(CONFIG_[A-Z0-9_]+\)[[:space:]]*[:+]=.*[[:space:]]\${OBJ_NAME}" "\$DIR_PATH/Makefile" | sed -n 's/.*\(CONFIG_[A-Z0-9_]*\).*/\1/p')

            if [ -z "\$SYMBOL" ]; then
                VAR_NAME=\$(grep -E "[:+]=.*[[:space:]]\${OBJ_NAME}" "\$DIR_PATH/Makefile" | cut -d'=' -f1 | tr -d ' \t+:'| sed -E 's/-(y|m|objs)\$//')
                [ -n "\$VAR_NAME" ] && SYMBOL=\$(grep -E "obj-\\\\$\(CONFIG_[A-Z0-9_]+\)[[:space:]]*[:+]=.*[[:space:]]\${VAR_NAME}.o" "\$DIR_PATH/Makefile" | sed -n 's/.*\(CONFIG_[A-Z0-9_]*\).*/\1/p')
            fi
        fi
    fi

    if [ -n "\$SYMBOL" ]; then
        ASSIGN=y
        [[ "\$SYMBOL" =~ "USB" ]] && ASSIGN=m
        grep -q "^\${SYMBOL}=[ym]" .config || echo "\${SYMBOL}=\${ASSIGN}" | tee -a .config
    else
        echo "Searching for \$drv not found"
    fi
done

echo -e "x\ny\n" | make menuconfig > /dev/null

# Prepare grub config since grub-mkconfig runs as part of make install, will re-run after some further changes
sed -i 's/^#GRUB_DISABLE_LINUX_UUID=[a-z]+/GRUB_DISABLE_LINUX_UUID=true/' /etc/default/grub
sed -i 's/^#GRUB_CMDLINE_LINUX=""/GRUB_CMDLINE_LINUX="rootfstype=ext4 net.ifnames=0 panic=30"/' /etc/default/grub
[ ! -d /sys/firmware/efi ] && sed -i 's/panic=30/panic=30 vga=791/' /etc/default/grub
sed -i 's/^#*GRUB_TIMEOUT=[0-9]+/GRUB_TIMEOUT=3/' /etc/default/grub
# Drop graphics in grub, with below 2 changes load_video is never called, at least not in grub 2.14-r4
sed -i 's/^#GRUB_TERMINAL=.*/GRUB_TERMINAL=console/' /etc/default/grub
sed -i 's/^#GRUB_GFXPAYLOAD_LINUX=.*/GRUB_GFXPAYLOAD_LINUX=text/' /etc/default/grub
echo "# replicate the old GRUB_LINUX_KERNEL_GLOBS" >> /etc/default/grub
echo "sed -i 's|/boot/vmlinuz-\*|/boot/vmlinuz /boot/vmlinuz.old|' /etc/grub.d/10_linux" >> /etc/default/grub
pushd /boot
# create a dummy link
ln -s vmlinuz-1.1 vmlinuz
popd
time make -s -j$(($(nproc)*2)) bzImage modules && make modules_install install || bash
rm /boot/vmlinuz.old
ls -lh /boot

mkdir -p /boot/efi/EFI/BOOT/
curl https://boot.ipxe.org/x86_64-efi/ipxe-legacy.efi -o /boot/efi/EFI/BOOT/ipxex64.efi
curl https://raw.githubusercontent.com/tianocore/edk2-archive/refs/heads/master/ShellBinPkg/UefiShell/X64/Shell.efi -o /boot/efi/EFI/BOOT/shellx64.efi
[ -f /etc/grub.d/39_efitools ] || curl -L ${GHBASEURL}/grub.d/39_efitools -o /etc/grub.d/39_efitools
sha512sum -c <<<"cae63738889e626906270c6ad853970340d83044363680db97a70fdc8b6ec7960ba9ea7553afaf79bd8b64a61800ecf782742509e9e84d1c60b1e1e6de9d5346  /etc/grub.d/39_efitools" || bash
chmod a+x /etc/grub.d/39_efitools
grub-install --target=x86_64-efi --efi-directory=/boot/efi ${IDEV}
grub-install --target=x86_64-efi --efi-directory=/boot/efi --removable ${IDEV}
grub-install --target=i386-pc ${IDEV}
grep -q console= /proc/cmdline && sed -i 's/ panic=30/ panic=30 console=tty0 console=ttyS0,115200/' /etc/default/grub
grep -q console= /proc/cmdline && sed -i 's/^#GRUB_TERMINAL=.*/GRUB_TERMINAL="console serial"/' /etc/default/grub
grep -q console= /proc/cmdline && echo 'GRUB_SERIAL_COMMAND="serial --speed=115200 --unit=0"' >> /etc/default/grub
# enable in inittab
grep -q console= /proc/cmdline && sed -i 's/^#s0:/s0:/' /etc/inittab
cd /usr/src/linux && make install
ls -lh /boot; find /boot/efi; efibootmgr

cd /etc
ln -fs /usr/share/zoneinfo/$TIMEZONE localtime
emerge -uv -j8 --keep-going y iptables nftables dev-vcs/git ${APCUPSDTOOLS} iotop iftop ddrescue sys-apps/pv tcpdump dmidecode hdparm \
 mlocate sys-apps/watchdog dhcpcd app-misc/mc smartmontools syslog-ng virtual/cron logrotate lsof ${BATTERYTOOLS:=} ${PRESET_PACKAGES} || bash
#rerun make sure up2date
time emerge -uvDN -j4 world --exclude gcc glibc || bash
etc-update --automode -5
#todo fix with sed ... but virtual machine dont save clock ;)
#/etc/init.d/hwclock save
sed -i 's/^c1:12345:respawn:\/sbin\/agetty .* tty1 linux\$/& --noclear/' /etc/inittab || bash
cd /etc/init.d
ln -s net.lo net.eth0
[ -n "${NETSVC}" ] && [ "${NETSVC}" != "net.eth0" ] && ln -sf net.lo ${NETSVC}
rc-update add watchdog boot
rc-update add syslog-ng default
rc-update add *cron* default
if [ -n "${SSHKEY}" ]; then
  # baked key: root by key only, password authentication off
  # (new users get the key too via /etc/skel)
  mkdir -p /root/.ssh /etc/skel/.ssh
  chmod 700 /root/.ssh /etc/skel/.ssh
  echo "${SSHKEY}" >> /root/.ssh/authorized_keys
  echo "${SSHKEY}" >> /etc/skel/.ssh/authorized_keys
  chmod 600 /root/.ssh/authorized_keys /etc/skel/.ssh/authorized_keys
  sed -i 's/^#PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
  [ "${SSHPASSAUTH}" != "yes" ] && echo "PasswordAuthentication no" >> /etc/ssh/sshd_config
else
  sed -i 's/^#PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
fi
rc-update add sshd default
rc-update delete netmount

# Start creating fix script
echo # Remove udev rules that make network interface names compleatly unpredictable and unmanagable. > /etc/local.d/remove.net.rules.start
echo setterm -blank 0 >> /etc/local.d/remove.net.rules.start
echo rm -rf /usr/lib/udev/rules.d/80-net-name-slot.rules >> /etc/local.d/remove.net.rules.start
echo rm -rf /usr/lib/udev/rules.d/80-net-setup-link.rules >> /etc/local.d/remove.net.rules.start
# Make it executable, and run also on shutdown
chmod a+x /etc/local.d/remove.net.rules.start
ln -fs /etc/local.d/remove.net.rules.start /etc/local.d/remove.net.rules.stop
rc-update add local default
# run it now and add clean exit (rm will fail if there is no file so always exit with ok)
sh /etc/local.d/remove.net.rules.start
echo exit 0 >> /etc/local.d/remove.net.rules.start

# TODO detect if username should be included or not
#sed -i 's/\troot\t/\t/' /etc/crontab
echo -e "*/30  *  * * *\troot\tsntp -S $NTPSERVER > /dev/null" >> /etc/crontab
# some variants of cron needs to have default cron installed
#crontab /etc/crontab

if (grep -q usegitportage /proc/cmdline); then
# move to git based portage tree
emerge -j2 app-eselect/eselect-repository
umount /var/db/repos/gentoo
rm -rf /var/db/snapshots
 # https://wiki.gentoo.org/wiki/Portage_with_Git
eselect repository disable gentoo
eselect repository enable gentoo
#sed -i 's#sync-uri = .*#sync-uri = git://anongit.gentoo.org/repo/gentoo.git#' /etc/portage/repos.conf/eselect-repo.conf
emerge --sync
fi

[[ ! -z "${APCUPSDTOOLS:=}" ]] && rc-update add apcupsd default && rc-update add apcupsd.powerfail shutdown
#todo configure snmp and add to startup

#todo... if vmware emerge open-vm-tools?

[ -n "${NETSVC}" ] && rc-update add ${NETSVC} default

# run preset chroot hooks (service configuration etc.)
export ROOTEMAIL="${ROOTEMAIL}" NTPSERVER="${NTPSERVER}" SET_PASS="${SET_PASS}" INSTALLUSER="${INSTALLUSER}"
for h in /preset-hooks/*.sh; do
  [ -f "\$h" ] && { echo "Running preset hook \$h"; sh "\$h" || bash; }
done

umount /var/tmp
EOF
chmod a+x chrootstart.sh
mkdir -p preset-hooks
for h in ${PRESET_HOOKS}; do
  cp "$h" preset-hooks/
  # a preset can ship data for its hook in presets/<name>.d/
  hd="${h%.chroot.sh}.d"
  [ -d "$hd" ] && cp -r "$hd" preset-hooks/
done

time chroot . ./chrootstart.sh
rm -rf chrootstart.sh preset-hooks
# Delete temporary change to avoid insufficient free space, emerge job parallelism reduced
sed -i 's/--jobs-tmpdir-require-free-gb=[0-9]\+ \?//g' $MAKECONF

umount var/tmp
rm -rf var/tmp/*
rm -rf var/cache/distfiles
umount *
cd /
## umount somehow fails recently, but can not find usage, lets go lazy
umount -l /mnt/gentoo  || exit 1
# halt in QEMU guest instead of reboot to messure and autohandle on vm shutdown
grep -q setupdonehalt /proc/cmdline && halt || reboot
