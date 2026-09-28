# Draft: power-profiles-daemon — emulated power-saver switches itself back to balanced

For a merge request at
<https://gitlab.freedesktop.org/upower/power-profiles-daemon> (fork, push the
patch, open the MR; mention #187). The patch applies with `git am` to main
`09eeb34` (2026-09) and the full test suite passes with it (129/129).

Patch: [`0005-platform-profile-Don-t-read-an-emulated-power-saver-.patch`](0005-platform-profile-Don-t-read-an-emulated-power-saver-.patch)
(no Signed-off-by; the sender adds their own if the project wants one).

Until this is in a release, `power-profile-bridge` works around it by
starting the daemon with `--block-driver=platform_profile`.

---

**Title:** platform-profile: Don't read an emulated power-saver back as balanced

When `platform_profile_choices` has no `low-power`, `quiet` or `cool`,
power-saver is emulated by writing `balanced`. Going from performance to
power-saver then lands on balanced within a second: the daemon switches itself
back with reason `internal`. Going from balanced to power-saver works, because
nothing is written.

`ppd_driver_platform_profile_activate_profile()` blocks the file monitor's
handler around its write and stores `PPD_PROFILE_POWER_SAVER` afterwards, but
GFileMonitor dispatches the change event later from the main loop, after the
handler is unblocked. `update_acpi_platform_profile_state()` then reads
`balanced`, sees it differ from the power-saver it just stored and emits
profile-changed. The block/unblock around the write never suppresses anything.

#187 reported this symptom on an HP Omen and was closed by 3b8066c5, which maps
hp-wmi's `cool` choice to power-saver. That removes the emulation on those
machines, but the emulation path itself is unchanged on main.

It happens on any machine whose legacy choices lack a low-power option. That
includes machines with several platform-profile handlers, where the legacy
file only lists the choices they all share. On an ASUS
ExpertBook Ultra B9406CAA (Panther Lake, Linux 7.2), Intel's "SoC Power
Slider" offers `low-power balanced performance` and asus-wmi offers
`quiet balanced performance`, so the legacy file offers `balanced performance`:

```
$ powerprofilesctl set performance; powerprofilesctl set power-saver; sleep 0.5; powerprofilesctl get
balanced
```

The same sequence in the new integration test, on unmodified main:

```
Core           Setting active profile 'power-saver' for reason 'user' (current: 'performance')
Utils          Writing 'balanced' to '.../sys/firmware/acpi/platform_profile'
PlatformDriver Successfully switched to profile power-saver
PlatformDriver /sys/firmware/acpi/platform_profile changed (0)
PlatformDriver /sys/firmware/acpi/platform_profile changed (1)
PlatformDriver ACPI performance_profile is now 'balanced', so profile is detected as balanced
Core           Driver 'platform_profile' switched internally to profile 'balanced' (current: 'power-saver')
Core           Setting active profile 'balanced' for reason 'internal' (current: 'power-saver')
AssertionError: property 'ActiveProfile' is not 'power-saver', but 'balanced'
```

The fix ignores reading `balanced` back while power-saver is being emulated;
any other change of the file is still followed. `test_emulated_power_saver`
covers performance → power-saver (stays), → balanced, → performance, and an
external write while emulating. It waits for the daemon's own "is now
'balanced'" log line, so it fails deterministically on main (2/2, and 16/16
with `--repeat`) and passes with the fix (40/40 with `--repeat 20`). Full
suite: 127/127 on main, 129/129 with the patch.

An alternative with the same test results: in `activate_profile()`, store what
the firmware now reports, `acpi_platform_profile_value_to_profile
(platform_profile_value)`, instead of `profile`. The balanced → power-saver
path already ends in that state, and it avoids one redundant write of
`balanced` when leaving an emulated power-saver for balanced.

Separately, `acpi_platform_profile_value_to_profile()` matches
`balanced_performance` with an underscore, while the kernel's name is
`balanced-performance`, so that choice would hit `g_return_val_if_reached`.
Not changed here.
