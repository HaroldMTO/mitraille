#!/bin/sh

set -e

mitra=~/mitraille

alias spdiff='~marguina/mitraille/diff'

usage()
{
	printf "
Description:
	Test a list of IFS, ARPEGE, ALADIN, AROME, ALARO, PGD, FP,... configurations

Usage:
	mitraillette.sh -cycle CYCLE -rc rcfile [-conf conf] [-opt opt] [-noenv] \
[-b bin] [-t time] [-nn nnodes] [-omp nomp] [-nj njobs] [-ref refpath] [-force] \
[-v]

Arguments:
	CYCLE: IFS cycle tag name (following 'cyNN[t1][_main|r1].vv') where to find \
IFS binaries
	rcfile: resource file for a model job
	-conf: filter for configuration name, as referenced in profil_table
	-opt: pack option, according to pack naming (default: '2y')
	-noenv: do not export (current) environment in job scripts. Note: \
environment is set from shell's startup, as login shell (-> .profile).
	-b: filter for binary, setting and running jobs only for binary 'bin'
	-t: filter for maximum time execution
	-nn: filter for maximum nnodes SLURM allocation
	-omp: filter for maximum nomp threads
	-nj: submit at most njobs jobs at a time (defaults to 0: no jobs running)
	-ref: path to jobs reference output
	-force: keep on submitting jobs even if any previously submitted job failed
	-v: verbose mode

Details:
	rcfile is sourced and must set the following (interactive) variables:
		- dirout: path to root directory of job execution
		- const: path to constant files (constants, clims, coupling files, \
guess and analysis files)
		- packs: path to packs, one of them corresponding to CYCLE and opt
	These variables are used in here as shell commands and so do not need to be \
in environment.

	Batch jobs need variable PATH contain path(s) to xpnam and io_poll. Any \
other environment variable

	Filters act on both jobs setting and execution.

Dependencies:
	None
"
}

logdiff()
{
	if [ $# -ne 2 ]
	then
		echo "usage: logdiff file1 file2" >&2
		return 1
	fi

	spdiff $1 $2 | grep -vE '^$' | sed -re 's:^# +:STEP(s)\t:' -e 's: +$::' \
		-e 's: {2,}([A-Z]+):\t\1:g' -e 's:([0-9]+)\.[0-9]+e[+-]?[0-9]+ +::g' ||
		true
}

jobwait()
{
	local jobid conf
	local stats="CONFIGURING|COMPLETING|PENDING|RUNNING|RESIZING|SUSPENDED"

	sleep 2
	while read jobid conf
	do
		[ -z "$(sacct -nXj $jobid)" ] && { sleep 2;
			[ -z "$(sacct -nXj $jobid)" ] && sleep 2; }
		if [ -z "$(sacct -nXj $jobid)" ]
		then
			echo "Error on sacct output $jobid" >&2
			sacct -j $jobid
			continue
		fi

		while sacct -nPXj $jobid -o state | grep -qiE $stats
		do
			sleep 5
		done

		[ $force -eq 0 ] && sacct -nPXj $jobid -o state | grep -vi COMPLETED &&
			continue

		[ -z "$ref" ] && continue

		if [ ! -s $ref/$conf/NODE.001_01 ]
		then
			echo "--> no ref log for conf $conf"
			continue
		fi

		if grep -qi 'spectral norms' $ref/$conf/NODE.001_01
		then
			logdiff $ddcy/$conf/NODE.001_01 $ref/$conf/NODE.001_01
		else
			echo "no spectral norms"
		fi
	done < jobs.txt
}

help=0
cycle=""
rcfile=""
conf=""
opt="2y"
env="ALL"
bin0=""
conf0=""
time=1000
nn=1000
nomp=100
nj=0
ref=""
verbose=0
force=0

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
			shift
			;;
		-conf)
			conf0=$2
			shift
			;;
		-opt)
			opt=$2
			shift
			;;
		-noenv) env="NONE";;
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
		-ref)
			ref=$2
			shift
			;;
		-force) force=1;;
		-v) verbose=1;;
		-h) help=1;;
		*)
			echo "Error: unknown option '$1'" >&2
			exit 1;;
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

if [ -z "$packs" -o -z "$const" -o -z "$dirout" ]
then
	printf "Error: rc variables not set
dirout: '$dirout'
const: '$const'
packs: '$packs'
" >&2
	exit 1
elif [ ! -d $packs -o ! -d $const -o ! $dirout ]
then
	printf "Error: mandatory directories missing" >&2
	ls -d $packs $const $dirout
fi

pack=$(find $packs -maxdepth 1 -type d -follow -name $(basename $cycle)\*.$opt.pack | \
	tail -1)
if [ -z "$pack" ]
then
	echo "Error: no pack named '$(basename $cycle)*.$opt.pack' on '$packs'" >&2
	exit 1
fi

echo "IFS pack found is '$pack'"

if [ ! -d $cycle ]
then
	cycle=$mitra/$cycle
	ls -d $cycle >/dev/null
fi

cycle=$(cd $cycle > /dev/null && pwd)
ddcy=$dirout/$(basename $cycle)
if [ "$ref" ] && [ ! -d $ref ]
then
	ref=$dirout/$ref
	ls -d $ref >/dev/null
fi

rm -f jobs.txt
grep -vE '^\s*#' $mitra/config/profil_table | \
	while read conf bin mem wall cpu ntaskio ntaskt nnodes nthread
do
	[ -n "$bin0" -a $bin != "$bin0" ] && continue
	[ -n "$conf0" ] && echo $conf | grep -qvE "$conf0" && continue
	[ $wall -gt $time -o $nnodes -gt $nn -o $nthread -gt $nomp ] && continue

	if [ -e $ddcy/$conf/jobOK ]
	then
		echo "--> job $conf already completed"
		if [ "$ref" ]
		then
			if [ ! -s $ref/$conf/NODE.001_01 ]
			then
				echo "--> no ref log for conf $conf"
				continue
			fi

			if grep -qi 'spectral norms' $ref/$conf/NODE.001_01
			then
				logdiff $ddcy/$conf/NODE.001_01 $ref/$conf/NODE.001_01
			else
				echo "no spectral norms"
			fi
		fi

		continue
	elif [ $force -eq 0 ] && ! grep -qE "^$conf$" $mitra/config/validconfs.txt
	then
		echo "--> invalid conf $conf"
		continue
	fi

	if [ ! -x $pack/bin/$bin ]
	then
		echo "Error: no executable $bin on $pack/bin/$BIN" >&2
		exit 1
	fi

	case $conf in
		*_PGDC_*)
			echo "--> by-passing PGDC conf $conf" >&2
			continue;;
		*_PGD*) name=pgd;;
		*_DILA*) name=dila;;
		GM_*) name=arpege;;
		GE_*) name=ifs;;
		L[123]_*) name=alaro;;
		*)
			echo "Error: unknown model name for $conf"
			exit 1;;
	esac

	[ $verbose -ne 0 ] && echo "Setting conf $conf $nnodes $wall' $bin"

	cat > job.profile <<-EOF
		export OMP_NUM_THREADS=$nthread
		export LFITOOLS=$pack/bin/LFITOOLS
		varenv=$cycle/varenv.txt
		nam=$cycle/namelist/$conf.nam
		bin=$pack/bin/$bin
	EOF

	awk '$1=="'$conf'" {printf("pgd=%s\n",$2);}' $cycle/pgdtable >> job.profile
	awk '$1=="'$conf'" {printf("pgdfa=../%s/%s\n",$2,$3);}' $cycle/pgdfatable \
		>> job.profile

	awk -v dd=$const/analyses '$1=="'$conf'" {printf("ln -sfv %s/%s %s\n",dd,$2,$3);}' \
		$cycle/initable > init.txt

	awk -v dd=$const/anasurfex '$1=="'$conf'" {printf("initsfx=%s/%s\n",dd,$2);}' \
		$cycle/inisfxtable >> job.profile

	awk -v dd=$const/pgd '$1=="'$conf'" {printf("ln -sfv %s/%s %s\n",dd,$2,$3);}' \
		$cycle/constable > const.txt

	awk -v dd=$const/clim '$1=="'$conf'" {printf("ln -sfv %s/%s %s\n",dd,$2,$3);}' \
		$cycle/climtable $cycle/climfptable $cycle/filtertable > clim.txt

	awk -v dd=$const/coupling '$1=="'$conf'" {printf("lbc=%s/%s\n",dd,$2);}' \
		$cycle/coupltable >> job.profile

	awk -v dd=$cycle/fpnam '$1=="'$conf'" {printf("cp %s/%s %s\n",dd,$2,$3);}' \
		$cycle/fptable > fpos.txt
	fpnam=$(cut -d " " -f3 fpos.txt | sed -re 's:[0-9]+$::' | uniq)
	[ "$fpnam" ] && echo "fpnam=$fpnam" >> job.profile

	find $cycle/quadnam/ -name $conf.\* -printf "quadnam=%p\n" >> job.profile

	find $cycle/fcnam/ -name $conf.\* | \
		sed -re 's:(.+)\.nam[0-9]+$:fcnam=\1.nam:' | uniq >> job.profile

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

	if [ $bin = "MASTER911" ]
	then
		tmpl=$mitra/config/job911tmpl.sh
	elif [ $bin = "PGD" ]
	then
		cat >> job.profile <<-EOF
			c923=$const/const/923N
			ecoclimap=$const/clim/ecoclimap
			lfi2fa=$mitra/config/lfi2fa.txt
			sfxtools=$pack/bin/SFXTOOLS
		EOF

		tmpl=$mitra/config/pgdtmpl.sh
	elif echo $conf | grep -q C923
	then
		cat >> job.profile <<-EOF
			c923=$const/const/923N
			gridnam=$mitra/config/grid.nam
			lfi2fa=$mitra/config/lfi2fa.txt
		EOF

		tmpl=$mitra/config/job923tmpl.sh
	else
		init=$(grep -E ' (EBAUCHE|ICMSHARPEINIT)$' init.txt | \
			sed -re 's:.+ (.+) .+:\1:')
		if [ -n "$init" -a ! -s "$init" ]
		then
			echo "--> IC file missing (cont'): $conf '$init'"
			continue
		fi

		cat >> job.profile <<-EOF
			rrtm=$const/clim/rrtm
			ecoclimap=$const/clim/ecoclimap
		EOF

		tmpl=$mitra/config/jobtmpl.sh
	fi

	ntask=$((ntaskt-ntaskio))
	ntpn=$((ntaskt/nnodes))
	mkdir -p $ddcy/$conf
	sed -e "s:_name:$name:g" -e "s:_ntaskt:$ntaskt:g" -e "s:_ntasks:$ntask:g" \
		-e "s:_ntaskio:$ntaskio:g" -e "s:_nnodes:$nnodes:g" -e "s:_ntpn:$ntpn:g" \
		-e "s:_nthreads:$nthread:g" -e "s:_maxmem:$mem:g" -e "s:_wall:$wall:g" \
		-e "s:_varexp:$env:" -e "/TAG PROFILE/r job.profile" \
		-e "/TAG CONST/r const.txt" -e "/TAG CLIM/r clim.txt" \
		-e "/TAG FPOS/r fpos.txt" -e "/TAG INIT/r init.txt" $tmpl \
		> $ddcy/$conf/$name.sh

	[ $nj -eq 0 ] && continue

	jobid=$(cd $ddcy/$conf; sbatch $name.sh | tail -1 | awk '{print $NF}')
	echo "--> job submitted for conf $conf - jobid: $jobid"
	echo "$jobid $conf" >> jobs.txt
	if [ $(wc -l jobs.txt | awk '{print $1}') -eq $nj ]
	then
		jobwait
		rm jobs.txt
	fi
done

[ -s jobs.txt ] && jobwait

rm -f job.profile const.txt clim.txt fpos.txt init.txt jobs.txt
