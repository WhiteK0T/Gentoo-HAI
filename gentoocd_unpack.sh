#!/bin/bash
# Needed packages for grub-mkrescue emerge -uv1 sys-fs/mtools dev-libs/libisoburn app-cdr/cdrtools

# some su configurations hand root a broken PATH; make sure the basics resolve
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH}"
# check for iso before asking for root
srciso=install-amd64-minimal-*.iso
for f in $srciso; do
  if [[ ! -e "$f" ]]; then
    echo "Matching minimal iso not found:"
    echo "   $f"
    echo " please run get_minimal_cd.sh to fetch latest version"
    exit 1
  fi
  srciso=$f
done
echo will be using $srciso as source

ALLPOSITIONAL=()
POSITIONAL=()
# modern (dracut-based) cds never run cdupdate.sh from the cd root, so the
# bashrc hook must be patched into the squashfs; nosquash restores the old
# genkernel-era behavior for old isos
DOSQUASH=1
KEYMAP=us
PRESETARG=""
# root password for the livecd and the installed system (baked into the squashfs)
SET_PASS=${SET_PASS:-}
while (($#)); do
  ALLPOSITIONAL+=("$1") # save it in an array for later
  case $1 in
  auto)
    AUTO=YES
    POSITIONAL+=("$1") # save it in an array for later
  ;;
  dosquash)
    DOSQUASH=1
  ;;
  nosquash)
    DOSQUASH=0
  ;;
  --keymap)
    # value for livecd env from https://github.com/gentoo/genkernel/blob/master/defaults/keymaps/keymapList
    ALLPOSITIONAL+=("$2")
    KEYMAP=$2
    shift
  ;;
  --preset)
    # preset name(s) for install.sh, comma separated: --preset minimal,xeon
    ALLPOSITIONAL+=("$2")
    PRESETARG=$2
    shift
  ;;
  setupdonehalt)
    SETUPDONEHALT=YES
  ;;
  nobinpkg)
    # tell install.sh to skip the binary package host (build from source)
    NOBINPKG=YES
  ;;
  *)
    # unknown arguments are passed thru
    POSITIONAL+=("$1") # save it in an array for later
  ;;
  esac
  shift
done
set -- "${POSITIONAL[@]}" # restore positional parameters
ALLPOSITIONAL=${ALLPOSITIONAL[@]}
POSITIONAL=${POSITIONAL[@]}

# check for root since we are using tmpfs and need root to not risk getting incorrect permissions on the new squashfs
if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root (to mount tmpfs), please provide password to su" 1>&2
  su -c "SET_PASS='${SET_PASS}' /bin/sh $0 ${ALLPOSITIONAL}" && [ "$AUTO" == "YES" ] && (rm -f kvm_lxgentootest.qcow2; sh test_w_qemu.sh -cdrom install-amd64-mod.iso ${POSITIONAL})
  exit
fi
# files that contains kernelcmdlines that should be patched
bootmenufiles="boot/grub/grub.cfg"
echo 'emerge -uv1 app-cdr/cdrtools sys-fs/squashfs-tools dev-libs/libisoburn sys-fs/mtools  # squashfs-tools needs USE="lzma" for xz images'
set -x
# unmount in case we got something left over since before
[ -d gentoo_boot_cd ] && umount gentoo_boot_cd
[ ! -d gentoo_boot_cd ] && (mkdir gentoo_boot_cd || exit 1)
echo Make all changes in a tmpfs for performance, and saving on SSD writes.
mount none -t tmpfs gentoo_boot_cd -o size=6G,nr_inodes=1048576
pushd gentoo_boot_cd || exit 1
# 7z x is broken in version 16.02, it does work with 9.20
# use isoinfo extraction from cdrtools instead
isoinfo -R -i ../$srciso -X || exit 1

if [ $DOSQUASH == 1 ]; then
# fail early if unsquashfs cannot actually decompress this image (e.g. an xz
# image but squashfs-tools built without USE=lzma). -s reads only the
# uncompressed superblock, so test a real listing which forces metadata
# decompression.
if ! unsquashfs -l image.squashfs >/dev/null 2>&1; then
  COMP=$(unsquashfs -s image.squashfs 2>/dev/null | awk '/^Compression/{print $2}')
  echo -e "\e[91mERROR: unsquashfs cannot decompress image.squashfs (compression: ${COMP:-unknown})."
  echo -e "On Gentoo enable the matching USE flag (xz images need 'lzma'):"
  echo -e "  echo 'sys-fs/squashfs-tools lzma lzo lz4 zstd' >> /etc/portage/package.use/squashfs-tools"
  echo -e "  emerge -1v sys-fs/squashfs-tools\e[0m"
  exit 1
fi
unsquashfs image.squashfs || exit 1
rm image.squashfs
# mv squashfs-root ~/squashroot

echo make changes...
# net.ifnames=0 is set, but ...
# Try to get rid of the PredictableNetworkInterfaceNames unpredicatability With it we never know what the nics are called.
mkdir -p squashfs-root/lib/udev/rules.d
echo > squashfs-root/lib/udev/rules.d/80-net-name-slot.rules
echo > squashfs-root/lib/udev/rules.d/80-net-setup-link.rules

# bake the chosen root password in so the addon and g-install.sh pick it up
[ -n "${SET_PASS}" ] && echo "export SET_PASS='${SET_PASS}'" >> squashfs-root/root/.bashrc
cat ../cdhelpers/gentoo_cd_bashrc_addon >> squashfs-root/root/.bashrc
mksquashfs squashfs-root image.squashfs || exit 1
rm -rf squashfs-root
else
  echo Update cdroot from cdhelpers
  cp -rav ../cdhelpers/* .
  [ -f cdupdate.sh ] && chmod a+x cdupdate.sh
fi

if [ -d ../cpiofiles ]; then
pushd ../cpiofiles
  echo Updating cpio initrd from cpiofiles
  find .
  ls -lh ../gentoo_boot_cd/boot/gentoo.igz
  find . -print | cpio -H newc -o | xz --check=crc32 -vT0 >> ../gentoo_boot_cd/boot/gentoo.igz
  ls -lh ../gentoo_boot_cd/boot/gentoo.igz
popd
fi

# change to defined keymap and add autoinstall
sed -i "s/ dokeymap/ net.ifnames=0 keymap=${KEYMAP}  autoinstall/" $bootmenufiles

# make presets available on the cd for install.sh
[ -d ../presets ] && cp -ra ../presets .
# bake the ssh public key if one lies next to the scripts
[ -f ../authorized_keys ] && cp ../authorized_keys .

if [ "$AUTO" == "YES" ]; then
  echo running with auto - wont stop
  [[ "$SETUPDONEHALT" == "YES" ]] && sed -i 's/ autoinstall/ autoinstall setupdonehalt/' $bootmenufiles
  sed -i 's/ autoinstall/ autoinstall console=tty0 console=ttyS0,115200/' $bootmenufiles
  # use console for -nographics, sga and curses
  sed -i 's/vga=791//' $bootmenufiles
  cp ../install.sh g-install.sh
  cp ../portagehelper.sh .
else
# TODO color ths to make it readable
echo -e "\n\tStarting separate shell, just exit if no changes should be done.\n\n\tWhen exit, the iso will be rebuilt."
bash
fi

# pass preset selection to install.sh via kernel cmdline
[ -n "$PRESETARG" ] && sed -i "s/ autoinstall/ autoinstall preset=${PRESETARG}/" $bootmenufiles
# skip the binary package host if requested
[[ "${NOBINPKG:-}" == "YES" ]] && sed -i 's/ autoinstall/ autoinstall nobinpkg/' $bootmenufiles

# rebuild efimg https://gitweb.gentoo.org/proj/catalyst.git/tree/targets/support/create-iso.sh#n256
clst_target_path=.

popd
# grub-mkrescue silently skips boot modes whose grub modules are missing on the host
[ -d /usr/lib/grub/i386-pc ] || echo -e "\e[91mWARNING: no /usr/lib/grub/i386-pc - ISO will NOT boot on BIOS/SeaBIOS (set GRUB_PLATFORMS=\"efi-64 pc\" and re-emerge grub)\e[0m"
[ -d /usr/lib/grub/x86_64-efi ] || echo -e "\e[91mWARNING: no /usr/lib/grub/x86_64-efi - ISO will NOT boot on UEFI\e[0m"
# keep the original volume label: the cd kernel cmdline mounts the live
# medium by it (dracut root=live:CDLABEL=...)
VOLID=$(isoinfo -d -i $srciso 2>/dev/null | sed -n 's/^Volume id: //p')
[ -z "$VOLID" ] && echo -e "\e[91mWARNING: could not read volume id from $srciso - the modified iso will likely not boot\e[0m"
echo "Creating ISO (volid: ${VOLID}) ..."
grub-mkrescue -joliet -iso-level 3 -volid "${VOLID}" -o install-amd64-mod.iso gentoo_boot_cd/

umount gentoo_boot_cd
rm -rf gentoo_boot_cd
