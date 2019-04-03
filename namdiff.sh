#!/bin/sh

mitra=~/mitraille

usage()
{
	printf "
Description:

Synopsis:
	$(basename $0) ficold ficnew [-h]

Arguments:
	-h: displays help and terminates normally

Details:

Exit status:
	Non 0 in case of error
	0 if not

Dependencies:

Author:
	H Petithomme, Meteo France - DR/GMAP/ALGO
"
}

ficold=""
ficnew=""
help=0

if [ $# -eq 0 ] || echo $* | grep -q ' -h'
then
	usage
	exit
elif [ $# -lt 2 ]
then
	echo "Error: input files missing" >&2
	exit 1
fi

R --encoding="latin1" --slave -f $mitra/namdiff.R --args ficold=$1 ficnew=$2
