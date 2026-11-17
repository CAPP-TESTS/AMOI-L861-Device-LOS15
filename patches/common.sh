# Shared by install.sh / check.sh / uninstall.sh. Run from the root of the
# LineageOS 16.0 source tree:   sh device/openstone/L861/patches/install.sh
#
# Patch sets:
#   (default)  core set, needed to build and boot
#   video      optional-video   : extra MTK video patches (YUV profiles, HEVC,
#                                 OMX crop info, MTK media profiles)
#   fmradio    optional-fmradio : build fix for packages/apps/FMRadio
# Example:     sh device/openstone/L861/patches/install.sh video

rootdirectory="$PWD"
patchroot="$rootdirectory/device/openstone/L861/patches"

core_dirs="bionic frameworks/av frameworks/base frameworks/native frameworks/opt/telephony hardware/interfaces system/core system/netd"
video_dirs="frameworks/av frameworks/native"
fmradio_dirs="packages/apps/FMRadio"

want_video=no
want_fmradio=no
for arg in "$@"; do
	case "$arg" in
		video) want_video=yes ;;
		fmradio) want_fmradio=yes ;;
		*) echo "unknown option: $arg (use: video, fmradio)"; exit 2 ;;
	esac
done

# run_set <subdir-of-patches> <git apply options> <project dirs...>
run_set() {
	set_dir="$1"; apply_opts="$2"; shift 2
	for dir in "$@"; do
		if [ ! -d "$rootdirectory/$dir" ]; then
			echo "MISSING project $dir"; failed=1; continue
		fi
		cd "$rootdirectory/$dir" || exit 1
		for p in "$patchroot/$set_dir$dir"/*.patch; do
			[ -f "$p" ] || continue
			if git apply $apply_opts "$p"; then
				echo "ok      $dir: $(basename "$p")"
			else
				echo "FAILED  $dir: $(basename "$p")"; failed=1
			fi
		done
	done
	cd "$rootdirectory" || exit 1
}
