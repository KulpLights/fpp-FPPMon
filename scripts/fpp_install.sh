#!/bin/bash
set -e

# fpp-FPPMon install script
# Download the platform/version-matched plugin binary. set -e keeps a failed
# download from being followed by a restart request that would load nothing.

BASEDIR="$(cd "$(dirname "$0")" && pwd)"

"${BASEDIR}/fetch-binary.sh"

. ${FPPDIR}/scripts/common

# FPP 10 loads a freshly installed plugin itself: the plugin manager calls
# fppd's load endpoint right after this script returns, so the .so we just
# placed is picked up without an fppd restart. Asking for one there is a
# gratuitous "FPPD needs a restart" banner (and, on a running show, a real
# interruption). Older FPP has no such call, so it still needs the flag.
#
# The presence of that helper in the installed plugin controller is the actual
# capability -- keyed on the code that would do the loading rather than on a
# version number, so a backport is honored and a build without it is not.
PLUGINCTL="${FPPDIR}/www/api/controllers/plugin.php"
if grep -q "FPPDPluginLifecycle" "${PLUGINCTL}" 2>/dev/null; then
    echo "fpp-FPPMon: FPP loads new plugins on its own, no fppd restart requested"
else
    setSetting restartFlag 1
fi
