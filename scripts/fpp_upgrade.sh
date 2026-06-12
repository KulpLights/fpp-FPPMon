#!/bin/bash
#############################################################################
# FPP plugin-manager upgrade hook, run after `git pull` when the user clicks
# Upgrade. fetch-binary.sh skips the download when the cached FPP-major
# marker matches (its job at boot is "make sure A binary is present", not
# "get the newest one"), so an upgrade must clear the marker to force a
# fresh download of the latest released libfpp-FPPMon.so.
#############################################################################

BASEDIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"

rm -f "${BASEDIR}/.binary-major"
"${BASEDIR}/scripts/fetch-binary.sh"
RC=$?

. ${FPPDIR}/scripts/common
setSetting restartFlag 1

exit $RC
