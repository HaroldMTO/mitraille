#!/bin/sh

usage()
{
	printf "
Description:
	Produce 'empty' concatenated Fortran namelist from Fortran 90 files, \
supposed to contain namelist declarations.

	Files produced are:
		namnul.txt: empty concatenated list of namelists
		namelists.f90: list of all found namelist declarations, as a Fortran file
		(note: namelist names and variables are sorted out)

Synopsis:
	$(basename $0) [-ext EXT] [-h]

Arguments:
	-ext : file extension for Fortran files containing namelists (as file.EXT)
	-h: displays help and terminates normally

Details:
	Files are searched recursively from local directory (find)
	Files are assumed to all be Fortran code files
	Found files are rewritten by rewrite.sh before namelist extraction from \
Fortran code files

Exit status:
	Non 0 in case of non unique namelist names or any else error
	0 if not

Dependencies:
	Utility tool rewrite.sh (parsing and rewriting of Fortran 90 files)

Author:
	H Petithomme, Meteo France - DR/GMAP/ALGO
"
}

ext=""
help=0

[ $# -eq 0 ] && help=1

while [ $# -ne 0 ]
do
	case $1 in
		-ext)
			ext=$(echo $2 | sed -re 's:^\.::' -e 's:([^\])\.:\1\\.:g')
			shift
			;;
		-h)
			help=1
			;;
		*)
			echo "$1 : unknown option, ignored" >&2
			;;
	esac

	shift
done

if [ $help -eq 1 ]
then
	usage
	exit
elif echo "$ext" | grep -qE "\s+."
then
	echo "Error: spaces in file extension (non valid)" >&2
	exit 1
fi

set -e

tmpdir=$(mktemp -d tmpXXX)
trap 'rm -r $tmpdir' EXIT

find -type f -name \*.$ext -printf "%h\n" | sort -u > $tmpdir/nam.lst
if [ ! -s $tmpdir/nam.lst ]
then
	echo "--> no namelist found recursively as '*.$ext'"
	exit
fi

while read dd
do
	rewrite.sh -i $dd -o $tmpdir/$dd -ext "$ext" > /dev/null
	# que 'namelist' (pas garanti...)
	grep -ihE '^\s*namelist\s*/\s*\w+\s*/' $tmpdir/$dd/*.$ext | \
		sed -re 's: *::g' -e 's:!.*::'
done < $tmpdir/nam.lst > $tmpdir/nam.f90

# ordonnement des variables et des namelists (sort, sans -u)
while read nam
do
	pre=$(echo $nam | sed -re 's:^(.+/.+/).+:\1:')
	vars=$(echo $nam | sed -re 's:^.+/.+/::' | tr ',' '\n' | sort | xargs | \
		tr ' ' ',')
	echo "$pre$vars"
done < $tmpdir/nam.f90 | sort > namelists.f90

echo "Writing default namelist, ie 'empty namelist' (namnul.txt)"
sed -re 's:^namelist/(\w+)/.+:\&\U\1/:' namelists.f90 > namnul.txt

echo ". nb of namelists : $(wc -l namnul.txt)"

uniq namnul.txt > $tmpdir/namnul.txt
if [ $(cat namnul.txt | wc -l) -ne $(cat $tmpdir/namnul.txt | wc -l) ]
then
	echo "Error: existing duplicated namelist names:" >&2
	diff -bBw namnul.txt $tmpdir
	exit 1
fi
