#!/bin/bash
# Detects and fixes a real, observed cold-boot bug: tuxedo_compatibility_check
# sometimes ends up loaded in a bad/stale state very early in boot (likely from
# repeated near-simultaneous WMI-device uevents each triggering their own modprobe
# attempt - "module init" was observed printing 8-9 times for tuxedo_keyboard alone
# during one cold boot), such that tuxedo_keyboard/uniwill_wmi/tuxedo_io then fail
# to load at all ("could not insert 'tuxedo_keyboard': No such device", i.e.
# -ENODEV from the compatibility check) even though the DMI match is correct and
# manually reloading later works fine.
#
# Only acts if tuxedo_keyboard failed to load - does nothing (no disruption) on a
# boot where it already came up correctly. ite_8291/ite_8291_lb are untouched -
# they're independent USB HID drivers with no DMI/compatibility-check dependency,
# and were never observed to be affected by this issue.
#
# Deliberately no `set -e`: a single failed modprobe (e.g. a genuine DMI mismatch
# after a firmware/BIOS update, not just the boot-time race this script targets)
# must not abort the sequence early - every step below still runs each attempt, and
# we retry the whole sequence a few times in case it really is the transient race.
# If tuxedo_keyboard still isn't loaded after all retries, exit non-zero so this
# shows up as a failed systemd unit rather than silently doing nothing - that
# failure is itself a useful signal (e.g. it's what surfaced the DMI-mismatch bug
# after the official Eluktronics firmware update, see ONBOARDING.md section 10).

if lsmod | grep -q '^tuxedo_keyboard '; then
  exit 0
fi

attempt=1
max_attempts=3
while [ "$attempt" -le "$max_attempts" ]; do
  for m in tuxedo_io uniwill_wmi clevo_wmi tuxedo_nb02_nvidia_power_ctrl tuxedo_keyboard tuxedo_compatibility_check; do
    rmmod "$m" 2>/dev/null || true
  done

  modprobe tuxedo_compatibility_check || true
  modprobe tuxedo_keyboard || true
  modprobe uniwill_wmi || true
  modprobe tuxedo_io || true

  if lsmod | grep -q '^tuxedo_keyboard '; then
    exit 0
  fi

  attempt=$((attempt + 1))
  sleep 1
done

echo "tongfang-uniwill-reload: tuxedo_keyboard still not loaded after $max_attempts attempts" >&2
exit 1
