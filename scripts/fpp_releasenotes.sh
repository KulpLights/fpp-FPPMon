#!/bin/bash
#############################################################################
# FPP plugin-manager Release Notes hook (pluginInfo.json declares
# "releaseNotesStyle": "script").
#
# This repo's git history is not the changelog: the plugin is a prebuilt
# libfpp-FPPMon.so attached to a rolling release tag, built from a separate
# source tree, so the commits here say almost nothing about what an update
# would actually change. The notes for each binary build are published as a
# "releasenotes.txt" asset on that same rolling release, and
# scripts/fpp_update_check.sh -- which already talks to the release -- caches
# them here. All this script does is print the cache.
#
# Runs as the web user (fpp), not root, synchronously while the user waits on
# the dialog: no sudo, no downloads, no sleeps. Output is shown as plain text
# (HTML-escaped), so write for a <pre> block. Exit 0 and print something; a
# non-zero exit or empty output shows "no release notes available".
#############################################################################

BASEDIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
CACHE="${BASEDIR}/.release-notes.txt"
SO="${BASEDIR}/libfpp-FPPMon.so"

if [ -s "${CACHE}" ]; then
    cat "${CACHE}"
    echo
fi

# Always close with what is actually loaded on this box, so the notes above can
# be read as "installed" or "available" without guessing.
LOCAL=""
ABI=""
if [ -r "${SO}" ]; then
    LOCAL="$(LC_ALL=C grep -ao 'FPPMon-build:[0-9A-Za-z._-]*' "${SO}" 2>/dev/null | head -1 | cut -d: -f2)"
    ABI="$(LC_ALL=C grep -ao 'FPPMon-abi:[0-9A-Za-z._-]*' "${SO}" 2>/dev/null | head -1 | cut -d: -f2)"
fi
if [ -n "${ABI}" ] && [ "${ABI}" != "none" ]; then
    echo "Installed build: ${LOCAL:-unknown} (plugin ABI ${ABI})"
else
    echo "Installed build: ${LOCAL:-unknown}"
fi

if [ ! -s "${CACHE}" ]; then
    echo
    echo "No release notes have been downloaded yet. They are fetched by the"
    echo "plugin's update check, which runs when FPP checks for updates -- open"
    echo "the Plugin Manager again in a moment, or press Check for Updates."
fi
exit 0
