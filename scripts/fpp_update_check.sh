#!/bin/bash
#############################################################################
# FPP plugin-manager update check (see PluginHasUpdates in FPP's plugin
# API). This repo's git history rarely changes -- the actual plugin is a
# prebuilt libfpp-FPPMon.so attached to a rolling release tag -- so the git
# check alone can't see binary updates. Compare the build version burned
# into the installed .so ("FPPMon-build:<ver>") against the "version:" line
# CI stamps into the rolling release's notes.
#
# This is also where the Release Notes cache gets filled: the rolling release
# carries a "releasenotes.txt" asset, and scripts/fpp_releasenotes.sh -- which
# runs as the unprivileged web user with the user waiting on a dialog, so it
# may not download anything -- just prints what this script left behind.
#
# Contract with FPP: last line of stdout is "1" (update available) or "0";
# a non-zero exit status means "could not check" and is ignored.
#############################################################################

BASEDIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
FPPDIR="${FPPDIR:-/opt/fpp}"
REPO_API="https://api.github.com/repos/KulpLights/fpp-FPPMon"
REPO_URL="${FPPMON_REPO_URL:-https://github.com/KulpLights/fpp-FPPMon}"
SO="${BASEDIR}/libfpp-FPPMon.so"
NOTES="${BASEDIR}/.release-notes.txt"

# Keep the Release Notes cache in step with the release we just looked at.
# Best-effort throughout: a failure here must never change the answer this
# script gives FPP, so every step is guarded and nothing replaces a good cache
# with a partial download.
cache_release_notes() {
    local want="$1" maj="$2" tmp
    # The cache names the build it describes on its first line, so a check that
    # finds the same release again costs nothing.
    if [ -s "${NOTES}" ] && head -1 "${NOTES}" | grep -qF "${want}"; then
        return 0
    fi
    tmp="$(mktemp "${NOTES}.XXXXXX" 2>/dev/null)" || return 0
    if curl -fsSL --max-time 20 -o "${tmp}" \
        "${REPO_URL}/releases/download/fpp${maj}/releasenotes.txt" 2>/dev/null &&
        [ -s "${tmp}" ]; then
        chmod 644 "${tmp}" 2>/dev/null
        mv -f "${tmp}" "${NOTES}" 2>/dev/null || rm -f "${tmp}"
    else
        rm -f "${tmp}"
    fi
}

MAJ="$(grep -oE 'FPP_MAJOR_VERSION[[:space:]]+[0-9]+' "${FPPDIR}/src/fppversion_defines.h" 2>/dev/null | grep -oE '[0-9]+$')"
if [ -z "${MAJ}" ]; then
    echo "fpp-FPPMon: could not determine FPP major version"
    echo "0"
    exit 0
fi

REMOTE="$(curl -fsSL --max-time 20 "${REPO_API}/releases/tags/fpp${MAJ}" 2>/dev/null |
    grep -oE 'version: [0-9]{4}\.[0-9]{2}\.[0-9]{2}-[0-9a-f]+' | head -1 | cut -d' ' -f2)"
if [ -z "${REMOTE}" ]; then
    # No network / no release / notes not stamped yet: can't tell, don't nag.
    echo "fpp-FPPMon: could not determine latest released version"
    echo "0"
    exit 0
fi

cache_release_notes "${REMOTE}" "${MAJ}"

if [ -s "${SO}" ] && [ ! -r "${SO}" ]; then
    # Present but unreadable by this user (e.g. a pre-fix 0600 download):
    # we can't tell what build it is, so don't report a false update.
    echo "fpp-FPPMon: ${SO} is not readable, cannot determine installed build"
    echo "0"
    exit 0
fi

LOCAL=""
if [ -s "${SO}" ]; then
    # grep -a, not `strings`: same answer without needing binutils installed.
    # Matches the reader in fetch-binary.sh.
    LOCAL="$(LC_ALL=C grep -ao 'FPPMon-build:[0-9A-Za-z._-]*' "${SO}" 2>/dev/null | head -1 | cut -d: -f2)"
fi

echo "fpp-FPPMon: installed build '${LOCAL:-unknown}', latest release '${REMOTE}'"
if [ "${LOCAL}" = "${REMOTE}" ]; then
    echo "0"
else
    # Covers both a version mismatch and an older .so without the marker.
    echo "1"
fi
exit 0
