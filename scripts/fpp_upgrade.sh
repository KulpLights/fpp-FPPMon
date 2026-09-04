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
#
# Unlike install, an upgrade genuinely needs an fppd restart -- but only when
# the binary actually moved. FPP does not reload a plugin after an upgrade, and
# this plugin deliberately does not declare FPP_PLUGIN_SUPPORTS_UNLOAD (its
# drogon WebSocketClient can queue handlers onto a trantor loop past shutdown,
# so the library is never dlclose()d), which means the running code stays the
# old build until fppd restarts. When the download turns out to be the same
# build that is already loaded -- the common case for a git-only upgrade --
# nothing changed and there is nothing to restart for.
#############################################################################

BASEDIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
TARGET="${BASEDIR}/libfpp-FPPMon.so"

sha_of() {
    [ -s "$1" ] || return 0
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | cut -d' ' -f1
    else
        shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1
    fi
}

BEFORE="$(sha_of "${TARGET}")"

rm -f "${BASEDIR}/.binary-major"
"${BASEDIR}/scripts/fetch-binary.sh"
RC=$?

AFTER="$(sha_of "${TARGET}")"

. ${FPPDIR}/scripts/common

if [ "${BEFORE}" != "${AFTER}" ]; then
    setSetting restartFlag 1
else
    echo "fpp-FPPMon: binary unchanged, no fppd restart requested"
fi

exit $RC
