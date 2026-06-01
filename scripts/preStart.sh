#!/bin/sh

# fpp-FPPMon PreStart script
# Ensure the correct plugin binary is present before fppd starts. Re-downloads
# if it is missing or was built for a different FPP major (e.g. after an FPP
# OS upgrade carried the old plugin directory forward).

echo "Running fpp-FPPMon PreStart Script"

BASEDIR="$(cd "$(dirname "$0")" && pwd)"
"${BASEDIR}/fetch-binary.sh"
