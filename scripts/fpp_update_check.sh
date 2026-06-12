#!/bin/bash
#############################################################################
# FPP plugin-manager update check (see PluginHasUpdates in FPP's plugin
# API). This repo's git history rarely changes -- the actual plugin is a
# prebuilt libfpp-FPPMon.so attached to a rolling release tag -- so the git
# check alone can't see binary updates. Compare the build version burned
# into the installed .so ("FPPMon-build:<ver>") against the "version:" line
# CI stamps into the rolling release's notes.
#
# Contract with FPP: last line of stdout is "1" (update available) or "0";
# a non-zero exit status means "could not check" and is ignored.
#############################################################################

BASEDIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
FPPDIR="${FPPDIR:-/opt/fpp}"
REPO_API="https://api.github.com/repos/KulpLights/fpp-FPPMon"
SO="${BASEDIR}/libfpp-FPPMon.so"

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

if [ -s "${SO}" ] && [ ! -r "${SO}" ]; then
    # Present but unreadable by this user (e.g. a pre-fix 0600 download):
    # we can't tell what build it is, so don't report a false update.
    echo "fpp-FPPMon: ${SO} is not readable, cannot determine installed build"
    echo "0"
    exit 0
fi

LOCAL=""
if [ -s "${SO}" ]; then
    LOCAL="$(strings "${SO}" 2>/dev/null | sed -n 's/^FPPMon-build://p' | head -1)"
fi

echo "fpp-FPPMon: installed build '${LOCAL:-unknown}', latest release '${REMOTE}'"
if [ "${LOCAL}" = "${REMOTE}" ]; then
    echo "0"
else
    # Covers both a version mismatch and an older .so without the marker.
    echo "1"
fi
exit 0
