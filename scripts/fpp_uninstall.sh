#!/bin/bash
#############################################################################
# fpp-FPPMon uninstall script.
#
# Everything this plugin puts outside its own directory comes back out here,
# and the script is safe to run twice (PLUGIN_GUIDELINES.md 2.1). FPP removes
# the plugin directory itself, so the binary and the cached release notes need
# no help.
#############################################################################

. ${FPPDIR}/scripts/common

# The Content-Security-Policy entry fpp_install.sh / fpp_upgrade.sh added for
# the config page's login POST. Only the local override is touched; if FPP's
# own built-in list still carries the domain it stays, which is correct --
# it was never ours to take away.
MACP="${FPPDIR}/scripts/ManageApacheContentPolicy.sh"
if [ -x "${MACP}" ]; then
    (cd /tmp && "${MACP}" remove connect-src https://kulplights.com) || \
        echo "fpp-FPPMon: could not remove the CSP entry for kulplights.com"
fi

# The stored KulpLights session. Leaving a live token on a box the user just
# uninstalled the plugin from is the thing plugindata/ exists to avoid, so it
# goes with the plugin -- along with the pre-plugindata copy under config/,
# which a restored backup can still put back.
rm -rf "${MEDIADIR}/plugindata/fpp-FPPMon"
rm -f "${MEDIADIR}/config/plugin.fppMon.json"

# Which instances the user chose to monitor.
rm -f "${MEDIADIR}/config/plugin.fpp-FPPMon"

exit 0
