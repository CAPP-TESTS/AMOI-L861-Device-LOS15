# AMOI L861 — LineageOS 15.1 → 16.0 (Android 9) device tree conversion

Status of the Pie conversion of this tree. The device stays **non-Treble**
(no vendor partition, blobs in `/system/vendor`) and keeps the frozen
**3.10.108** kernel. Nothing here changes the partition table.

## Changes applied in this tree

### Product / build system
- `lineage.mk` renamed to `lineage_L861.mk` (16.0 naming convention),
  now inherits `full_base_telephony.mk` (`aosp_base_telephony.mk` is gone in Pie).
- `AndroidProducts.mk` gained `COMMON_LUNCH_CHOICES`; `vendorsetup.sh`
  (`add_lunch_combo`) removed — 16.0 picks up lunch choices from
  `AndroidProducts.mk`.
- `device.mk`: `PRODUCT_FULL_TREBLE_OVERRIDE := false` (this is the variable
  Pie actually honors; setting `PRODUCT_FULL_TREBLE` in BoardConfig does nothing).
- `BoardConfig.mk`: added `BOARD_VNDK_RUNTIME_DISABLE := true` and explicit
  `TARGET_COPY_OUT_VENDOR := system/vendor`. `BOARD_VNDK_VERSION` is
  intentionally **not** set — that keeps the legacy linker namespace config,
  which is what a non-Treble Pie build needs.

### HIDL (manifest.xml + hidl.mk)
| HAL | 15.1 | 16.0 |
|---|---|---|
| android.hardware.audio | 2.0 | **4.0** (`audio@4.0-impl`, service binary is still `audio@2.0-service`) |
| android.hardware.audio.effect | 2.0 | **4.0** |
| android.hardware.soundtrigger | 2.0 | **2.1** |
| android.hardware.configstore | 1.0 | **1.1** (`configstore@1.1-service`) |
| android.hardware.health | 1.0 | **2.0** (`health@2.0-service` replaces healthd/health@1.0) |
| android.hardware.cas | — | **1.0** added (`cas@1.0-service`, new in the Pie media stack) |

Everything else (camera.provider 2.4 passthrough `legacy/0`, composer 2.1,
gnss 1.0, radio 1.1, keymaster 3.0, wifi 1.0, …) is unchanged and remains
valid on Pie for a legacy (FCM target-level 1/2) device.

### device.mk package cleanup
- Dropped `audio_policy.default` / `audio_policy.stub` (legacy audio policy
  modules removed in Pie; `libaudiopolicymanagerdefault` stays).
- Dropped `Torch` (long gone; flashlight is a QS tile).
- `su` commented out — 16.0 ships root as the separate addonsu zip
  (or build with `WITH_SU=true`).
- `media_profiles.xml` additionally installed as `media_profiles_V1_0.xml`
  (the name the Pie media framework looks up first).

### seccomp
Added `getrandom`, `sched_yield`, `clock_getres` to the mediacodec and
mediaextractor device policies (P libc/ART use them; missing entries kill the
process on first use).

### Charger / health note
Offline charging now runs through `health@2.0-service` + `charger`. The sysfs
paths in BoardConfig (`CHARGING_ENABLED_PATH`, LED paths, …) still apply. If
charge mode misbehaves, a small `libhealthd.mt6795` (BoardHook) may be needed.

### Partition layout: FuelOS only
The tree now targets the FuelOS partition layout only (scatter
`MT6795_Android_scatter_MARK1`, project `ef1682d`); the older compromise
sizes that also fitted the FlyME layout are gone.

| Partition | Scatter size | `BoardConfig.mk` |
|---|---|---|
| boot / recovery | 0x1000000 | 16777216 (unchanged) |
| system | 0xda000000 | 3657433088 (was 1887436800) |
| cache | 0x1a800000 | 444596224 (was 838860800) |
| userdata | 0x64bb80000 | 27040137216 = partition minus 16384 for the crypto footer (was 28415885312) |

The FuelOS layout has no `metadata` partition, so the encryption key
location in `fstab.mt6795` and `twrp.fstab` moved from
`by-name/metadata` to `encryptable=footer`; the meaningless `encryptable=`
flag on `/cache` was dropped. An existing `/data` formatted to the full
partition size has no room for the footer: encryption needs `/data` to be
formatted once (TWRP already formats with `length=-16384`).

## patches/ — re-port status for 16.0

The 15.1 patch set applies to 15.1 sources and **will not apply as-is** to
lineage-16.0. Per-patch plan:

| Patch | 16.0 fate |
|---|---|
| `bionic/0001-bionic-mtk-patch.patch` | **Re-port required.** P bionic changed a lot; take the Pie MTK bionic patch from an existing legacy-MTK 16.0 bringup instead of forward-porting. |
| `frameworks/av/0001-libaudiohal-LEGACY_MTK_AV_BLOB-support.patch` | **Re-port required** against the audio@4.0 libaudiohal layout. |
| `frameworks/av/0002-libmedia-add-MTK-null-functions.patch` | **Re-port required** — libmedia was split up in P (libmediaextractor, libmedia_helper…). |
| `frameworks/av/0003-Disable-usage-of-get_capture_position.patch` | **Re-port** to P AudioFlinger (small). |
| `frameworks/av/0004-AutoscaleOmx.patch` | **Probably droppable** — lineage-16.0 carries `TARGET_OMX_LEGACY_RESCALING` support upstream (flag already set in BoardConfig). Verify, then drop. |
| `frameworks/opt/telephony/0001-RIL.java-add-mtk-ril-requests-unsol-responses.patch` | **Re-port required.** RIL.java was heavily reworked in P. This plus libril is the main RIL workload. |
| `hardware/interfaces/0001-Add-error-message-suppress-option.patch` | **Re-port** to audio@4.0-impl (`SUPPRESS_MTK_AUDIO_BLOB_ERR_MSG`). |
| `hardware/interfaces/0002-Build-flag-misplaced.patch` | Re-check; may be fixed upstream in P. |
| `hardware/interfaces/0002-Workaround-for-MTK-camera-blobs.patch` | **Re-port** to P camera.provider@2.4/device@1.0 impl. |
| `hardware/interfaces/0003-Lower-the-requirement-of-sensor-API-version-to-1.0.patch` | **Re-port** (sensors@1.0-impl still similar in P). |
| `hardware/ril/0001-BOARD_PROVIDES_RILD.patch` | Check lineage-16.0 `hardware/ril` first — Lineage may already honor `BOARD_PROVIDES_RILD`/`BOARD_PROVIDES_LIBRIL`; re-port only if not. |
| `system/core/0001-liblog-Add-__xlog_buf_printf.patch` | **Re-port** (liblog restructured in P). |
| `system/core/0001-restore-support-for-early_suspend.patch` | **Re-port** — still needed with the 3.10 kernel's legacy suspend path. |
| `system/core/0002-gatekeeperd-Add-use-software-gatekeeper-option.patch` | **Re-port** (software gatekeeper still needed). |
| `system/core/0003-O-change-patch.patch` | **Not droppable as first assumed.** Besides enlarging init's `ENV[]`, it adds the MTK `ifc_*` helpers to libnetutils (`ifc_set_txq_state`, `ifc_ccmni_md_cfg`, `ifc_set_throttle`, …) that the MTK RIL uses. The hermes lineage-16.0 tree avoids patching system/core by carrying `ifc_set_txq_state`/`ifc_ccmni_md_cfg` in `mtk/ril/libril/libnetutils.c`; do the same in `hal/libril`, or re-port the libnetutils part. |

Good patch donors: any maintained legacy-MTK lineage-16.0 bringup
(MT6795 `hermes`/Redmi Note 2 trees, and the common mt6735/mt6753 16.0 trees
share most of these patches already ported to Pie).

## Known TODOs that need a full 16.0 source tree / device to verify

1. **sepolicy**: compile against P base policy — expect new neverallow hits
   (use the commented `SELINUX_IGNORE_NEVERALLOWS` + permissive cmdline in
   BoardConfig for first boots, then fix denials properly).
2. **Overlays**: audit `overlay/` and `overlay-lineage/` against P resource
   renames (aapt will error on removed/renamed resources — fix as they appear).
3. **Shims** (`TARGET_LD_SHIM_LIBS` / `libmtk_symbols`): expect new unresolved
   symbols from P `libgui`/`libui`/`libstagefright`; extend the shim as
   runtime linker errors show up in logcat.
4. **Audio policy**: RESOLVED in the Phase-3 vendor/device commits — Pie's
   APM only searches `/odm/etc`, `/vendor/etc`, `/system/etc`, so the vendor
   tree now installs the primary `audio_policy_configuration.xml` into
   `system/vendor/etc/` and device.mk installs the XInclude fragments next
   to it. Verify at runtime that the audio HAL module names in that XML
   match what the MTK audio blob registers.
5. **TARGET_SPECIFIC_HEADER_PATH**: verify still honored on 16.0 (see comment
   in BoardConfig.mk).
6. **dhcpcd/wide-dhcpv6 configs**: still fine on P (external/dhcpcd-6.8 exists);
   these go away in the Q (17.1) hop.
7. **NFC (MTK stack) and FM radio**: build the 15.1 modules against P and
   triage — these are the most likely candidates to be temporarily disabled
   during bringup.
8. **TWRP flags**: recovery section untouched; rebuild TWRP from a
   9.0-compatible twrp tree or keep flashing the existing 8.1 TWRP (it can
   flash Pie zips fine).
