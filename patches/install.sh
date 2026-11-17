#!/bin/sh
# Apply the L861 patches to a LineageOS 16.0 source tree. See common.sh.
. "$(dirname "$0")/common.sh"
failed=0
run_set "" "" $core_dirs
[ "$want_video" = yes ] && run_set "optional-video/" "" $video_dirs
[ "$want_fmradio" = yes ] && run_set "optional-fmradio/" "" $fmradio_dirs
[ "$failed" = 0 ] && echo "All patches applied." || { echo "Some patches FAILED."; exit 1; }
