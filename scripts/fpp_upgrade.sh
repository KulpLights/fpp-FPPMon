#!/bin/bash
#############################################################################
# FPP plugin-manager upgrade hook, run after `git pull` when the user clicks
# Upgrade. fetch-binary.sh skips the download when the cached marker (FPP major
# plus plugin ABI version) matches (its job at boot is "make sure a *loadable*
# binary is present", not "get the newest one"), so an upgrade must clear the
# marker to force a fresh download of the latest released libfpp-FPPMon.so.
#
# This is also the recovery path when a release is republished *after* an FPP
# ABI bump has already been fetched: the marker matches but the binary is stale,
# so only an explicit upgrade (or fpp_update_check.sh reporting a newer build
# stamp, which is what puts the Upgrade button in front of the user) shifts it.
#############################################################################

BASEDIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"

rm -f "${BASEDIR}/.binary-major"
"${BASEDIR}/scripts/fetch-binary.sh"
RC=$?

. ${FPPDIR}/scripts/common
setSetting restartFlag 1

exit $RC
