#!/bin/sh

set -e

mitra=~/mitraille
instates="CONFIGURING|COMPLETING|PENDING|RUNNING|RESIZING|SUSPENDED"

usage()
{
	printf "
Description:
	Test a list of IFS, ARPEGE, ALADIN, AROME, ALARO, PGD, FP,... configurations

Usage:
	mitraillette.sh -cycle CYCLE -rc rcfile [-conf conf] [-b bin] [-t time] \
[-nn nnodes] [-omp nomp] [-nj njobs] [-v]

Arguments:
	CYCLE: IFS cycle tag name (following 'cyNN[t1][_main|r1].vv') where to find \
IFS binaries
	rcfile: resource file for a model job
	-conf: filter for configuration name, as referenced in profil_table
	-b: filter for binary, setting and running jobs only for binary 'bin'
	-t: filter for maximum time execution
	-nn: filter for maximum nnodes SLURM allocation
	-omp: filter for maximum nomp threads
	-nj: submit at most njobs jobs at a time (defaults to 0: no jobs running)
	-v: verbose mode

Details:
	rcfile is sourced and must set the following environment variables:
		- CONST: path to constant files (constants, clims, coupling files, \
guess and analysis files)
		- PACKS: path to CYCLE packs binary files
		- UTILS: path to IO server tool 'io_poll'
	Optional filters act on both jobs setting and optionally running
"
}

help=0
cycle=""
rcfile=""
conf=""
bin0=""
conf0=""
time=1000
nn=1000
nomp=100
nj=0
verbose=0

[ $# -eq 0 ] && help=1

while [ $# -ne 0 ]
do
	case $1 in
		-cycle)
			cycle=$2
			shift
			;;
		-rc)
			rcfile=$2
			;;
		-conf)
			conf0=$2
			shift
			;;
		-b)
			bin0=$2
			shift
			;;
		-t)
			time=$2
			shift
			;;
		-nn)
			nn=$2
			shift
			;;
		-nomp)
			nomp=$2
			shift
			;;
		-nj)
			nj=$2
			shift
			;;
		-v)
			verbose=1
			;;
		-h)
			help=1
			;;
	esac

	shift
done

if [ $help -eq 1 ]
then
	usage
	exit
elif [ -z "$cycle" -o -z "$rcfile" ]
then
	printf "Error: mandatory arguments missing
cycle: '$cycle'
rcfile: '$rcfile'
" >&2
	exit 1
fi

. $rcfile

if [ -z "$PACKS" -o -z "$CONST" -o -z "$UTILS" ]
then
	printf "Error: environment not set
CONST: '$CONST'
$PACKS: '$PACKS'
UTILS: '$UTILS'
" >&2
	exit 1
elif [ ! -d $PACKS -o ! -d $CONST -o ! -d $UTILS ]
then
	printf "Error: mandatory directories missing" >&2
	ls -d $PACKS $CONST $UTILS
fi

pack=$(find $PACKS -maxdepth 1 -type d -follow -name $(basename $cycle)\*.pack|\
	tail -1)
if [ -z "$pack" ]
then
	echo "Error: no pack named '$(basename $cycle)*.pack' on '$PACKS'" >&2
	exit 1
fi

echo "IFS pack found is '$pack'"

# because set -e...
[ -d $cycle ] || cycle=$mitra/$cycle
ls -d $cycle >/dev/null

cycle=$(cd $cycle;pwd)
ddcy=$DATA/$(basename $cycle)

rm -f mit.err

n=0
jobids=""
grep -vE '^\s*#' $mitra/config/profil_table | \
	while read conf bin mem wall cpu ntaskio ntaskt nnodes nthread
do
	if [ ! -x $pack/bin/$bin ]
	then
		echo "Error: no executable $bin on $pack/bin/$BIN" >&2
		exit 1
	fi

	case $conf in
		*_PGDC_*) continue;;
		*PGD*) name=pgd;;
		GM_*) name=arpege;;
		GE_*) name=ifs;;
		L[123]_*) name=alaro;;
		*)
			echo "Error: unknown model name for $conf"
			exit 1
			;;
	esac

	[ -n "$bin0" -a $bin != "$bin0" ] && continue
	[ -n "$conf0" ] && echo $conf | grep -qvE "$conf0" && continue
	[ $wall -gt $time -o $nnodes -gt $nn -o $nthread -gt $nomp ] && continue

	if [ -e $ddcy/$conf/jobOK ]
	then
		echo "--> job $conf.sh already succeeded"
		continue
	fi

	[ $verbose -ne 0 ] && echo "Setting conf $conf"

	# option with deltanams:
	# cp $cycle/nulnam.f90 $ddcy/$conf.nam
	# xpnam --dfile $cycle/deltanam/$conf.nam -i $ddcy/$conf.nam

	cat > job.profile <<-EOF
		export OMP_NUM_THREADS=$nthread
		export LFITOOLS=$pack/bin/LFITOOLS
		nam=$cycle/namelist/$conf.nam
		bin=$pack/bin/$bin
	EOF

	awk '$1=="'$conf'" {printf("pgd=%s\n",$2);}' $cycle/pgdtable >> job.profile
	awk '$1=="'$conf'" {printf("pgdfa=%s/%s\n",$2,$3);}' $cycle/pgdfatable \
		>> job.profile

	awk -v dd=$CONST/analyses '$1=="'$conf'" {printf("ln -sfv %s/%s %s\n",dd,$2,$3);}' \
		$cycle/initable > init.txt
	init=$(grep -E ' (EBAUCHE|ICMSHARPEINIT)$' init.txt | \
		sed -re 's:.+ (.+) .+:\1:')

	awk -v dd=$CONST/anasurfex '$1=="'$conf'" {printf("initsfx=%s/%s\n",dd,$2);}' \
		$cycle/inisfxtable >> job.profile

	awk -v dd=$CONST/pgd '$1=="'$conf'" {printf("ln -sfv %s/%s %s\n",dd,$2,$3);}' \
		$cycle/constable > const.txt

	awk -v dd=$CONST/clim '$1=="'$conf'" {printf("ln -sfv %s/%s %s\n",dd,$2,$3);}'\
		$cycle/climtable $cycle/climfptable $cycle/filtertable > clim.txt

	awk -v dd=$CONST/coupling '$1=="'$conf'" {printf("lbc=%s/%s\n",dd,$2);}' \
		$cycle/coupltable >> job.profile

	awk -v dd=$cycle/fpnam '$1=="'$conf'" {printf("cp %s/%s %s\n",dd,$2,$3);}'\
		$cycle/fptable > fpos.txt
	fpnam=$(cut -d " " -f3 fpos.txt | xargs)
	[ "$fpnam" ] && echo "fpnam=\"$fpnam\"" >> job.profile

	find $cycle/quadnam/ -name $conf.\* -printf "quadnam=%p\n" >> job.profile

	fcnam=$(find $cycle/fcnam/ -name $conf.\* | xargs)
	[ "$fcnam" ] && echo "fcnam=$fcnam" >> job.profile

	find $cycle/selnam/ -name $conf.\* -printf 'selnam=%p\n' >> job.profile

	diffnam=$(find $cycle/diffnam/ -name ${conf}_CONVPGD.nam)
	if [ "$diffnam" ]
	then
		cat >> job.profile <<-EOF
			diffnam=${diffnam/_CONVPGD\.nam/}
			orog=$mitra/config/orog.txt
		EOF
	fi

	awk '$1=="'$conf'" {printf("ios=%s\n",$2);}' $cycle/ioservtable >>job.profile

	if [ $bin = "PGD" ]
	then
		cat >> job.profile <<-EOF
			c923=$CONST/const/923N
			ecoclimap=$CONST/clim/ecoclimap
			lfi2fa=$mitra/config/lfi2fa.txt
			sfxtools=$pack/bin/SFXTOOLS
		EOF

		tmpl=$mitra/config/pgdtmpl.sh
	elif echo $conf | grep -q C923
	then
		cat >> job.profile <<-EOF
			c923=$CONST/const/923N
			gridnam=$mitra/config/grid.nam
			lfi2fa=$mitra/config/lfi2fa.txt
		EOF

		tmpl=$mitra/config/job923tmpl.sh
	else
		if [ -n "$init" -a ! -s "$init" ] || [ -n "$initsfx" -a ! -s "$initsfx" ]
		then
			echo "IC file missing: $conf '$init' '$initsfx'" >> mit.err
			continue
		fi

		cat >> job.profile <<-EOF
			rrtm=$CONST/clim/rrtm
			ecoclimap=$CONST/clim/ecoclimap
		EOF

		tmpl=$mitra/config/jobtmpl.sh
	fi

	ntask=$((ntaskt-ntaskio))
	ntpn=$((ntaskt/nnodes))
	sed -e "s:_name:$name:g" -e "s:_ntaskt:$ntaskt:g" -e "s:_ntasks:$ntask:g" \
		-e "s:_ntaskio:$ntaskio:g" -e "s:_nnodes:$nnodes:g" -e "s:_ntpn:$ntpn:g" \
		-e "s:_nthreads:$nthread:g" -e "s:_maxmem:$mem:g" -e "s:_wall:$wall:g" \
		-e "/TAG PROFILE/r job.profile" -e "/TAG CONST/r const.txt" \
		-e "/TAG CLIM/r clim.txt" -e "/TAG FPOS/r fpos.txt" \
		-e "/TAG INIT/r init.txt" $tmpl > $conf.sh

	mkdir -p $ddcy/$conf
	ln -sf $PWD/$conf.sh $ddcy/$conf/$name.sh

	[ $nj -eq 0 ] && continue

	jobid=$(cd $ddcy/$conf; sbatch $name.sh | tail -1 | awk '{print $NF}')
	[ $verbose -eq 1 ] && echo "--> submitted job $jobid"
	jobids="$jobids $jobid"
	n=$((n+1))
	if [ $n -eq $nj ]
	then
		sleep $((3+nj/5))
		for jobid in $jobids
		do
			if [ -z "$(sacct -j $jobid -n)" ]
			then
				echo "Error on sacct output $jobid" >&2
				sacct -j $jobid
				continue
			fi

			while sacct -j $jobid -o state,jobid -nPX | grep -qiE $instates
			do
				sleep 5
			done
		done

		n=0
		jobids=""
	fi
done

rm -f job.profile const.txt clim.txt fpos.txt init.txt
