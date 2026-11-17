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

## patches/ — the 16.0 set

`patches/` now holds the set for lineage-16.0; see `patches/README` for the
full list with the origin of each patch. `install.sh`, `check.sh` and
`uninstall.sh` were run against the LineageOS `lineage-16.0` branches of
bionic, frameworks/av, frameworks/base, frameworks/native,
frameworks/opt/telephony, hardware/interfaces, system/core, system/netd and
packages/apps/FMRadio: all 17 core patches and the 6 optional ones apply in
order, and uninstall restores the projects. Nothing has been compiled.

- **Core (17):** 6 carried over unchanged from the 15.1 set (bionic
  `__pthread_gettid`, `get_capture_position`, MTK camera workaround, sensor
  API 1.0, xlog, software gatekeeper) and 11 from the hermes lineage-16.0
  tree (OMX without VNDK, ACodec MTK basics, hardware bitmaps, `ged` in
  zygote, `presentOrValidate`, gralloc usage bits, RIL.java, HWC2On1Adapter
  fence leak, early suspend, two netd ones).
- **optional-video (5)** and **optional-fmradio (1):** hermes patches to
  enable by name once tested on the device.
- **`patches/lineage-15.1/`:** the nine 15.1 patches not carried over, kept
  for reference. Seven do not apply to 16.0; the audio ones are only worth
  re-porting if audio fails (hermes needs none).

Replaced rather than re-ported:
- `system/core/0003-O-change-patch`: the two MTK helpers the RIL blobs
  import (`ifc_set_txq_state`, `ifc_ccmni_md_cfg` — the only non-standard
  `ifc_*` symbols any L861 blob needs) are now built into `hal/libril`
  (`libnetutils.c`, as hermes does). `ifc_set_throttle` is only called from
  `hal/bwc` under `FLAG_SUPPORT_MODEM_SCALE`, which is not defined. The
  `ENV[]` enlargement has no target any more: Pie init has no fixed-size
  environment array.
- `hardware/ril/0001-BOARD_PROVIDES_RILD`: `ENABLE_VENDOR_RIL_SERVICE` in
  BoardConfig.

Not taken from hermes: its camera patch (this tree uses the device library
`libcamera_client_mtk`), the signature-spoofing patch, and its two bionic
patches (its own install script does not apply them; one does not apply to
16.0 because LineageOS bionic already has that behavior, the other reads a
phh-specific property).

### hal/libril and hal/rild compared with hermes and with hardware/ril 16.0

No Pie port is needed. The upstream lineage-16.0 libril still speaks only
`android.hardware.radio@1.0`/`@1.1`, like this one, and the 15.1 → 16.0
upstream changes are internal (const-correctness, NITZ locking, an OEM-hook
switch, MNC digit handling); they do not change what the framework or the
MTK RIL blob see. The hermes lineage-16.0 tree builds the same sources:
`include/telephony/ril.h` and the prebuilt `rild-prop-md1.a` are
byte-identical to the ones here, 15 of 20 libril files are identical, and
`rild.c` differs in 23 lines once whitespace is ignored (const qualifiers,
comments, a property name that only applies to Treble builds).

The 244 + 112 differing lines in `ril_service.cpp`/`ril.cpp` are not Pie
adaptations but hermes's own changes. Ported, because they are plain fixes:
- `getOperatorResponse`: three `==` typed where `=` was meant, so the short
  operator name was never set.
- `copyHidlStringToRil` and the radio-capability UUID copy use `strlcpy`;
  on truncation the buffer is freed and an error response is sent.
- `registerService` stores the vendor callbacks before the services are
  registered instead of after (the order hardware/ril 16.0 uses).
- `sap_service.cpp`: NULL check on the decoded message (also in
  hardware/ril 16.0).

Not ported, because they change behavior and are hermes's own choices:
relaxed response-length checks (`!= sizeof(int)` → `% sizeof(int) != 0`,
`!= 2` → `< 2`; upstream 16.0 keeps the strict ones), the reworked IMEI /
device-identity handling, the single-dialog USSD hack, the one-time modem
reset when the second SIM slot connects, and the disabled
`RIL_UNSOL_STK_CC_ALPHA_NOTIFY`. hermes also hard-codes two SIMs, while this
tree sets `SIM_COUNT := 1`.

`hal/libril/Android.mk` no longer links `vendor.mediatek.hardware.radio@1.1`,
`@2.0` and `.deprecated@1.1`: nothing in libril uses them and no module with
those names exists in the device, vendor or kernel trees. `hidl.mk` still
lists them in `PRODUCT_PACKAGES`.

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
  `-DDISABLE_ASHMEM_TRACKING`, … reach no compiler. It would not matter if
  they did: none of these defines is referenced anywhere in 16.0
  frameworks/native, frameworks/av, bionic, system/core or
  hardware/interfaces. Whatever they switched on in 15.1 (sensor
  compatibility in particular) has no 16.0 counterpart and must come from a
  patch if it turns out to be needed.
- `BOARD_USES_MTK_HARDWARE` / `BOARD_HAS_MTK_HARDWARE` on the platform side
  (no `uses_mtk_hardware` soong variable). They stay set: this tree's own
  `hal/libril` and `hal/libcamera_client_mtk` makefiles read them, like
  `BOARD_PROVIDES_RILD` (`hal/rild`) and `USE_MTK_CAMERA_WRAPPER`.
- the camera flags `TARGET_USES_NON_TREBLE_CAMERA`,
  `TARGET_NEEDS_LEGACY_CAMERA_HAL1_DYN_NATIVE_HANDLE`,
  `TARGET_CAMERASERVICE_CLOSES_NATIVE_HANDLES`, `TARGET_USE_COMPAT_GRALLOC_ALIGN`,
  `USE_DEVICE_SPECIFIC_CAMERA`.
- `TARGET_NEEDS_TEXT_RELOCATIONS` (harmless: no L861 32-bit blob has text
  relocations), `TARGET_NO_SENSOR_PERMISSION_CHECK`,
  `TARGET_CPU_MEMCPY_OPT_DISABLE`, `BOARD_USE_SOFT_GATEKEEPER` (only the
  re-ported gatekeeperd patch would read it).
- `BOARD_USES_LINEAGE_HARDWARE` / `BOARD_HARDWARE_CLASS`: see lineagehw below.

### RIL
hardware/ril 16.0 reads `BOARD_PROVIDES_LIBRIL` (libril) and
`ENABLE_VENDOR_RIL_SERVICE` (rild), not `BOARD_PROVIDES_RILD`. Without
`ENABLE_VENDOR_RIL_SERVICE := true` the platform rild and this tree's
`hal/rild` would both define a `rild` module. Now set in BoardConfig.

### lineagehw
16.0 replaces classes of `hardware/lineage/lineagehw` through
`JAVA_SOURCE_OVERLAYS` (`<module>|<dir>|<glob>`), matching files by their
path inside the module (`src/org/lineageos/hardware/X.java`). The old layout
(`lineagehw/org/lineageos/hardware/X.java` + `BOARD_HARDWARE_CLASS`) is
ignored. The four classes that still exist in 16.0 and have identical public
signatures (`DisplayColorCalibration`, `HighTouchSensitivity`, `KeyDisabler`,
`VibratorHW`) moved to `lineagehw/src/org/lineageos/hardware/` and
BoardConfig sets `JAVA_SOURCE_OVERLAYS` with the glob `src/**/*.java`.
`UniqueDeviceId`, `PersistentStorage` and `util/FileUtils` have no 16.0
counterpart; they stay in the old location, outside the glob, unused.
`DisplayColorCalibration` uses
`com.android.server.display.DisplayTransformManager` from frameworks/base;
checked against Pie: the class, `LEVEL_COLOR_MATRIX_NIGHT_DISPLAY` and
`setColorMatrix(int, float[])` are all still there.

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
2. **Overlays**: the `frameworks/base` overlays were checked against the Pie
   resources: 52 of 56 entries still exist. Four are gone
   (`config_dozeAfterScreenOff`, `config_wifi_wakeup_available`,
   `config_ignoreRssnrSignalLevel`, SystemUI `doze_pulse_on_pick_up`) and the
   `packages/Keyguard` overlay has no target; the build passes
   `--auto-add-overlay`, so these are dead entries, not errors. The overlays
   for Settings, Dialer, Bluetooth, Snap, Telephony and lineage-sdk are not
   checked (projects not cloned).
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
