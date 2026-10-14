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
# When the binary actually moved, the running fppd still has the old build and
# has to be told. In order of preference:
#   - FPP says it reloads the plugin itself once the upgrade lands
#     (FPP_RELOADS_PLUGIN=1): nothing to do here.
#   - FPP 10 can unload and load a plugin at runtime but does not do it after an
#     upgrade: ask it to here. The new .so is a new file (fetch-binary.sh
#     renames it into place), and fppd opens a replaced library under a name of
#     its own, so the new build is what loads -- no restart, no interrupted show.
#   - Anything else (FPP 9, or fppd refusing): the restart flag, so FPP restarts
#     between sequences.
# When the download turns out to be the same build that is already loaded --
# the common case for a git-only upgrade -- nothing changed and there is
# nothing to do.
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

# Same CSP entry fpp_install.sh asks for -- FPP runs this script *instead of*
# re-running the install script, so an install that predates it would otherwise
# never get it. Adding an allowed domain again is a no-op.
MACP="${FPPDIR}/scripts/ManageApacheContentPolicy.sh"
if [ -x "${MACP}" ]; then
    (cd /tmp && "${MACP}" add connect-src https://kulplights.com) || \
        echo "fpp-FPPMon: could not add the CSP entry for kulplights.com"
fi

# Unload then load through the documented proxy; true only if both succeed.
# fppd not answering at all counts as success: it is not running, and loads
# the new build when it starts.
reload_in_fppd() {
    local base="http://localhost/api/fppd/plugin/$(basename "${BASEDIR}")"
    local action resp
    for action in unload load; do
        if ! resp="$(curl -s --max-time 40 -X POST "${base}/${action}")"; then
            [ "${action}" = "unload" ] && return 0
            return 1
        fi
        case "${resp}" in
            *'"Status":"OK"'*) ;;
            *) echo "fpp-FPPMon: fppd could not ${action} the plugin: ${resp}"; return 1 ;;
        esac
    done
}

if [ "${BEFORE}" = "${AFTER}" ]; then
    echo "fpp-FPPMon: binary unchanged, no fppd restart requested"
elif [ "${FPP_RELOADS_PLUGIN}" = "1" ]; then
    echo "fpp-FPPMon: FPP reloads the updated plugin itself"
elif grep -q "FPPDPluginLifecycle" "${FPPDIR}/www/api/controllers/plugin.php" 2>/dev/null && reload_in_fppd; then
    echo "fpp-FPPMon: reloaded the updated plugin in fppd, no restart needed"
else
    setSetting restartFlag 1
fi

exit $RC
