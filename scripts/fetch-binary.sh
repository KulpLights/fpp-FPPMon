#!/bin/bash
#############################################################################
# Download the FPPMon plugin binary that matches this device's platform and
# the installed FPP major version, and place it as libfpp-FPPMon.so in the
# plugin directory.
#
# Binaries are published per FPP major to a rolling release tag on the public
# repo, e.g.  releases/download/fpp10/libfpp-FPPMon-Pi64-10.so.gz
#
# This is sourced/run both at install time (fpp_install.sh) and on every boot
# (preStart.sh). The boot run re-fetches when the .so is missing or no longer
# matches the running FPP -- which happens after an FPP OS upgrade carries the
# old plugin dir forward.
#
# "Matches" is the FPP major AND the plugin ABI version (FPP_PLUGIN_API_VERSION
# in FPP's Plugin.h). The major alone is not enough: FPP bumps the ABI version
# *within* a major when it changes the layout of a type plugins construct, and
# fppd then refuses to load a binary built against the older value. Keying the
# marker on the major only meant such a box saw "already present", never
# re-fetched, and stayed broken forever -- exactly the situation the FPP 10
# 3 -> 4 bump created for every installed FPPMon binary.
#############################################################################

# BASEDIR = the plugin directory (one level up from this script).
BASEDIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"

# Pull in FPPDIR / FPPPLATFORM. FPPDIR is exported when FPP runs our scripts;
# fall back to the standard location for direct/manual invocation.
FPPDIR="${FPPDIR:-/opt/fpp}"
if [ -f "${FPPDIR}/scripts/common" ]; then
    . "${FPPDIR}/scripts/common"
fi

# Overridable so the download/verify path can be tested against a local server.
REPO_URL="${FPPMON_REPO_URL:-https://github.com/KulpLights/fpp-FPPMon}"
TARGET="${BASEDIR}/libfpp-FPPMon.so"
# Records what the installed .so was built for, as "<major>" on FPP releases
# that predate the plugin ABI version, or "<major>.<abi>" where it exists. The
# filename is historical; an install written by an older version of this script
# holds a bare major, which simply fails to match and triggers one re-fetch.
MARKER="${BASEDIR}/.binary-major"

# Determine whether the installed FPP is 64-bit. NOTE: `uname -m` is NOT
# reliable for this on a Pi 4/5 -- those boot a 64-bit kernel even under a
# 32-bit FPP, so `uname -m` reports "aarch64" for what is really an armhf
# userspace. Instead read the ELF class of an actual FPP binary (the exact ABI
# the plugin must match): byte 5 of the ELF header is 2 for 64-bit, 1 for
# 32-bit. Fall back to getconf/uname only if no FPP binary is readable.
fpp_is_64bit() {
    _f=""
    for _c in "${FPPDIR}/src/fppd" "${FPPDIR}/src/libfpp.so"; do
        [ -r "${_c}" ] && { _f="${_c}"; break; }
    done
    if [ -n "${_f}" ]; then
        case "$(od -An -t u1 -j4 -N1 "${_f}" 2>/dev/null | tr -d '[:space:]')" in
            2) return 0 ;;   # ELFCLASS64
            1) return 1 ;;   # ELFCLASS32
        esac
    fi
    if command -v getconf >/dev/null 2>&1; then
        [ "$(getconf LONG_BIT 2>/dev/null)" = "64" ]
        return $?
    fi
    [ "$(uname -m)" = "aarch64" ] || [ "$(uname -m)" = "x86_64" ]
}

# --- Platform: $FPPPLATFORM can't tell Pi from Pi64, so check the bitness -----
ARCH="$(uname -m)"
case "${FPPPLATFORM}" in
    "Raspberry Pi")
        if fpp_is_64bit; then PLAT="Pi64"; else PLAT="Pi"; fi
        ;;
    "BeagleBone 64")     PLAT="BB64" ;;
    "BeagleBone Black")  PLAT="BBB" ;;
    *)
        # Generic installs (Armbian/Debian/Ubuntu/etc.) -- key off the
        # architecture. (Pi64/BB64 are also aarch64 but are matched above by
        # $FPPPLATFORM, so this only catches non-Pi/BB hardware.)
        if [ "${ARCH}" = "x86_64" ]; then
            PLAT="x86_64"
        elif fpp_is_64bit; then
            PLAT="aarch64"
        else
            echo "fpp-FPPMon: unsupported platform '${FPPPLATFORM}' (${ARCH}), skipping binary download" >&2
            exit 0
        fi
        ;;
esac

# --- FPP major version (the software version, not the OS date stamp) ---------
VERFILE="${FPPDIR}/src/fppversion_defines.h"
MAJ="$(grep -oE 'FPP_MAJOR_VERSION[[:space:]]+[0-9]+' "${VERFILE}" 2>/dev/null | grep -oE '[0-9]+$')"
if [ -z "${MAJ}" ]; then
    echo "fpp-FPPMon: could not determine FPP major version from ${VERFILE}" >&2
    exit 1
fi

# --- Plugin ABI version (absent on FPP releases predating the mechanism) ------
# fppd refuses to load a plugin whose FPP_PLUGIN_API_VERSION differs from its
# own, so this has to be part of the "is the installed binary still good?" test.
PLUGINHDR="${FPPDIR}/src/Plugin.h"
ABI="$(sed -nE 's/^#define[[:space:]]+FPP_PLUGIN_API_VERSION[[:space:]]+([0-9]+).*/\1/p' "${PLUGINHDR}" 2>/dev/null | head -1)"
if [ -n "${ABI}" ]; then
    KEY="${MAJ}.${ABI}"
    DESC="FPP ${MAJ} (plugin ABI ${ABI})"
else
    # Older FPP with no version gate; major alone is the best signal available.
    KEY="${MAJ}"
    DESC="FPP ${MAJ}"
fi

# Read a marker string the plugin exports out of a .so (see FPPMON_ABI_MARKER /
# FPPMON_BUILD_MARKER in src/FPPMonitorPlugin.cpp). grep -a rather than
# `strings`, so this does not depend on binutils being installed.
so_marker() {
    LC_ALL=C grep -ao "FPPMon-${2}:[0-9A-Za-z._-]*" "$1" 2>/dev/null | head -1 | cut -d: -f2
}

# Does a .so declare an ABI this fppd will actually load? Three answers:
# "ok", "unknown" (nothing to compare -- either this FPP predates the version
# gate, or the binary predates this marker), or "no".
abi_fits() {
    _got="$(so_marker "$1" abi)"
    if [ -z "${ABI}" ] || [ -z "${_got}" ]; then
        echo "unknown"
    elif [ "${_got}" = "${ABI}" ]; then
        echo "ok"
    else
        echo "no"
    fi
}

# --- Skip if we already have the right binary --------------------------------
# The marker alone is not enough. It records what the *core* wanted at the time
# it was written, so a download that turned out to be the wrong build still
# stamped it "current" -- and the box then never re-fetched, staying broken
# through every boot until someone deleted the file by hand. Ask the installed
# binary what it is as well, and treat a disagreement as "not present".
if [ -s "${TARGET}" ] && [ "$(cat "${MARKER}" 2>/dev/null)" = "${KEY}" ]; then
    case "$(abi_fits "${TARGET}")" in
        no)
            echo "fpp-FPPMon: installed binary is built for plugin ABI $(so_marker "${TARGET}" abi), but this FPP wants ${ABI} -- re-fetching"
            ;;
        *)
            echo "fpp-FPPMon: ${PLAT} binary for ${DESC} already present"
            exit 0
            ;;
    esac
fi

# --- Which asset? ------------------------------------------------------------
# builds.txt lists what the release actually holds, one line per asset:
#   <asset> <platform> <major> <abi> <version> <sha256>
# Ask it for the build made for this platform AND this FPP's plugin ABI. Asking
# by major alone was only ever right because there happened to be one binary per
# major: FPP bumps FPP_PLUGIN_API_VERSION *within* a major, so "the FPP 10
# binary" is not one thing, and a box that cannot say which one it can load gets
# handed whichever was built last.
MANIFEST="$(mktemp "${TMPDIR:-/tmp}/fpp-FPPMon.XXXXXX.builds")"
ASSET=""
if curl -fsL --retry 2 --max-time 20 -o "${MANIFEST}" \
        "${REPO_URL}/releases/download/fpp${MAJ}/builds.txt"; then
    ROW="$(awk -v p="${PLAT}" -v m="${MAJ}" -v a="${ABI:-none}" \
        '$2 == p && $3 == m && $4 == a { print $1 " " $5; exit }' "${MANIFEST}")"
    if [ -z "${ROW}" ]; then
        echo "fpp-FPPMon: ERROR: no ${PLAT} build for ${DESC} in release fpp${MAJ}." >&2
        echo "fpp-FPPMon: what is published for ${PLAT}:" >&2
        awk -v p="${PLAT}" '$2 == p { print "    FPP " $3 ", plugin ABI " $4 " -> " $1 }' "${MANIFEST}" >&2
        echo "fpp-FPPMon: leaving the installed binary alone; this will retry on the next boot." >&2
        rm -f "${MANIFEST}"
        exit 1
    fi
    ASSET="${ROW% *}"
    echo "fpp-FPPMon: ${ASSET} is the published build for ${DESC} (${ROW#* })"
else
    # A release predating builds.txt carried one binary per major, named without
    # the ABI. Keep fetching it the old way; the stamp check below still refuses
    # it if it turns out not to fit.
    ASSET="libfpp-FPPMon-${PLAT}-${MAJ}.so.gz"
    echo "fpp-FPPMon: release fpp${MAJ} has no builds.txt, falling back to ${ASSET}"
fi
rm -f "${MANIFEST}"

URL="${REPO_URL}/releases/download/fpp${MAJ}/${ASSET}"
SUMSURL="${REPO_URL}/releases/download/fpp${MAJ}/checksums.txt"
echo "fpp-FPPMon: downloading ${ASSET} ..."

TMP="$(mktemp "${BASEDIR}/.fpp-FPPMon.XXXXXX.gz")"
# The download has to land in BASEDIR so the final mv onto the .so is a
# same-filesystem rename, but the checksum list is not an install artifact and
# has no such constraint. Keep it out of the plugin directory: that directory
# is a git working tree, so anything left there shows up as untracked cruft
# and gets swept by the plugin manager on the next upgrade.
SUMS="$(mktemp "${TMPDIR:-/tmp}/fpp-FPPMon.XXXXXX.sums")"
trap 'rm -f "${TMP}" "${TMP%.gz}" "${SUMS}"' EXIT

sha256_of() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | cut -d' ' -f1
    else
        shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1
    fi
}

# Verify the downloaded archive against the release's checksums.txt before it
# can replace the installed .so, so a truncated or corrupted download can't
# take out a working install. CI uploads the binaries and checksums.txt as
# separate assets, so a fetch that lands mid-publish can see a mismatched
# pair; one re-fetch of both resolves that, and a mismatch that survives the
# retry is fatal. A release with no checksums.txt (predates the mechanism)
# verifies nothing -- same trust as before, so proceed with a note.
VERIFY="pending"
for ATTEMPT in 1 2; do
    if ! curl -fSL --retry 3 -o "${TMP}" "${URL}"; then
        echo "fpp-FPPMon: ERROR downloading ${URL}" >&2
        echo "fpp-FPPMon: no binary available for ${PLAT} on FPP ${MAJ}." >&2
        exit 1
    fi
    if ! curl -fsL --retry 3 -o "${SUMS}" "${SUMSURL}"; then
        VERIFY="no-checksums"
        break
    fi
    EXPECTED="$(awk -v a="${ASSET}" '$2 == a { print tolower($1); exit }' "${SUMS}")"
    if [ -z "${EXPECTED}" ]; then
        VERIFY="unlisted"
        break
    fi
    ACTUAL="$(sha256_of "${TMP}")"
    if [ -z "${ACTUAL}" ]; then
        VERIFY="no-tool"
        break
    fi
    if [ "${ACTUAL}" = "${EXPECTED}" ]; then
        VERIFY="ok"
        break
    fi
    VERIFY="mismatch"
    [ "${ATTEMPT}" = "1" ] && echo "fpp-FPPMon: checksum mismatch for ${ASSET}, re-fetching ..." >&2
done
case "${VERIFY}" in
    ok)           echo "fpp-FPPMon: checksum verified for ${ASSET}" ;;
    no-checksums) echo "fpp-FPPMon: release fpp${MAJ} has no checksums.txt, skipping verification" ;;
    unlisted)     echo "fpp-FPPMon: WARNING: ${ASSET} not listed in checksums.txt, skipping verification" >&2 ;;
    no-tool)      echo "fpp-FPPMon: WARNING: no sha256 tool available, skipping verification" >&2 ;;
    *)
        echo "fpp-FPPMon: ERROR: checksum mismatch for ${ASSET}; keeping the installed binary." >&2
        echo "fpp-FPPMon: (a release may be mid-publish -- retry in a few minutes)" >&2
        exit 1
        ;;
esac

if ! gunzip -f "${TMP}"; then
    echo "fpp-FPPMon: ERROR decompressing ${ASSET}" >&2
    exit 1
fi

# Never put a binary fppd cannot load where fppd will try to load it. A
# mismatch here means the release does not yet carry a build for this FPP's
# plugin ABI; installing it anyway is worse than installing nothing, because a
# plugin built against a different layout of a struct FPP hands it can load
# cleanly and then corrupt the heap. Leave the marker unwritten so the next
# boot tries again on its own once a matching build is published.
case "$(abi_fits "${TMP%.gz}")" in
    no)
        echo "fpp-FPPMon: ERROR: ${ASSET} is built for plugin ABI $(so_marker "${TMP%.gz}" abi), but this FPP wants ${ABI}." >&2
        echo "fpp-FPPMon: not installing it. A build for ABI ${ABI} has not been published yet." >&2
        exit 1
        ;;
    unknown)
        [ -n "${ABI}" ] && echo "fpp-FPPMon: ${ASSET} carries no ABI stamp, cannot check it against ${ABI}"
        ;;
esac

# Atomically replace the live .so and record which major it was built for.
# mktemp creates the temp file 0600 and mv preserves that mode, which left
# the .so readable only by root -- breaking non-root tooling like the
# update-check script the web UI runs. Open both files up explicitly.
chmod 644 "${TMP%.gz}"
mv -f "${TMP%.gz}" "${TARGET}"
echo "${KEY}" > "${MARKER}"
chmod 644 "${MARKER}"
# Deliberately leave the EXIT trap armed: it is the only thing that removes
# the checksum file, and clearing it here (as this did) leaked one temp file
# per successful download. Everything it removes is either already consumed
# or scratch, so letting it fire on the success path is a no-op plus that
# cleanup -- and no future early return can leak either.
echo "fpp-FPPMon: installed ${PLAT} binary for ${DESC}"
