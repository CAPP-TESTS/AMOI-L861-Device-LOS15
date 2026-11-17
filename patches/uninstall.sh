#!/bin/sh
# Revert every patched project to its checked-out state.
# WARNING: this discards ALL local changes in those projects
# (git reset --hard + git clean), not only these patches.
. "$(dirname "$0")/common.sh"
for dir in $core_dirs $fmradio_dirs; do
	[ -d "$rootdirectory/$dir" ] || continue
	cd "$rootdirectory/$dir" || exit 1
	echo "Reverting $dir ..."
	git reset --hard
	git clean -f -d
done
cd "$rootdirectory" || exit 1
