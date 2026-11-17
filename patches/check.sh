#!/bin/sh
# Dry run: report which patches of each set would apply to a pristine tree,
# without changing anything. Each patch is tested on its own, so a patch
# that depends on an earlier one in the same project can report FAILED here
# and still apply with install.sh. See common.sh.
. "$(dirname "$0")/common.sh"
failed=0
run_set "" "--check" $core_dirs
[ "$want_video" = yes ] && run_set "optional-video/" "--check" $video_dirs
[ "$want_fmradio" = yes ] && run_set "optional-fmradio/" "--check" $fmradio_dirs
[ "$failed" = 0 ] && echo "All patches would apply." || { echo "Some patches would FAIL."; exit 1; }
