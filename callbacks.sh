#!/bin/bash
export BASEDIR=$(dirname $0)
. ${FPPDIR}/scripts/common
export FPPPLATFORM

for var in "$@"
do
	case $var in
		-l|--list)
            # The platform/version-matched libfpp-FPPMon.so is provisioned by
            # scripts/fpp_install.sh (install) and scripts/preStart.sh (boot).
            echo "c++";
            exit 0;
		;;
		-h|--help)
			usage
			exit 0
		;;
		-v|--version)
			printf "%s, version %s\n" "$PROGRAM_NAME" "$PROGRAM_VERSION"
			exit 0
		;;
		--)
			# no more arguments to parse
			break
		;;
		*)
			printf "Unknown option %s\n" "$var"
			exit 1
		;;
	esac
done

