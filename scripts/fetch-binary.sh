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
# (preStart.sh). The boot run re-fetches when the .so is missing or was built
# for a different FPP major than is now running -- which happens after an FPP
# OS upgrade carries the old plugin dir forward.
#############################################################################

# BASEDIR = the plugin directory (one level up from this script).
BASEDIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"

# Pull in FPPDIR / FPPPLATFORM. FPPDIR is exported when FPP runs our scripts;
# fall back to the standard location for direct/manual invocation.
FPPDIR="${FPPDIR:-/opt/fpp}"
if [ -f "${FPPDIR}/scripts/common" ]; then
    . "${FPPDIR}/scripts/common"
fi

REPO_URL="https://github.com/KulpLights/fpp-FPPMon"
TARGET="${BASEDIR}/libfpp-FPPMon.so"
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

# --- Skip if we already have the right binary --------------------------------
if [ -s "${TARGET}" ] && [ "$(cat "${MARKER}" 2>/dev/null)" = "${MAJ}" ]; then
    echo "fpp-FPPMon: ${PLAT} binary for FPP ${MAJ} already present"
    exit 0
fi

ASSET="libfpp-FPPMon-${PLAT}-${MAJ}.so.gz"
URL="${REPO_URL}/releases/download/fpp${MAJ}/${ASSET}"
echo "fpp-FPPMon: downloading ${ASSET} ..."

TMP="$(mktemp "${BASEDIR}/.fpp-FPPMon.XXXXXX.gz")"
trap 'rm -f "${TMP}" "${TMP%.gz}"' EXIT

if ! curl -fSL --retry 3 -o "${TMP}" "${URL}"; then
    echo "fpp-FPPMon: ERROR downloading ${URL}" >&2
    echo "fpp-FPPMon: no binary available for ${PLAT} on FPP ${MAJ}." >&2
    exit 1
fi

if ! gunzip -f "${TMP}"; then
    echo "fpp-FPPMon: ERROR decompressing ${ASSET}" >&2
    exit 1
fi

# Atomically replace the live .so and record which major it was built for.
mv -f "${TMP%.gz}" "${TARGET}"
echo "${MAJ}" > "${MARKER}"
trap - EXIT
echo "fpp-FPPMon: installed ${PLAT} binary for FPP ${MAJ}"
