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
| android.hardware.health | 1.0 | **2.0** (`health@2.0-service.override`, the variant that replaces healthd) |
| android.hardware.cas | — | **1.0** added (`cas@1.0-service`, new in the Pie media stack) |
| android.hardware.wifi | 1.0 | **1.2** |
| android.hardware.wifi.supplicant | 1.0 | **1.1** |
| android.hardware.wifi.hostapd | — | **1.0** added (Pie controls hostapd over HIDL; needed for the hotspot) |

Everything else (camera.provider 2.4 passthrough `legacy/0`, composer 2.1,
gnss 1.0, radio 1.1, keymaster 3.0, …) is unchanged. The extra HALs this
device declares compared to hermes (NFC, IR, fingerprint, MTK radio/IMS, …)
are kept on purpose: the L861 has hardware hermes lacks.

Audio 4.0 vs 2.0: both work on Pie (libaudiohal tries 4.0, then 2.0). The
hermes trees ran 4.0 for 13 months; its lineage-16.0 branch went back to 2.0
in its last, unexplained commit. The framework matrices require audio 2.0 up
to FCM level 2 and 4.0 from level 3, and hermes declares `target-level="2"`,
which is the likely reason. This tree declares no target level and keeps 4.0;
switching to 2.0 is a four-line change in `hidl.mk` + `manifest.xml`.

### device.mk package cleanup
- Dropped `audio_policy.default` / `audio_policy.stub` (legacy audio policy
  modules removed in Pie; `libaudiopolicymanagerdefault` stays).
- Dropped `Torch` (long gone; flashlight is a QS tile).
- `su` commented out — 16.0 ships root as the separate addonsu zip
  (or build with `WITH_SU=true`).
- `media_profiles.xml` additionally installed as `media_profiles_V1_0.xml`
  (the name the Pie media framework looks up first).

### seccomp
The device files are *additions* loaded after the base policy
(`/system/etc/seccomp_policy/*.policy` + `/vendor/etc/seccomp_policy/*.policy`,
see `main_codecservice.cpp` / `main_extractorservice.cpp`). Added the entries
the hermes lineage-16.0 tree (same SoC, MTK M blobs) carries and this tree
lacked: `sched_getaffinity`, `setrlimit`, `setsockopt`, `tee` for mediacodec
and `setrlimit` for mediaextractor. An earlier revision of this tree added
`getrandom`/`sched_yield`/`clock_getres` instead; that was unfounded
(`getrandom` is already in the base policies) and has been removed.

### Charger / health note
Offline charging now runs through `health@2.0-service.override` + `charger`. The sysfs
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

## patches/ — status against the real lineage-16.0 sources

Checked with `git apply --check` against LineageOS `frameworks/av`,
`hardware/interfaces` and `system/core` (branch `lineage-16.0`). The other
target projects (bionic, frameworks/opt/telephony, hardware/ril) are not
verified yet.

### L861 15.1 patches

| Patch | Applies to 16.0? | Plan |
|---|---|---|
| `frameworks/av/0001-libaudiohal-LEGACY_MTK_AV_BLOB-support.patch` | no (`libaudiohal/Android.mk` is gone) | re-port only if audio fails without it; hermes needs no audio patch at all |
| `frameworks/av/0002-libmedia-add-MTK-null-functions.patch` | no | re-port, or move the stubs into `libmtk_symbols` |
| `frameworks/av/0003-Disable-usage-of-get_capture_position.patch` | **yes** | keep |
| `frameworks/av/0004-AutoscaleOmx.patch` | no | **drop**: 16.0 has `TARGET_OMX_LEGACY_RESCALING` natively (soong variable `Target_omx_legacy_rescaling`), already set in BoardConfig |
| `hardware/interfaces/0001-Add-error-message-suppress-option.patch`, `0002-Build-flag-misplaced.patch` | no (`audio/2.0/default/Android.mk` is gone) | re-port only if the log spam matters |
| `hardware/interfaces/0002-Workaround-for-MTK-camera-blobs.patch` | **yes** | keep |
| `hardware/interfaces/0003-Lower-the-requirement-of-sensor-API-version-to-1.0.patch` | **yes** | keep |
| `system/core/0001-liblog-Add-__xlog_buf_printf.patch` | **yes** | keep |
| `system/core/0001-restore-support-for-early_suspend.patch` | no | replace with hermes `0001-libsuspend-readd-earlysuspend.patch` (applies) |
| `system/core/0002-gatekeeperd-Add-use-software-gatekeeper-option.patch` | **yes** | keep |
| `system/core/0003-O-change-patch.patch` | no | **not droppable**: besides enlarging init's `ENV[]` it adds the MTK `ifc_*` helpers to libnetutils that the MTK RIL uses. hermes carries `ifc_set_txq_state`/`ifc_ccmni_md_cfg` in `mtk/ril/libril/libnetutils.c` instead of patching system/core; do the same in `hal/libril`, or re-port the libnetutils part |
| `bionic/0001-bionic-mtk-patch.patch` | not checked | exports `__pthread_gettid`; hermes solves this class of problem with shims |
| `frameworks/opt/telephony/0001-RIL.java-…` | not checked | the hermes Pie patch adds the very same 50 lines; use that one |
| `hardware/ril/0001-BOARD_PROVIDES_RILD.patch` | not checked | hermes has no such patch and only sets `BOARD_PROVIDES_LIBRIL` |

### hermes lineage-16.0 patches

All seven `frameworks/av` patches apply, also in sequence, and the six
non-camera ones apply without `0003-MTK-camera-support`. The
`hardware/interfaces` fence-leak patch and the `system/core` early-suspend
patch apply too.

To adopt: early suspend, HWC2On1Adapter fence leak, `0001-Disable-vndk-for-omx`,
and (not yet apply-checked, their projects are not cloned) the bionic, netd,
frameworks/native and frameworks/base ones. To evaluate on the device: the
video ones (YUV profiles, HEVC, crop info, MTK profiles) — the L861 OMX blobs
are different builds. Not to adopt: `0003-MTK-camera-support` (this tree does
the same through the device library `libcamera_client_mtk`) and the
signature-spoofing part of `frameworks/base/0010`.

## Verified against the lineage-16.0 sources

### BoardConfig flags nothing reads any more
lineage-16.0 has a short, fixed list of Lineage soong variables
(`vendor/lineage/build/soong/soong_config.mk`). Of the flags this tree sets,
it still honors `TARGET_LD_SHIM_LIBS`, `TARGET_SPECIFIC_CAMERA_PARAMETER_LIBRARY`,
`TARGET_OMX_LEGACY_RESCALING`, `TARGET_SPECIFIC_HEADER_PATH`,
`BOARD_VNDK_RUNTIME_DISABLE`, `TARGET_COPY_OUT_VENDOR`,
`USE_XML_AUDIO_POLICY_CONF`. Nothing in build/make, build/soong,
vendor/lineage, frameworks/av, hardware/interfaces or system/core reads:

- `BOARD_GLOBAL_CFLAGS` / `BOARD_GLOBAL_CPPFLAGS` — so `-DMTK_HARDWARE`,
  `-DCOMPAT_SENSORS_M`, `-DNO_SENSOR_PERMISSION_CHECK`,
  `-DDISABLE_HW_ID_MATCH_CHECK`, `-DADD_LEGACY_ACQUIRE_BUFFER_SYMBOL`,
  `-DDISABLE_ASHMEM_TRACKING`, … reach no compiler. Any behavior that depended
  on them must come from a patch or from the module's own flags.
- `BOARD_USES_MTK_HARDWARE` / `BOARD_HAS_MTK_HARDWARE` (no `uses_mtk_hardware`
  soong variable).
- the camera flags `TARGET_USES_NON_TREBLE_CAMERA`,
  `TARGET_NEEDS_LEGACY_CAMERA_HAL1_DYN_NATIVE_HANDLE`,
  `TARGET_CAMERASERVICE_CLOSES_NATIVE_HANDLES`, `TARGET_USE_COMPAT_GRALLOC_ALIGN`,
  `USE_DEVICE_SPECIFIC_CAMERA`.
- `TARGET_NEEDS_TEXT_RELOCATIONS` (harmless: no L861 32-bit blob has text
  relocations), `TARGET_NO_SENSOR_PERMISSION_CHECK`,
  `TARGET_CPU_MEMCPY_OPT_DISABLE`, `BOARD_USE_SOFT_GATEKEEPER` (only the
  re-ported gatekeeperd patch would read it).
- `BOARD_USES_LINEAGE_HARDWARE` / `BOARD_HARDWARE_CLASS`: 16.0 wires lineagehw
  Java classes through `JAVA_SOURCE_OVERLAYS`. Not confirmed yet
  (hardware/lineage is not cloned): until then `lineagehw/` may be ignored.

`BOARD_PROVIDES_LIBRIL`/`BOARD_PROVIDES_RILD` live in hardware/ril, not
checked yet.

### Camera
The only legacy-camera switch left in 16.0 is `TARGET_HAS_LEGACY_CAMERA_HAL1`,
which builds the camera service into mediaserver (`-DNO_CAMERA_SERVER`, no
cameraserver binary). hermes uses it. This tree does not set it and ships its
own `cameraserver.rc`. The HAL1 video-recording behaviors the two
native-handle flags provided in 15.1 have no 16.0 counterpart. Open decision,
to be taken on the device: separate cameraserver as today, or the hermes
layout.

`TARGET_SPECIFIC_CAMERA_PARAMETER_LIBRARY := libcamera_client_mtk` is still
supported: 16.0 links that static library into `libcamera_client` in place of
the generic `CameraParameters.cpp`.

### Build errors found by reading the sources
- `hal/libcamera_client_mtk/Android.bp` used
  `product_variables.lineage.uses_mtk_hardware`, which does not exist in 16.0
  (an unknown property is a soong error). Replaced with an unconditional
  `-DMTK_HARDWARE`.

### Confirmed
- `media_profiles_V1_0.xml`: 16.0 searches `odm/etc/media_profiles_V1_0.xml`,
  `vendor/etc/media_profiles_V1_0.xml`, `system/etc/media_profiles.xml` only,
  so the 15.1 location `vendor/etc/media_profiles.xml` would not be read.
- `encryptable=footer` is supported by fs_mgr.
- `TARGET_SPECIFIC_HEADER_PATH` is still read by build/make and build/soong.

## Known TODOs that need a full 16.0 source tree / device to verify

1. **sepolicy**: compile against P base policy — expect new neverallow hits
   (use the commented `SELINUX_IGNORE_NEVERALLOWS` + permissive cmdline in
   BoardConfig for first boots, then fix denials properly).
2. **Overlays**: audit `overlay/` and `overlay-lineage/` against P resource
   renames (aapt will error on removed/renamed resources — fix as they appear).
3. **Shims** (`TARGET_LD_SHIM_LIBS` / `libmtk_symbols`): expect new unresolved
   symbols from P `libgui`/`libui`/`libstagefright`; extend the shim as
   runtime linker errors show up in logcat.
4. **Audio policy**: nothing to do. 16.0 searches `/odm/etc`,
   `/vendor/etc/audio`, `/vendor/etc`, `/system/etc`
   (`AudioPolicyManager.cpp`, `kConfigLocationList`), so the vendor blob in
   `vendor/etc/audio/` and the fragments device.mk installs next to it are
   found as they are. An earlier revision of this tree claimed
   `/vendor/etc/audio` was not searched on Pie and added duplicate copies in
   `vendor/etc/`; that was wrong and the copies have been removed. Still to
   verify at runtime: that the HAL module names in that XML match what the MTK
   audio blob registers.
5. **TARGET_SPECIFIC_HEADER_PATH**: resolved, still honored on 16.0.
6. **dhcpcd/wide-dhcpv6 configs**: still fine on P (external/dhcpcd-6.8 exists);
   these go away in the Q (17.1) hop.
7. **NFC (MTK stack) and FM radio**: build the 15.1 modules against P and
   triage — these are the most likely candidates to be temporarily disabled
   during bringup.
8. **TWRP flags**: recovery section untouched; rebuild TWRP from a
   9.0-compatible twrp tree or keep flashing the existing 8.1 TWRP (it can
   flash Pie zips fine).
