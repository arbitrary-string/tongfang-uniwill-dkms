#!/bin/bash
# Full from-scratch bring-up for the Eluktronics Hydroc 16 G1 on a fresh Ubuntu 26.04
# ("resolute") install. Reproduces, in order:
#   1. Build prerequisites for DKMS.
#   2. A permanent apt pin blocking TUXEDO's stock tuxedo-drivers package, so it can
#      never silently overwrite/conflict with this fork's patched kernel modules
#      (same module basenames, different DMI-gated behavior for this board).
#   3. This fork (with the Hydroc 16 G1 local patches) built and installed via DKMS.
#   4. TUXEDO Control Center (TCC), installed from OUR OWN verified-binary archive
#      (arbitrary-string/tuxedo-control-center-archive), not TUXEDO's live apt repo —
#      deliberately avoids any risk of a silent future TCC update changing behavior
#      or adding compatibility checks against this driver. A local placeholder
#      package satisfies TCC's tuxedo-drivers/tuxedo-keyboard dependency without
#      installing either.
#
# This is a personal reinstall script for this exact machine/board, not a generic
# installer — re-verify hardware identity (see ONBOARDING.md Step 1) before running
# this on any other machine.
set -euo pipefail

TCC_ARCHIVE_BASE="https://github.com/arbitrary-string/tuxedo-control-center-archive/releases/download/v3.0.9-verified"
TCC_DEB="tuxedo-control-center_3.0.9_amd64.deb"
PLACEHOLDER_DEB="tuxedo-keyboard-placeholder_4.0.0_all.deb"
CLONE_DIR="${CLONE_DIR:-$HOME/laptopissues/repos/tongfang-uniwill-dkms}"

echo "== Step 1: build prerequisites =="
sudo apt-get update
sudo apt-get install -y git build-essential dkms linux-headers-generic curl

echo "== Step 2: permanently block TUXEDO's stock tuxedo-drivers package =="
# Belt-and-suspenders: we also never register TUXEDO's live apt repo in this script
# at all (see step 4), so apt has no source to pull tuxedo-drivers from anyway. This
# pin protects against the case where the live repo gets added manually later.
sudo tee /etc/apt/preferences.d/block-tuxedo-drivers.pref > /dev/null << 'EOF'
Package: tuxedo-drivers
Pin: release *
Pin-Priority: -1
EOF

echo "== Step 3: clone and DKMS-install the patched driver fork =="
if [ ! -d "$CLONE_DIR/.git" ]; then
  git clone https://github.com/arbitrary-string/tongfang-uniwill-dkms.git "$CLONE_DIR"
fi
cd "$CLONE_DIR"
PKG=tongfang-uniwill-dkms
VER=$(grep '^PACKAGE_VERSION=' dkms.conf | head -1 | cut -d'"' -f2)
echo "Package version from dkms.conf: $VER"

sudo mkdir -p "/usr/src/${PKG}-${VER}"
# git archive, never the raw working tree — uncommitted changes would silently
# vanish from the build otherwise.
git archive HEAD | sudo tar -x -C "/usr/src/${PKG}-${VER}/"

sudo dkms add -m "${PKG}" -v "${VER}" || true   # ok if already added
sudo dkms build -m "${PKG}" -v "${VER}"
sudo dkms install -m "${PKG}" -v "${VER}"
sudo depmod -a

echo "== Step 4: install TUXEDO Control Center from our own verified archive =="
# Deliberately NOT adding TUXEDO's live apt repo here. We install the exact version
# we've already tested against this driver fork, from our own GitHub release, so a
# future TUXEDO repo change/removal or an unreviewed TCC update can't affect this
# install. To evaluate a newer TCC version later: add TUXEDO's repo manually, test
# it, and if it works well, update this script AND push a new archived version to
# tuxedo-control-center-archive before switching the pin here.
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
curl -fL -o "$TMPDIR/$TCC_DEB" "$TCC_ARCHIVE_BASE/$TCC_DEB"
curl -fL -o "$TMPDIR/$PLACEHOLDER_DEB" "$TCC_ARCHIVE_BASE/$PLACEHOLDER_DEB"

# Real, non-alternative TCC dependency — let apt resolve this one normally.
sudo apt-get install -y libayatana-appindicator3-1

# Placeholder first, so TCC's tuxedo-drivers|tuxedo-keyboard alternative is already
# satisfied by the time dpkg processes TCC's own dependency check.
sudo dpkg -i "$TMPDIR/$PLACEHOLDER_DEB"
sudo dpkg -i --ignore-depends=tuxedo-drivers,tuxedo-keyboard "$TMPDIR/$TCC_DEB"

echo "== Step 5: sanity checks =="
sudo dpkg --audit
sudo apt-get check
sudo systemctl status tccd --no-pager || true

echo
echo "Done. A reboot is recommended to confirm the driver autoloads cleanly from a"
echo "cold boot (verify with: lsmod | grep -E 'ite_8291|tuxedo|uniwill', and check"
echo "/sys/class/leds/ for the expected LED classdevs)."
