#!/bin/sh

mitra=~/mitraille

usage()
{
	printf "
Description:
	Check the difference of a list of file

Usage:
	statdiff.sh PATH [-h]

Arguments:
	PATH: file or path to files ('.diff') of field differences
	-h: print this help and exits normally

Details:
	Differences are printed one line for each field, grouped by file and then by vertical \
extension (2D/3D).
	It is the result of a call to R's 'summary' function, namely: min, Q25, median, ave., \
Q75, max and NA's (if there are any).

Dependencies:
	R software
"
}

fic=""
help=0

[ $# -eq 0 ] && help=1

while [ $# -ne 0 ]
do
	case $1 in
		-h)
			help=1
			;;
		*)
			[ -z "$fic" ] && fic=$1
			;;
	esac

	shift
done

if [ $help -eq 1 ]
then
	usage
	exit
elif [ -z "$fic" ]
then
	echo "usage: statdiff.sh PATH [-h]" >&2
	exit 1
fi

set -e

type R > /dev/null 2>&1 || module -s load intel R > /dev/null 2>&1

R --slave -f $mitra/statf.R --args fic=$fic
