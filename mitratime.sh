#!/bin/sh

mitra=~/mitraille

usage()
{
	printf "
Description:
	Test a list of IFS, ARPEGE, ALADIN, AROME, ALARO, PGD, FP,... configurations

Usage:
	mitratime.sh cycle [-m factor]

Arguments:
	cycle: path to cycle directory where jobs have been run
	-m: time inflation factor (default: 1) for jobs elapsed time (non run jobs \
only)
	-h: print this help and exits normally

Dependencies:
	R software
"
}

cycle=""
factor=1
help=0

[ $# -eq 0 ] && help=1

while [ $# -ne 0 ]
do
	case $1 in
		-m)
			factor=$2
			shift
			;;
		-h) help=1;;
		*)
			if [ -n "$cycle" ]
			then
				echo "Error: unknown option '$1'" >&2
				exit 1
			fi
			cycle=$1
			;;
	esac

	shift
done

set -e

if [ $help -eq 1 ]
then
	usage
	exit
elif [ -z "$cycle" ]
then
	printf "Error: mandatory arguments missing
cycle: '$cycle'
" >&2
	exit 1
elif [ ! -d $cycle ]
then
	echo "Error: mandatory directories missing" >&2
	ls -d $cycle
fi

echo "Looking for jobs log files..."
grep -A 2 -iE ' +elapsed +' $cycle/*/*.log | grep COMPLETED | \
	sed -re 's:.+/(.+)/.+\.log\-( +[^ ]+){7} +([0-9\:]+).+:\1 \3:' > elapse.txt

type R > /dev/null 2>&1 || module -s load intel R > /dev/null 2>&1

R --slave -f $mitra/profils.R --args factor=$factor

rm elapse.txt
