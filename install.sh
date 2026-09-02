#!/bin/bash
# Full from-scratch bring-up for this fork's supported TongFang/Uniwill-based chassis, on a
# fresh Ubuntu 26.04 ("resolute") install. Auto-detects which known board it's running on via
# DMI and runs the same steps regardless - all per-board differences (DMI matches, TDP tables,
# keyboard color-correction curves) live in this repo's own patched C source, not in this
# script. One installer for every machine this repo supports, not one script per machine.
#
# Reproduces, in order:
#   1. Build prerequisites for DKMS.
#   2. A permanent apt pin blocking TUXEDO's stock tuxedo-drivers package, so it can never
#      silently conflict with this fork's patched kernel modules (same module basenames).
#   3. This fork (with all local per-board patches) built and installed via DKMS, then loaded.
#   4. The cold-boot autoload race workaround (tongfang-uniwill-reload.service).
#   5. TUXEDO Control Center (TCC), installed from OUR OWN verified-binary archive
#      (arbitrary-string/tuxedo-control-center-archive), not TUXEDO's live apt repo - avoids
#      any risk of a silent future TCC update changing behavior or adding compatibility checks
#      against this fork. A local placeholder package satisfies TCC's
#      tuxedo-drivers/tuxedo-keyboard dependency without installing either.
#
# Safe to re-run: each step either no-ops or cleanly replaces its own prior result.
#
# If this machine's DMI identity isn't one this repo already has local patches for, the driver
# will almost certainly refuse to load (tuxedo_compatibility_check gate) - this script warns and
# asks for confirmation before proceeding in that case, rather than failing silently partway
# through. See README.md / ONBOARDING.md for how to add support for a new board first.
set -euo pipefail

TCC_ARCHIVE_BASE="https://github.com/arbitrary-string/tuxedo-control-center-archive/releases/download/v3.0.9-verified"
TCC_DEB="tuxedo-control-center_3.0.9_amd64.deb"
PLACEHOLDER_DEB="tuxedo-keyboard-placeholder_4.0.0_all.deb"

confirm_or_exit() {
	read -r -p "$1 [y/N] " reply
	case "$reply" in
		[Yy]*) ;;
		*) echo "Aborted."; exit 1 ;;
	esac
}

echo "== Step 0: identify hardware =="
SYS_VENDOR=$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || echo "")
BOARD_NAME=$(cat /sys/class/dmi/id/board_name 2>/dev/null || echo "")
PRODUCT_NAME=$(cat /sys/class/dmi/id/product_name 2>/dev/null || echo "")
PRODUCT_SKU=$(cat /sys/class/dmi/id/product_sku 2>/dev/null || echo "")
echo "sys_vendor='$SYS_VENDOR' board_name='$BOARD_NAME' product_name='$PRODUCT_NAME' product_sku='$PRODUCT_SKU'"

# Purely informational - matched against the same DMI identities this repo's local test
# patches key off of, just so the operator gets a friendly confirmation of what was detected.
# Missing from this list does NOT necessarily mean unsupported (a genuine TUXEDO board with a
# "TUXEDO" vendor/board/chassis string works out of the box with zero local patches) - it's
# only meant to flag the case that actually needs attention: a non-TUXEDO-branded chassis this
# repo doesn't yet have a local patch for.
DETECTED=""
case "$SYS_VENDOR|$BOARD_NAME" in
	*TUXEDO*|*"|"*TUXEDO*)
		DETECTED="Genuine TUXEDO device" ;;
	"ELUKTRONICS|HYDROC-16 powered by premamod.com")
		DETECTED="Eluktronics Hydroc 16 G1 (original factory firmware)" ;;
	"SchenkerTechnologiesGmbH|GM7IXxN")
		DETECTED="Eluktronics Hydroc 16 G1 (XMG-branded interim firmware)" ;;
	"Eluktronics Inc.|HYDROC-16")
		DETECTED="Eluktronics Hydroc 16 G1 (official Eluktronics firmware)" ;;
	"TongFang|GX4MRXL")
		DETECTED="TongFang GX4MRXL (exploratory bring-up)" ;;
	"SchenkerTechnologiesGmbH|X6AR5xxY")
		DETECTED="XMG NEO 16 (E25) / TUXEDO Stellaris 16 Gen7 board (X6AR5xxY)" ;;
esac

if [ -z "$DETECTED" ]; then
	echo
	echo "WARNING: no local test patch in this repo recognizes sys_vendor='$SYS_VENDOR'"
	echo "board_name='$BOARD_NAME'. tuxedo_compatibility_check will very likely refuse to load"
	echo "the driver stack as a result. See README.md / ONBOARDING.md for the process to add"
	echo "support for a new board (four gated files: tuxedo_compatibility_check.c,"
	echo "uniwill_keyboard.h, tuxedo_io.c, ite_8291.c) before running this installer."
	confirm_or_exit "Continue anyway?"
else
	echo "Detected: $DETECTED"
fi

echo "== Step 1: build prerequisites =="
sudo apt-get update
sudo apt-get install -y git build-essential dkms linux-headers-generic curl

echo "== Step 2: permanently block TUXEDO's stock tuxedo-drivers package =="
# Belt-and-suspenders: this script never registers TUXEDO's live apt repo either (see step 5),
# so apt has no source to pull tuxedo-drivers from anyway. This pin protects against the case
# where the live repo gets added manually later.
sudo tee /etc/apt/preferences.d/block-tuxedo-drivers.pref > /dev/null << 'EOF'
Package: tuxedo-drivers
Pin: release *
Pin-Priority: -1
EOF

echo "== Step 3: build and install this fork via DKMS =="
# Run in place if this script is being executed from inside a checkout of this repo (the
# common case - this file lives in the repo root); otherwise clone one fresh. Either way, the
# actual DKMS build always archives HEAD, never the working tree, so uncommitted local patches
# don't silently vanish from the build without at least a warning here first.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if git -C "$SCRIPT_DIR" rev-parse --show-toplevel >/dev/null 2>&1; then
	REPO_DIR="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
else
	REPO_DIR="${CLONE_DIR:-$HOME/laptopissues/repos/tongfang-uniwill-dkms}"
	if [ ! -d "$REPO_DIR/.git" ]; then
		git clone https://github.com/arbitrary-string/tongfang-uniwill-dkms.git "$REPO_DIR"
	fi
	# Set local identity immediately on a fresh clone, before it could ever be committed to -
	# never rely on a global default (see ONBOARDING.md section 0 / README.md).
	git -C "$REPO_DIR" config user.name "arbitrary-string"
	git -C "$REPO_DIR" config user.email "arbitrarystring@gmail.com"
fi
cd "$REPO_DIR"

if ! (git diff --quiet && git diff --cached --quiet); then
	echo "WARNING: uncommitted changes in $REPO_DIR - these will be SILENTLY EXCLUDED from the"
	echo "DKMS build (it archives HEAD, not the working tree)."
	confirm_or_exit "Continue anyway (build from last commit, ignoring uncommitted changes)?"
fi

PKG=tongfang-uniwill-dkms
VER=$(grep '^PACKAGE_VERSION=' dkms.conf | head -1 | cut -d'"' -f2)
echo "Package version from dkms.conf: $VER"

sudo dkms remove -m "$PKG" -v "$VER" --all 2>&1 | tail -5 || true
sudo rm -rf "/usr/src/${PKG}-${VER}"
sudo mkdir -p "/usr/src/${PKG}-${VER}"
git archive HEAD | sudo tar -x -C "/usr/src/${PKG}-${VER}/"
sudo dkms add -m "$PKG" -v "$VER"
sudo dkms build -m "$PKG" -v "$VER"
sudo dkms install -m "$PKG" -v "$VER" --force
sudo depmod -a

echo "== Step 4: load the driver chain and confirm it actually came up =="
# Retried, not a single attempt: empirically observed during testing on 2026-09-02 that even a
# live reload right after a successful DKMS install can transiently fail the very next check
# (dmesg showed one clean "tuxedo_keyboard: module init" with no errors, yet the immediately
# following `lsmod` check missed it - module was confirmed loaded moments later) - the same
# class of flakiness tongfang-uniwill-reload.service exists to paper over at boot, just hit
# here during the script's own reload instead. Same retry shape as
# tongfang-uniwill-reload-if-needed.sh: full clean rmmod+modprobe cycle, up to 5 attempts.
# Also settle briefly before checking: testing showed dmesg confirming a clean module init with
# no errors, immediately followed by the lsmod check missing it anyway - checking with zero
# delay after modprobe returns isn't reliable here, whatever the underlying cause (root cause
# not fully identified - no competing udev rule found, `udevadm settle` alone didn't explain
# it either - but a short sleep before checking reliably reflects the true settled state).
attempt=1
max_attempts=5
loaded=false
while [ "$attempt" -le "$max_attempts" ]; do
	for m in tuxedo_io uniwill_wmi clevo_wmi tuxedo_nb02_nvidia_power_ctrl tuxedo_keyboard tuxedo_compatibility_check; do
		sudo rmmod "$m" 2>/dev/null || true
	done
	sudo modprobe tuxedo_compatibility_check || true
	sudo modprobe tuxedo_keyboard || true
	sudo modprobe uniwill_wmi || true
	sudo modprobe tuxedo_io || true
	sudo udevadm settle --timeout=5 || true
	sleep 2

	if lsmod | grep -q '^tuxedo_keyboard '; then
		loaded=true
		break
	fi
	attempt=$((attempt + 1))
done
sudo modprobe ite_8291 2>/dev/null || true
sudo modprobe ite_8291_lb 2>/dev/null || true

if [ "$loaded" != true ]; then
	echo "ERROR: tuxedo_keyboard failed to load after $max_attempts attempts - this hardware's"
	echo "DMI identity is not accepted by tuxedo_compatibility_check. Stopping before installing"
	echo "TCC (it would have nothing to talk to)."
	exit 1
fi

echo "== Step 5: install cold-boot autoload workaround =="
# Real, observed bug: tuxedo_compatibility_check can end up loaded in a bad/stale state very
# early in boot (a flapping/retry race from near-simultaneous WMI-device uevents), causing
# tuxedo_keyboard/uniwill_wmi/tuxedo_io to fail to load at all despite a correct DMI match. This
# service checks after boot and does one clean reload of the chain only if actually needed - a
# no-op on a boot where autoload already worked correctly.
sudo install -m 755 "$REPO_DIR/tongfang-uniwill-reload-if-needed.sh" /usr/local/sbin/tongfang-uniwill-reload-if-needed.sh
sudo install -m 644 "$REPO_DIR/tongfang-uniwill-reload.service" /etc/systemd/system/tongfang-uniwill-reload.service
sudo systemctl daemon-reload
sudo systemctl enable --now tongfang-uniwill-reload.service

echo "== Step 6: install TUXEDO Control Center from our own verified archive =="
# Deliberately NOT adding TUXEDO's live apt repo here. We install the exact version we've
# already tested against this driver fork, from our own GitHub release, so a future TUXEDO
# repo change/removal or an unreviewed TCC update can't affect this install. To evaluate a
# newer TCC version later: add TUXEDO's repo manually, test it, and if it works well, update
# this script AND push a new archived version to tuxedo-control-center-archive before
# switching the pin here.
sudo apt-get install -y libayatana-appindicator3-1

TCC_STATUS=$(dpkg-query -W -f='${Status}' tuxedo-control-center 2>/dev/null || true)
if [ "$TCC_STATUS" = "install ok installed" ]; then
	echo "tuxedo-control-center already installed, skipping download/install."
else
	DOWNLOAD_DIR="${TCC_DOWNLOAD_DIR:-$(dirname "$REPO_DIR")/tcc-install-cache}"
	mkdir -p "$DOWNLOAD_DIR"
	curl -fL -o "$DOWNLOAD_DIR/$TCC_DEB" "$TCC_ARCHIVE_BASE/$TCC_DEB"
	curl -fL -o "$DOWNLOAD_DIR/$PLACEHOLDER_DEB" "$TCC_ARCHIVE_BASE/$PLACEHOLDER_DEB"

	# Placeholder first, so TCC's tuxedo-drivers|tuxedo-keyboard alternative is already
	# satisfied by the time dpkg processes TCC's own dependency check.
	PLACEHOLDER_STATUS=$(dpkg-query -W -f='${Status}' tuxedo-keyboard-placeholder 2>/dev/null || true)
	if [ "$PLACEHOLDER_STATUS" != "install ok installed" ]; then
		sudo dpkg -i "$DOWNLOAD_DIR/$PLACEHOLDER_DEB"
	fi
	sudo dpkg -i --ignore-depends=tuxedo-drivers,tuxedo-keyboard "$DOWNLOAD_DIR/$TCC_DEB"
fi

echo "== Step 7: sanity checks =="
sudo dpkg --audit
sudo apt-get check
sudo systemctl status tccd --no-pager || true

echo
if [ -n "$DETECTED" ]; then
	echo "Bring-up complete for: $DETECTED"
else
	echo "Bring-up complete (unrecognized hardware, proceeded on manual override)."
fi
echo "A reboot is recommended to confirm the driver autoloads cleanly from a cold boot."
echo "Verify with: lsmod | grep -E 'ite_8291|tuxedo|uniwill', and check /sys/class/leds/."
