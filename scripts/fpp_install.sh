#!/bin/bash
set -e

# fpp-FPPMon install script
# Download the platform/version-matched plugin binary, then ask FPP to restart
# so the freshly placed libfpp-FPPMon.so is loaded. set -e keeps a failed
# download from being followed by a restart request that would load nothing.

BASEDIR="$(cd "$(dirname "$0")" && pwd)"

"${BASEDIR}/fetch-binary.sh"

. ${FPPDIR}/scripts/common
setSetting restartFlag 1
