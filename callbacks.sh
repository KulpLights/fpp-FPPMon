#!/bin/bash
export BASEDIR=$(dirname $0)
. ${FPPDIR}/scripts/common
export FPPPLATFORM

for var in "$@"
do
	case $var in
		-l|--list)
            env > /root/env.txt
            if [[ $FPPPLATFORM == "Raspberry Pi" ]]; then
                cp -f ${BASEDIR}/lib/libfpp-FPPMon-Pi.so ${BASEDIR}/libfpp-FPPMon.so
            elif [[ $FPPPLATFORM == "BeagleBone Black" ]]; then
                cp -f ${BASEDIR}/lib/libfpp-FPPMon-BBB.so ${BASEDIR}/libfpp-FPPMon.so
            fi
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

