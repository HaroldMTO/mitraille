#!/bin/sh

mitra=~/mitraille

usage()
{
	printf "
Description:
	Check the difference between 2 'NODE' file in terms of spectral and \
grid-point norms

Usage:
	normdiff.sh NODE1 NODE2 [-nogp] [-fp] [-h]

Arguments:
	NODE1/2: path to 2 'NODE' files
	-nogp: do not check differences for 'NODE' prints of grid-point norms
	-fp: check differences also for 'NODE' prints of FULL-POS norms (grid-point)
	-h: print this help and exits normally

Details:
	Spectral norms are printed showing number of digits in common between the 2 \
'NODE' files, while grid-point norms show the opposite (number of different \
digits).

Dependencies:
	R software, executable ~petithommeh/bin/spdiff
"
}

fic1=""
fic2=""
gp=1
fp=FALSE
help=0

[ $# -eq 0 ] && help=1

while [ $# -ne 0 ]
do
	case $1 in
		-nogp)
			gp=0
			;;
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
	echo "usage: normdiff.sh NODE1 NODE2 [-nogp] [-fp] [-h]" >&2
	exit 1
fi

set -e

type R > /dev/null 2>&1 || module -s load intel R > /dev/null 2>&1

if ! grep -qi 'spectral norms' $fic1
then
	echo "--> no spectral/grid-point norms"
	exit
fi

echo ". SP norms difference (up to 17):"
R --slave -f $mitra/spdiff.R --args fic1=$fic1 fic2=$fic2

if false
then
	echo ". SP norms agreement (up to 17):"
	if grep -qE 'AVE .+[0-9][-+][0-9]' $fic1
	then
		echo "--> correction of spectral norms printings"
		sed -i -re 's:(AVE .+[0-9])([-+][0-9]):\1E\2:' $fic1
	fi

	if grep -qE 'AVE .+[0-9][-+][0-9]' $fic2
	then
		echo "--> correction of spectral norms printings"
		sed -i -re 's:(AVE .+[0-9])([-+][0-9]):\1E\2:' $fic2
	fi

	spdiff $fic1 $fic2 | grep -vE '^$' | sed -re 's:^# +:  step(s)\|:' \
		-e 's: +$::' -e 's: {2,}([A-Z]+):\|\1:g' \
		-e 's:([0-9]+)\.[0-9]+e[+-]?[0-9]+ +::g'
fi

if [ $gp -eq 1 ]
then
	echo ". GP norms difference (up to 17):"
	R --slave -f $mitra/gpdiff.R --args fic1=$fic1 fic2=$fic2 fp=$fp
fi
