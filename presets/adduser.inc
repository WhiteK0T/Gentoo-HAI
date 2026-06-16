# Shared user-creation snippet for preset chroot hooks. SOURCE it, don't run it
# (named .inc so the hook runner's *.sh glob skips it). Expects INSTALLUSER and
# SET_PASS in the environment; set USER_GROUPS before sourcing to override the
# default group list. Creates the login user (initial password = SET_PASS, same
# as root - change it!), adds the groups that actually exist, and gives wheel
# sudo (a no-op if sudo/sudoers is not installed).
: "${USER_GROUPS:=wheel users audio video usb plugdev render input}"
if [ -n "${INSTALLUSER:-}" ] && ! id "$INSTALLUSER" >/dev/null 2>&1; then
  useradd -m "$INSTALLUSER"
  for _g in $USER_GROUPS; do
    getent group "$_g" >/dev/null && usermod -aG "$_g" "$INSTALLUSER"
  done
  echo "${INSTALLUSER}:${SET_PASS:-password}" | chpasswd -c BCRYPT
fi
[ -f /etc/sudoers ] && sed -i -e 's/^# *%wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' \
  -e 's/^# *%wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/' /etc/sudoers
