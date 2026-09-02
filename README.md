# Table of Content
- <a href="#description">Description</a>
- <a href="#tongfang-gm6ixxb-fork-tested-on-eluktronics-hydroc-16-g1">TongFang GM6IXxB fork (tested on: Eluktronics Hydroc 16 G1)</a>
- <a href="#building-and-install">Building and Install</a>
- <a href="#troubleshooting">Troubleshooting</a>
- <a href="#regarding-upstreaming-of-tuxedo-drivers">Regarding upstreaming of tuxedo-drivers</a>

# Description
Drivers for several platform devices for TUXEDO notebooks meant for DKMS.

# TongFang GM6IXxB fork (tested on: Eluktronics Hydroc 16 G1)

This fork of TUXEDO's `tuxedo-drivers` adds board-specific patches (local DMI matches, not
upstream-worthy) for the TongFang **`GM6IXxB`** chassis — the same barebone TUXEDO sells as the
"Stellaris 16 Gen6" (Intel), unrecognized by this driver out of the box under any other brand.
It was tested and verified specifically on an **Eluktronics Hydroc 16 G1**, but `GM6IXxB` is a
TongFang reference design manufactured for many different resellers under many different model
names — the same underlying hardware, sold rebranded. **If your laptop is a rebrand of this same
chassis from a different seller (e.g. in the UK, PC Specialist and others resell TongFang/Uniwill
barebones under their own model names — this repo does not confirm any specific one of those
sells `GM6IXxB` specifically, so verify your own hardware below rather than assuming from the
seller's name alone), this may well apply to you too — TUXEDO's own driver already recognizes
`GM6IXxB` under two of its own real board names (`GM6IXxB_MB1`/`GM6IXxB_MB2`), so if your board
reports one of those directly, you don't even need this fork's patches — they exist because our
specific unit's board strings were overwritten by its reseller instead.**

## Is this the right chassis for your device?

Before using any of this, confirm your hardware actually matches, rather than assuming from a
similar model name or reseller:

```
cat /sys/class/dmi/id/board_name /sys/class/dmi/id/sys_vendor /sys/class/dmi/id/product_name
ls /sys/bus/wmi/devices/ | grep -E "ABBC0F"   # Uniwill/WMI GUID block present?
sudo dmesg | grep -i "EC Barebone ID"          # after loading tuxedo_keyboard with dynamic debug on
```

If `board_name` already reports `GM6IXxB_MB1` or `GM6IXxB_MB2` directly, use TUXEDO's own
upstream `tuxedo-drivers` unmodified — no fork needed. This fork's patches match specifically on
`DMI_SYS_VENDOR="ELUKTRONICS"` + `DMI_BOARD_NAME` containing `"HYDROC-16"` (this exact reseller's
overwritten strings). If your board reports different strings but you believe it's the same
`GM6IXxB` chassis under a different rebrand, these DMI matches won't activate for you as-is — see
the commit history for the pattern used (e.g. `cf4cb77`, `7cc0dff`, `ee045b2`) to add a matching
entry for your own board's actual strings, after independently confirming your chassis identity
(same DMI/WMI/barebone-ID checks above). Don't assume a shared reseller, model name, or even
chassis family guarantees identical EC firmware behavior — see "Known limitations" below for why
that assumption failed badly for at least one feature on this exact unit, and may well differ
again on yours.

## What's confirmed working (visually verified on real hardware)

- Per-key RGB keyboard backlight (126 individually-addressable keys) and light bar, via the
  ITE8291/ITE8233 USB controllers (`ite_8291`/`ite_8291_lb`) — including a color-calibration fix
  for a real, visible magenta tint on this panel.
- TUXEDO Control Center (TCC) integration — fan control, keyboard backlight, TDP presets.
- `ac_auto_boot`/`usb_powershare` toggles (present and EC-backed; real-world on/off behavior not
  further tested).
- Suspend/resume (s2idle) — clean, verified multiple times.

## Known limitations — read before relying on this for battery health

**The "Stationary"/"Balanced" battery charging-profile feature does not actually cap charging on
this unit.** The relevant EC register accepts writes and reads back correctly (confirmed via two
independent open-source drivers using the identical register/encoding, and cross-checked against
genuine Eluktronics Windows software persisting the same register across a reboot into Linux), but
the physical charging current never throttles — verified via `current_now` across multiple full
charge cycles, well past the intended threshold. This appears to be a real EC-firmware-level gap,
not a bug in this driver, and matches an open, unresolved bug report against TUXEDO's own
Stellaris hardware plus an explicit "some devices do not properly implement the charging threshold
interface" caveat documented by the independent `uniwill-laptop` driver
(https://github.com/Wer-Wolf/uniwill-laptop). If you need a hard charge limit, don't rely on this
feature — manually unplug around your target percentage instead.

The TDP/power-limit table (matched to TUXEDO's `GM6IXxB_MB2` motherboard revision) is an
unverified, deliberately conservative guess — this unit's actual revision (`MB1` vs `MB2`) was
never conclusively determined, and no sustained thermal/power test has confirmed the chosen
values are correct for this specific board.

## Installing

`install.sh` (in the repo root) reproduces a full setup on a fresh Ubuntu 26.04 ("resolute")
install: build prerequisites, a permanent apt pin blocking TUXEDO's stock `tuxedo-drivers`
package (would silently conflict with this fork's modules), this fork built and installed via
DKMS, and TUXEDO Control Center installed from a pinned, independently-archived binary release
(not TUXEDO's live apt repo, to stay isolated from any future unreviewed TCC update) — see
`arbitrary-string/tuxedo-control-center-archive` for that archive and its source mirror. Run it,
then reboot to confirm the driver autoloads cleanly from a cold boot.

It's a single installer for every machine this repo supports, not one script per machine — it
auto-detects the DMI identity it's running on, prints what it recognized, and warns (rather than
failing partway through) if the hardware isn't one this repo has a local patch for yet. It's also
safe to re-run.

This has been tested end-to-end, including a full simulated fresh-machine run (not just written
and assumed correct).

## Features implemented by this driver package
- Fn-keys
- Keyboard backlight
- Fan control
- Power control
- Other sensors
- Hardware specific userspace quirks

## Modules included in this package
- clevo_acpi
- clevo_wmi
- tuxedo_keyboard
- uniwill_wmi
- ite_8291
- ite_8291_lb
- ite_8297
- ite_829x
- tuxedo_io
- tuxedo_compatibility_check
- tuxedo_nb05_keyboard
- tuxedo_nb05_power_profiles
- tuxedo_nb05_ec
- tuxedo_nb05_sensors
- tuxedo_nb04_keyboard
- tuxedo_nb04_wmi_ab
- tuxedo_nb04_wmi_bs
- tuxedo_nb04_sensors
- tuxedo_nb04_power_profiles
- tuxedo_nb04_kbd_backlight
- tuxedo_nb05_kbd_backlight
- tuxedo_nb02_nvidia_power_ctrl
- tuxedo_nb05_fan_control
- tuxi_acpi
- tuxedo_tuxi_fan_control
- stk8321
- gxtp7380

# Building and Install

## Dependencies:
All:
- make

`make package-*`:
- [simple-package-creator](https://gitlab.com/tuxedocomputers/development/packages/simple-package-creator)
- [simple-package-tools](https://gitlab.com/tuxedocomputers/development/packages/simple-package-tools)

# Troubleshooting

## The keyboard backlight control and/or touchpad toggle key combinations do not work
For all devices with a touchpad toggle key(-combo) and some devices with keyboard backlight control key-combos the driver does nothing more then to send the corresponding key event to userspace where it is the desktop environments duty to carry out the action. Some smaller desktop environments however don't bind an action to these keys by default so it seems that these keys don't work.

Please refer to your desktop environments documentation on how to set custom keybindings to fix this.

For keyboard brightness control you should use the D-Bus interface of UPower as actions for the key presses.

For touchpad toggle on X11 you can use `xinput` to enable/disable the touchpad, on Wayland the correct way is desktop environment specific.

# Regarding upstreaming of tuxedo-drivers
The code, while perfectly functional, is currently not in an upstreamable state. That being said we started an upstreaming effort and the first small part, the keyboard backlight control for the Sirius 16 Gen 1 & 2, already got accepted.

If you want to hack away at this matter yourself please follow the following precautions and guidelines to avoid breakages on both software and hardware level:
- Involve us in the whole process. Nothing is won if at some point tuxedo-control-center or the dkms variant of tuxedo-drivers stops working. Especially when you send something to the LKML, please set us in the cc.
- We mostly can't share documentation, but we can answer questions.
- Code interacting with the EC, which is most of tuxedo-drivers, can brick devices and therefore must be ensured to only run on compatible and tested devices.
- If you use tuxedo-drivers as a reference or code snippets from it, a "Codeveloped-by:\<name\> \<tuxedo_email\>" must be included in your upstream commit, with \<name\> and \<tuxedo_email\> depending on the actual part of tuxedo-drivers being used. Please talk to us regarding this.
