#!/bin/sh

mitra=~/mitraille

usage()
{
	printf "
Description:
	Check the difference between 2 'NODE' file in terms of spectral and \
grid-point norms

Usage:
	normdiff.sh NODE1 NODE2 [-fp] [-h]

Arguments:
	NODE1/2: path to 2 'NODE' files
	-fp: check differences also for 'NODE' prints of FULL-POS norms (grid-point)
	-h: print this help and exits normally

Details:
	Spectral norms are printed showing number of digits in common between the 2 \
'NODE' files, while grid-point norms show the opposite (number of different \
digits).

Dependencies:
	R software, executable ~marguina/mitraille/diff
"
}

alias spdiff='~marguina/mitraille/diff'

fic1=""
fic2=""
fp=FALSE
help=0

[ $# -eq 0 ] && help=1

while [ $# -ne 0 ]
do
	case $1 in
		-fp)
			fp=TRUE
			;;
		-h)
			help=1
			;;
		*)
			[ -z "$fic1" ] && fic1=$1 || fic2=$1
			;;
	esac

	shift
done

if [ $help -eq 1 ]
then
	usage
	exit
elif [ -z "$fic1" -o -z "$fic2" ]
then
	echo "usage: gpdiff.sh NODE1 NODE2 [-fp] [-h]" >&2
	exit 1
fi

set -e

type R > /dev/null 2>&1 || module -s load intel R > /dev/null 2>&1

if ! grep -qi 'spectral norms' $fic1
then
	echo "--> no spectral/grid-point norms"
	exit
fi

echo ". SP norms agreement (up to 17):"
spdiff $fic1 $fic2 | grep -vE '^$' | sed -re 's:^# +:  step(s)\|:' \
	-e 's: +$::' -e 's: {2,}([A-Z]+):\|\1:g' \
	-e 's:([0-9]+)\.[0-9]+e[+-]?[0-9]+ +::g'

echo ". GP norms difference (up to 17):"
R --slave -f $mitra/gpdiff.R --args fic1=$fic1 fic2=$fic2 fp=$fp
