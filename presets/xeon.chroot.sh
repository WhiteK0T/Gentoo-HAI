#!/bin/sh
# Xeon preset: low-RAM build setup (runs inside the chroot)
set -x

# /var/tmp is a small tmpfs on this box; route heavy builds to disk
mkdir -p /var/cache/portage-tmpdir /etc/portage/env /etc/portage/package.env
echo 'PORTAGE_TMPDIR="/var/cache/portage-tmpdir"' > /etc/portage/env/largetmp.conf
cat > /etc/portage/package.env/largetmp << EOF
dev-qt/qtwebengine largetmp.conf
www-client/firefox largetmp.conf
www-client/chromium largetmp.conf
sys-devel/gcc largetmp.conf
dev-lang/rust largetmp.conf
app-office/libreoffice largetmp.conf
net-libs/webkit-gtk largetmp.conf
EOF

# video driver for the old GeForce (takes effect when X/KDE gets installed)
grep -q '^VIDEO_CARDS=' /etc/portage/make.conf || echo 'VIDEO_CARDS="nouveau"' >> /etc/portage/make.conf

exit 0
