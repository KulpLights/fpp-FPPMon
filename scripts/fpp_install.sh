#!/bin/bash
set -e

# fpp-FPPMon install script
# Download the platform/version-matched plugin binary. set -e keeps a failed
# download from being followed by a restart request that would load nothing.

BASEDIR="$(cd "$(dirname "$0")" && pwd)"

"${BASEDIR}/fetch-binary.sh"

. ${FPPDIR}/scripts/common

# Allow the config page's browser-side login POST to reach kulplights.com.
# FPP serves plugin pages under a Content-Security-Policy whose connect-src is
# 'self' plus a built-in list; kulplights.com happens to be on that list today,
# but it is not FPP's own service and there is no promise it stays there, so ask
# for it explicitly rather than relying on someone else's default. Adding a
# domain that is already allowed is a no-op, and fpp_uninstall.sh removes it.
# Declared in pluginInfo.json's privacy block (PLUGIN_GUIDELINES.md 14.1).
#
# Run from /tmp: the helper builds its new JSON as ./tmp.json in the caller's
# working directory, and a failed jq would leave that behind in the plugin dir.
MACP="${FPPDIR}/scripts/ManageApacheContentPolicy.sh"
if [ -x "${MACP}" ]; then
    (cd /tmp && "${MACP}" add connect-src https://kulplights.com) || \
        echo "fpp-FPPMon: could not add the CSP entry for kulplights.com"
fi

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
