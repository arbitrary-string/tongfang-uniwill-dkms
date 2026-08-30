#!/bin/bash
# Detects and fixes a real, observed cold-boot bug: tuxedo_compatibility_check
# sometimes ends up loaded in a bad/stale state very early in boot (likely from
# repeated near-simultaneous WMI-device uevents each triggering their own modprobe
# attempt - "module init" was observed printing 8 times for tuxedo_keyboard alone
# during one cold boot), such that tuxedo_keyboard/uniwill_wmi/tuxedo_io then fail
# to load at all ("could not insert 'tuxedo_keyboard': No such device", i.e.
# -ENODEV from the compatibility check) even though the DMI match is correct and
# manually reloading later works fine.
#
# Only acts if tuxedo_keyboard failed to load - does nothing (no disruption) on a
# boot where it already came up correctly. ite_8291/ite_8291_lb are untouched -
# they're independent USB HID drivers with no DMI/compatibility-check dependency,
# and were never observed to be affected by this issue.
set -e

if lsmod | grep -q '^tuxedo_keyboard '; then
  exit 0
fi

for m in tuxedo_io uniwill_wmi clevo_wmi tuxedo_nb02_nvidia_power_ctrl tuxedo_keyboard tuxedo_compatibility_check; do
  rmmod "$m" 2>/dev/null || true
done

modprobe tuxedo_compatibility_check
modprobe tuxedo_keyboard
modprobe uniwill_wmi
modprobe tuxedo_io

exit 0
