#!/bin/sh

usage()
{
	printf "
Description:
	Adapt a list of namelists to a new cycle

Usage:
	modifnam.sh OLD NEW [-delta DELTA|-tag TAG] [-h]

Options:
	OLD/NEW: directories where to find namelists for current (OLD) and changed (NEW) namelists
	-delta: apply file DELTA as a namelist 'delta' as input to xpnam
	-tag: character tag , internal to this script:
		currently only 'belenos' and 'vfenh' are known.
	-h: print this help and exit

Details:
	Namelists are to be found in directory OLD.
	Any file containing word 'NAMCT0' will be processed (could be improved).
	Directory NEW is created if non already existing.
	Overwriting existing files in NEW is allowed, mind it!

Dependencies:
	Whenever option '-delta' is used, a delta file is processed by way of xpnam.
"
}

if [ $# -eq 0 ] || echo $* | grep -qE ' ?\-h'
then
	usage
	exit
fi

set -e

old=""
new=$PWD
nam=""
tag=""
while [ $# -ne 0 ]
do
	case $1 in
	-delta)
		nam=$2
		shift
		;;
	-tag)
		tag=$2
		shift
		;;
	*)
		if [ -z "$old" ]
		then
			old=$1
		else
			new=$1
		fi
		;;
	esac

	shift
done

if [ -z "$old" ] || [ -z "$nam" -a -z "$tag" ]
then
	echo "Error: argument missing
OLD: '$old'
NEW: '$new'
nam/tag: '$nam'/'$tag'" >&2
	exit 1
fi

[ -n "$nam" ] && ls $nam >/dev/null

tmp=$(mktemp -d tmpXXX -t)

trap 'rm -r $tmp' EXIT

if [ -d $old ]
then
	echo "Processing files from $old to $new"

	# new must be a directory (not a file)
	if [ $new != $PWD ]
	then
		mkdir -p $new
		(cd $new >/dev/null)
	fi
else
	echo "Processing file $old to $new"
	ls $old >/dev/null
	ficold=$old

	# new can be a directory or a file
	[ -d $new ] && ficnew=$new/$(basename $old) || ficnew=$new
fi

if [ -n "$nam" ]
then
	echo "Processing files via xpnam"
	type xpnam >/dev/null || PATH=$PATH:~gco/public/bin

	# gather names of namelist blocks
	grep -iE '\&\w+' $nam > $tmp/nam.lst

	for fic in $(ls -1 $old)
	do
		if [ -d $old ]
		then
			ficold=$old/$fic
			ficnew=$new/$fic
		fi

		# target files that have these namelists blocks
		grep -iqEf $tmp/nam.lst $ficold || continue

		cp $ficold $ficnew
		xpnam --dfile="$nam" --inplace $ficnew
	done
elif echo $tag | grep -q vide
then
	for fic in $(ls -1 $old)
	do
		if [ -d $old ]
		then
			ficold=$old/$fic
			ficnew=$new/$fic
		fi

		grep -qE '\<NAMCT0\>' $ficold || continue

		grep -vE '^\s*$' $ficold | sed -re 's:\t:   :g' | tr '\n' '\t' | \
			sed -re 's:(^|\t) *&\w+\s+/::g' | tr '\t' '\n' > $ficnew
	done
elif echo $tag | grep -q belenos
then
	for fic in $(ls -1 $old)
	do
		if [ -d $old ]
		then
			ficold=$old/$fic
			ficnew=$new/$fic
		fi

		grep -qE '\<NAMCT0\>' $ficold || continue

		if grep -qE '\<LFFTW\>.+FALSE' $ficold
		then
			sed -re 's:(\<LFFTW\>.+)\.FALSE.+:\1\.TRUE\.:' $ficold > $tmp/fic
		elif grep -qEv '\<LFFTW\>.+\.TRUE\.' $ficold
		then
			if grep -qE '\<NAMTRANS\>' $ficold
			then
				sed -re 's:(\<NAMTRANS\> *)$:\1\n   LFFTW=.TRUE.,:' $ficold > $tmp/fic
			else
				cat $ficold - > $tmp/fic <<EOF
 &NAMTRANS
   LFFTW=.TRUE.,
 /
EOF
			fi
		fi

		sed -re 's:\<(NPROMA) *=(\-?)50\>:\1=-16:' $tmp/fic > $ficnew
	done
elif echo $tag | grep -q vfenh
then
	for fic in $(ls -1 $old)
	do
		if [ -d $old ]
		then
			ficold=$old/$fic
			ficnew=$new/$fic
		fi

		grep -qE '\<NAMCT0\>' $ficold || continue

		if grep -qE '\<LVERTFE.+FALSE' $ficold
		then
			grep -ivE '^ *\<[LNR]VFE_' $ficold > $fic
			continue
		fi

		grep -ivE '\<LVFE_(REGETA|CENTRI|[XZ]_TERM|LAPL(_HALF|_[TB]BC|2PI)|DELNHPRE)' \
			$ficold > $tmp/fic
		sed -re 's:(NVFE_(DER|INT)BC|LVFE_(APPROX|LAPL *=)):\!\1:' $tmp/fic > $tmp/fic.2

		if grep -qE '\<CVFE_ETAH\>' $ficold
		then
			if [ $(grep -E '\<CVFE_ETAH\>' $ficold | wc -l | awk '{print $0}') -gt 1 ]
			then
				echo "multi CVFE_ETAH: $ficold"
			fi

			mv $tmp/fic.2 $ficnew
			continue
		fi

		grep -qE '\<LVFE_REGETA.+TRUE' $ficold &&
			sed -re 's:\<(LVERTFE.+TRUE.+):\1\n   CVFE_ETAH="REGETA",:' $tmp/fic.2 > $ficnew ||
			sed -re 's:\<(LVERTFE.+TRUE.+):\1\n   CVFE_ETAH="CHORDAL",:' $tmp/fic.2 > $ficnew
	done
elif echo $tag | grep -q crough
then
	for fic in $(ls -1 $old)
	do
		if [ -d $old ]
		then
			ficold=$old/$fic
			ficnew=$new/$fic
		fi

		grep -qE '\<NAM_ISBAN' $ficold || continue

		if grep -qE '\<CROUGH\>' $ficold
		then
			grep -ivE '^ *CROUGH\>' $ficold > $ficnew
		fi
	done
else
	echo "Error: tag '$tag' unknown" >&2
	exit 1
fi
