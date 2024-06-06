#!/bin/sh

mitra=~/mitraille

usage()
{
	printf "
Description:
	Check the difference between 2 'NODE' file in terms of spectral and grid-point norms

Usage:
	normdiff.sh NODE1 NODE2 [-spre RE|-nosp] [-gpre RE|-nogp] [-nosurf] [-nofp] [-h]

Arguments:
	NODE1/2: path to 2 'NODE' files
	-spre: use regular expression RE as pattern for block of spectral norms to compare
	-gpre: use regular expression RE as pattern for block of grid-point norms to compare
	-nosp: do not check differences for 'NODE' prints of spectral norms
	-nogp: do not check differences for 'NODE' prints of grid-point norms
	-nosurf: do not check differences for 'NODE' prints of surface grid-point norms
	-nofp: do not checl differences for 'NODE' prints of FullPOS norms
	-h: print this help and exit normally

Details:
	Spectral norms are printed showing number of digits in common between the 2 \
'NODE' files, while grid-point norms show the opposite (number of different digits).
	Default spectral norms compared rely on blocks of norms following pattern \
'NORMS AT (NSTEP|END) CNT4', if found in files. With option '-spre', blocks of norms \
follow pattern RE, which should be present in both files.
	Default grid-point norms are printed for GFL t0 without any pattern indicating them. \
Option '-gpre' lets specify other blocks of GP norms that follow pattern RE, \
which should be present in both files.

Dependencies:
	R software
"
}

if [ $# -eq 0 ] || echo " $*" | grep -qE ' \-h\>'
then
	usage
	exit
fi

fic1=""
fic2=""
spre=""
gpre=""
sp=1
gp=1
fp=1
surf=1
opt=""

while [ $# -ne 0 ]
do
	case $1 in
	-spre)
		spre="re=$2"
		shift
		;;
	-gpre)
		gpre="re=$2"
		shift
		;;
	-nosp)
		sp=0
		;;
	-nogp)
		gp=0
		;;
	-nofp)
		fp=0
		;;
	-nosurf)
		surf=0
		;;
	-mnx)
		opt="mnx=TRUE"
		;;
	*)
		if [ -z "$fic1" ]
		then
			fic1=$1
		elif [ -z "$fic2" ]
		then
			fic2=$1
		else
			echo "Error: files 1 & 2 already set as '$fic1' '$fic2', unknown option '$1'" >&2
			exit 1
		fi
		;;
	esac

	shift
done

if [ -z "$fic1" -o -z "$fic2" ]
then
	echo "Error: missing mandatory arguments:
fic1: '$fic1'
fic2: '$fic2'" >&2
	exit 1
fi

set -e

type R > /dev/null 2>&1 || module -s load intel R > /dev/null 2>&1
if ! env | grep -qw R_LIBS
then
	export R_LIBS=~petithommeh/lib
	echo "--> setting R_LIBS: $R_LIBS"
else
	R_LIBS=$R_LIBS:~petithommeh/lib
fi

if ! grep -qi 'spectral norms' $fic1
then
	echo "--> no spectral/grid-point norms"
	exit
fi

if [ $sp -eq 1 ]
then
	echo ". SP norms difference (up to 17):"
	R --slave -f $mitra/spdiff.R --args fic1=$fic1 fic2=$fic2 $spre
fi

if [ $gp -eq 1 ]
then
	echo ". GP norms difference (up to 17):"
	R --slave -f $mitra/gpdiff.R --args fic1=$fic1 fic2=$fic2 $gpre $opt
fi

if [ $fp -eq 1 ]
then
	echo ". FP norms difference (up to 17):"
	R --slave -f $mitra/fpdiff.R --args fic1=$fic1 fic2=$fic2 $opt
fi

if [ $surf -eq 1 ]
then
	echo ". Surface GP norms difference (up to 17):"
	R --slave -f $mitra/surfdiff.R --args fic1=$fic1 fic2=$fic2 $opt
fi
