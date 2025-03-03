#!/bin/sh

set -e

mitra=~/mitraille

usage()
{
	printf "
Description:
	Test a list of IFS, ARPEGE, ALADIN, AROME, ALARO, PGD, FP,... configurations

Usage:
	mitraillette.sh -cycle CYCLE -rc rcfile [-conf conf] [-opt OPT] [-noenv] \
[-b bin] [-t time] [-nn nnodes] [-omp nomp] [-nj njobs] [-ref refpath] [-info] \
[-base YYYYMMDD -res HH] [-prof] [-force] [-i] [-f] [-nogp] [-h]

Arguments:
	CYCLE: IFS cycle tag name (following 'cyNN[t1][_main|r1].vv') where to \
find IFS binaries
	rcfile: resource file for a model job (cf Details)
	-conf: filter for configuration name, as referenced in profil_table
	-OPT: pack option, according to pack naming (default: '2y')
	-noenv: do not export (current) environment in job scripts. Note: \
environment is set from shell's startup, as login shell (-> .profile).
	-b: filter for binary, setting and running jobs only for binary 'bin'
	-t: filter for maximum time execution
	-nn: filter for maximum nnodes SLURM allocation
	-omp: filter for maximum nomp threads
	-nj: submit at most njobs jobs at a time (defaults to 0: no jobs running)
	-ref: path to jobs reference output
	-hpc: let job conf completion and comparison (ifever asked for) being \
looked for on HPC named MACHINE as an alternative to job local directory
	-info: only print info on jobs that have succeeded and failed
	-base/-res: run jobs on the specified base date and hour. If so, variable data \
must exist (set in rcfile or in env) and point to initial files as a path following \
pattern [HH]/[YYYYMMDD]/[initfile].
	-prof: only print info on jobs profiles
	-force: keep on submitting jobs even if any previously submitted job failed
	-f: rerun jobs even when already completed
	-i: submit jobs in interactive mode. Only small jobs are allowed (1 node, < \
20 omp).
	-nogp: in norms checking, activate -nogp option (no grid-point norms, cf \
normdiff.sh)
	-nosurf: in norms checking, activate -nosurf option (no norms for surface fields, \
cf normdiff.sh)
	-h: print this help and exit normally

Details:
	rcfile is sourced and can or must set the following (interactive) variables:
		- dirout: path to root directory of job execution (default: '$TMPDIR')
		- config: path to alternative mitraillette settings (default: mitraillette settings)
		- const: path to constant files (constants, clims, coupling files, \
guess and analysis files, default: path to mitraillette constants)
		- packs: path to packs, one of them corresponding to CYCLE and opt
	These variables are used in here as shell commands, hence do not need to \
be in environment.

	Batch jobs extend variable PATH to contain path(s) to xpnam and io_poll. Any \
other environment variable (to be used in the binary) may be added in user's \
environment, either in current one or preferably in default one (ie startup \
file .bashrc).

	Filters act on both jobs setting and execution.

	Alternative HPC actions for completion and comparison (option -hpc) use \
SSH protocol for connexion. Master mode is used for optimization reasons.

Dependencies:
	if comparison is asked (option -ref), utilities normdiff.sh
"
}

# not used (could be usefull when init file names don't show month in standard way)
getbase()
{
	DR_HOOK=0 epy_dump.py $1 -f frame | grep 'Base date/time' | \
		sed -re 's/ *Base .+: *([0-9]{8}) .+/\1/'
	#epy_what.py $1 | grep 'Basis' | \
	#	sed -re 's/ *Basis *: *([-: 0-9])/\1/' | sed -re 's/[-: ]//g'
}

logdiff()
{
	local rrconf=$ref/$conf/$bb

	if [ "$hpc" ] && [ ! -e $rrconf/jobOK -o ! -s $rrconf/NODE.001_01 ]
	then
		mkdir -p $rrconf
		scp -qo 'Controlpath=/tmp/ssh-%r@%h:%p' $hpc:$rrconf/jobOK \
			$hpc:$rrconf/NODE.001_01 $rrconf || return
	fi

	if [ ! -e $rrconf/jobOK -o ! -s $rrconf/NODE.001_01 ]
	then
		echo "--> no ref log (jobOK + NODE.001_01) on '$rrconf'"
		return
	fi

	if ! grep -qi 'spectral norms' $rrconf/NODE.001_01
	then
		echo "--> no spectral norms"
		return
	fi

	normdiff.sh $rrconf/NODE.001_01 $ddconf/NODE.001_01 $nogp $nofp $nosurf
}

statdiff()
{
	local fic ficref rrconf=$ref/$conf/$bb

	find $rrconf -name ARPE.\*.\* | grep -E '\.[0-9]{4}\.[A-Z0-9_]+$' > diff.txt ||
	{
		echo "--> no reference diff file to compare to"
		return 1
	}

	while read ficref
	do
		fic=$ddconf/$(basename $ficref)
		{
			[ -s $ficref.info ] || epy_what.py $ficref -o > $ficref.info
			[ -s $fic.info ] || epy_what.py $fic -o > $fic.info
		} 2> epy_what.err || cat epy_what.err 1>&2
		diff -q $ficref.info $fic.info || true
		DR_HOOK=0 epy_stats.py -l $fic.info -D $ficref $fic -O $fic.diff 2> epy_stats.err ||
			cat epy_stats.err 1>&2
		grep -E '^[A-Z0-9_]+ +-?[0-9]+' $fic.diff | grep -vE ' +(0\.0+E\+?0+ +){3,}' ||
			true
	done < diff.txt

	statdiff.sh $ddconf
}

jobwait()
{
	local jobid conf ddconf
	local stats="CONFIGURING|COMPLETING|PENDING|RUNNING|RESIZING|SUSPENDED"

	sleep 1.5

	while read jobid conf
	do
		[ -z "$(sacct -nXj $jobid)" ] && { sleep 1;
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

		sacct -nPXj $jobid -o state | grep -vi COMPLETED && continue

		ddconf=$ddcy/$conf/$bb
		[ -s $ddconf/NODE.001_01 ] && grep -iE '\<nan\>' $ddconf/NODE.001_01 || true

		[ -n "$ref" ] && logdiff
	done < jobs.txt
}

if [ $# -eq 0 ]
then
	usage
	exit
fi

cycle=""
rcfile=""
conf=""
opt="2y"
env="ALL"
bin0=""
confre=""
time=1000
nn=1000
nomp=400
nj=0
ref=""
info=0
prof=0
force=0
rerun=0
inter=0
nogp=""
nofp=""
nosurf=""
hpc=""

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
			confre=$2
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
		-base)
			base=$2
			shift
			;;
		-res)
			res=$(echo $2 | sed -re 's:0*([0-9]):\1:')
			shift
			;;
		-ref)
			ref=$2
			shift
			;;
		-hpc)
			hpc=$2
			shift
			;;
		-info) info=1;;
		-prof) prof=1;;
		-force) force=1;;
		-nogp) nogp="-nogp";;
		-nofp) nofp="-nofp";;
		-nosurf) nosurf="-nosurf";;
		-f) rerun=1;;
		-i) inter=1;;
		*)
			echo "Error: unknown option '$1'" >&2
			exit 1
			;;
	esac

	shift
done

if [ -z "$cycle" -o -z "$rcfile" ]
then
	printf "Error: mandatory arguments missing
cycle: '$cycle'
rcfile: '$rcfile'
" >&2
	exit 1
fi

# default values
packs=""
config=$mitra/config
const=$mitra/const
dirout=$TMPDIR

. $rcfile

if [ -z "$packs" -o -z "$config" -o -z "$const" -o -z "$dirout" ]
then
	printf "Error: rc variables not set
dirout: '$dirout'
config: '$config'
const: '$const'
packs: '$packs'
" >&2
	exit 1
elif [ ! -d $packs -o ! -d $config -o ! -d $const -o ! $dirout ]
then
	echo "Error: mandatory directories missing" >&2
	ls -d $packs/ $config/ $const/ $dirout/
fi

cy=$(basename $cycle)
pack=$packs/$cy
[ -d $pack ] || pack=$(find -L $packs -maxdepth 1 -type d -name $cy\*.$opt.pack | tail -1)
[ -z "$pack" ] && pack=$(find -L $packs -maxdepth 1 -type d -name $cy\*.$opt | tail -1)
[ -z "$pack" ] && pack=$(find -L $packs -maxdepth 1 -type d -name $cy\* | tail -1)

if [ -z "$pack" ]
then
	echo "Error: no pack named '$cy*' on '$packs'" >&2
	exit 1
fi

echo "IFS pack found is '$pack'"

const=$(cd $const > /dev/null && pwd)
dirout=$(cd $dirout > /dev/null && pwd)
ana=$const/analyses
anasfx=$const/anasurfex
coupling=$const/coupling
bb=""

if [ -n "$base" -a -n "$res" ]
then
	if [ -z "$data" ]
	then
		echo "Error: mandatory arguments missing
data: '$data'" >&2
		exit 1
	fi

	RES=$(printf "%02d" $res)
	ls $data/$RES/$base/ > /dev/null

	bb=$RES/$base
	ana=$data/$bb
	anasfx=$data/$bb
	coupling=$data/$bb
fi

if [ -d $cycle ]
then
	cycle=$(cd $cycle > /dev/null && pwd)
	echo "--> use user's jobs directory $cycle"
else
	echo $cycle | grep -vqE '^/' && cycle=$mitra/$cycle
	ls $cycle/ > /dev/null
fi

ddcy=$dirout/$cy

if [ "$hpc" ]
then
	[ -z "$HOSTNAME" ] && echo "Info: no variable HOSTNAME to compare to"
	if [ $hpc = "${HOSTNAME/login*/}" ]
	then
		echo "Info: alternative HPC is current one (${HOSTNAME/login*/})"
		hpc=""
	fi
fi

if [ "$hpc" ]
then
	# connection in mode master with control socket file
	# batchmode for disabling password authentification
	# must be in background (-f) for keeping connection alive (like a server)
	# subsequent scp's replace -S 'file' with -o 'Controlpath=file'
	ssh -f -o 'batchmode=yes' -S '/tmp/ssh-%r@%h:%p' -M $hpc bash
fi

if [ "$ref" ] && [ ! -d $ref ]
then
	ref=$dirout/$ref
	ls $ref/ >/dev/null
	type normdiff.sh > /dev/null || PATH=$PATH:$mitra
fi

tmpdir=$(mktemp --tmpdir -d mitraXXX)
trap 'rm -r $tmpdir' 0

cp -r $mitra/config $tmpdir
if ! diff -rq $config $mitra/config > /dev/null
then
	echo "--> use local directory $config"
	cp -r $config $tmpdir
fi

cd $tmpdir

if [ $info -eq 1 ]
then
	find $ddcy -maxdepth 2 -name jobOK -printf "%h\n" | sed -re "s:$dirout/::" | sort > jok
	echo "Jobs completed:"
	cat jok
	echo "Jobs failed:"
	find $ddcy -maxdepth 2 -name mpi\*.out -printf "%h\n" | sed -re "s:$dirout/::" | \
		sort | grep -vf jok
	exit
fi

grep -vE '^\s*#' config/profil_table | \
	while read conf bin mem wall cpu ntaskio ntaskt nnodes nthread
do
	[ -n "$bin0" -a $bin != "$bin0" ] && continue
	[ -n "$confre" ] && echo $conf | grep -qvE "$confre" && continue
	[ $wall -gt $time -o $nnodes -gt $nn -o $nthread -gt $nomp ] && continue

	echo $conf >> jobmatch.txt
	if [ $prof -eq 1 ]
	then
		echo -e "$conf: $wall' $nnodes nodes, ${ntaskt}x$nthread MPI/OMP"
		continue
	fi

	ddconf=$ddcy/$conf
	[ -n "$bb" ] && ddconf=$ddconf/$bb

	if [ ! -e $ddconf/jobOK ] && [ "$hpc" ]
	then
		mkdir -p $ddconf
		scp -qo 'Controlpath=/tmp/ssh-%r@%h:%p' $hpc:$ddconf/jobOK \
			$hpc:$ddconf/NODE.001_01 $ddconf 2>/dev/null || true
	fi

	if [ -e $ddconf/jobOK -a $rerun -eq 1 ]
	then
		echo "--> job $conf already completed, rerun asked"
		rm $ddconf/*OK
	fi

	if [ -e $ddconf/jobOK ]
	then
		echo "--> job $conf already completed"
		[ -s $ddconf/NODE.001_01 ] && grep -iE '\<nan\>' $ddconf/NODE.001_01 || true
		[ -n "$ref" ] && logdiff

		continue
	elif [ $force -eq 0 ] && ! grep -qE "^$conf$" config/validconfs.txt
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
		*_PGD*) name=pgd;;
		*_DILA*) name=dila;;
		*_ANSU_*) name=anasurf;;
		*_SCRE_*) name=screen;;
		*_MINI_*) name=minim;;
		GM_*) name=arpege;;
		GE_*) name=ifs;;
		L[123]_*LACE*|L[123]_*_ALR*) name=alaro;;
		L[123]_*) name=arome;;
		*)
			name=model;;
	esac

	echo "Setting job $conf in $name.sh $bin $wall' ($nnodes nodes, ${ntaskt}x$nthread MPI/OMP)"

	{
		awk -v dd=$ana '$1=="'$conf'" {
			printf("ln -sfv %s/%s %s\n",dd,$2,$3);}' config/initable
		awk -v dd=$anasfx '$1=="'$conf'" {
			printf("ln -sfv %s/%s %s\n",dd,$2,$3);}' config/inisfxtable
	} > init.txt

	awk -v dd=$const/pgd '$1=="'$conf'" {
		printf("ln -sfv %s/%s %s\n",dd,$2,$3);}' config/constable > const.txt

	if [ -n "$base" -a -s init.txt ]
	then
		finit=$(head -1 init.txt | sed -re 's:ln \-sfv ([^ ]+) .+:\1:')
		ls $finit > /dev/null
		#MM=$(getbase $finit | cut -c5-6)
		MM=$(echo $base | cut -c5-6)
		if [ -z "$MM" ] || [ $(echo $base | cut -c5-6) != $MM ]
		then
			echo "Error: month '$MM' not found in '$finit'" >&2
			exit 1
		fi
	fi

	{
		awk -v dd=$const/clim -v mm=".m$MM" '$1=="'$conf'" {
			fclim = gensub("\\.mMONTH$",mm,"",gensub("^PATH",dd,"",$2));
			printf("ln -sfv %s %s\n",fclim,$3);
			}' config/climtable

		awk -v dd=$const/clim -v mm=".m$MM" '$1=="'$conf'" {
			fclim = gensub("\\.mMONTH$",mm,"",$2);
			printf("ln -sfv %s/%s %s\n",dd,fclim,$3);
			}' config/climfptable config/filtertable
	} > clim.txt

	if [ -s config/obstable ]
	then
		awk -v dd=$const/obs '$1=="'$conf'" {
			printf("cp -rf %s/%s/*CMA* .\n",dd,$2);}' config/obstable > odb.txt
	fi

	if [ -s config/stattable ]
	then
		awk -v dd=$const/const '$1=="'$conf'" {
			printf("ln -sf %s/%s/* .\n",dd,$2);}' config/sattable > sat.txt

		awk -v dd=$const/stat '$1=="'$conf'" {
			printf("ln -sf %s/* .\n",dd);}' config/stattable > stat.txt
	fi

	{
		if [ -x $pack/bin/lfitools ]
		then
			lfitools=$pack/bin/lfitools
		elif [ -x $pack/bin/LFITOOLS ]
		then
			lfitools=$pack/bin/LFITOOLS
		else
			lfitools=$(ls -t1 $packs/*.2y.pack/bin/lfitools 2>/dev/null | head -1)
			[ -n "$lfitools" ] && [ -x $lfitools ] ||
				lfitools=$(ls -t1 $packs/*.2y.pack/bin/LFITOOLS 2>/dev/null | head -1)
			[ -n "$lfitools" ] && [ -x $lfitools ] ||
				lfitools=$(ls -t1 ~gco/packs/*.2y.pack/bin/lfitools 2>/dev/null | head -1)
			[ -n "$lfitools" ] && [ -x $lfitools ] ||
				lfitools=$(ls -t1 ~gco/packs/*.2y.pack/bin/LFITOOLS 2>/dev/null | head -1)
		fi

		if [ "$lfitools" ]
		then
			echo "export LFITOOLS=$lfitools"
		else
			echo "Warning: no binary LFITOOLS" >&2
		fi

		cat <<-EOF
			export OMP_NUM_THREADS=$nthread
			varenv=config/varenv.txt
			nam=$cycle/deltanam/$conf.nam
			bin=$pack/bin/$bin
		EOF

		find $cycle/selnam/ -name $conf.\* -printf 'selnam=%p\n'
		find $cycle/fcnam/ -name $conf.\* | \
			sed -re 's:(.+)\.nam[0-9]+$:fcnam=\1.nam:' | uniq
		find $cycle/deltaquad/ -name $conf.\* -printf "quadnam=%p\n"
		awk '$1=="'$conf'" {printf("pgd=%s\n",$2);}' config/pgdtable
		awk '$1=="'$conf'" {printf("pgdfa=../%s/%s\n",$2,$3);}' config/pgdfatable
		awk -v dd=$coupling '$1=="'$conf'" {
			printf("lbc=%s\n",gensub("^PATH",dd,"",$2));}' config/coupltable
		awk '$1=="'$conf'" {printf("ios=%s\n",$2);}' config/ioservtable

		if [ -n "$base" -a -n "$data" ]
		then
			awk -v dd=$data/$RES/$base '$1=="'$conf'" {printf("save=%s\n",dd);}' \
				config/savetable
		fi
	} > job.profile

	awk -v dd=$cycle/fpnam '$1=="'$conf'" {printf("cp %s/%s %s\n",dd,$2,$3);}' \
		config/fptable > fpos.txt
	fpnam=$(cut -d " " -f3 fpos.txt | sed -re 's:[0-9]+$::' | uniq)
	[ "$fpnam" ] && echo "fpnam=$fpnam" >> job.profile

	diffnam=$(find $cycle/diffnam -name ${conf}_CONVPGD.nam)
	if [ "$diffnam" ]
	then
		cat >> job.profile <<-EOF
			diffnam=${diffnam/_CONVPGD\.nam/}
			orog=config/orog.txt
		EOF
	fi

	if [ $bin = "MASTER911" ]
	then
		tmpl=config/job911tmpl.sh
	elif [ $bin = "PGD" ]
	then
		cat >> job.profile <<-EOF
			c923=$const/const/923N
			ecoclimap=$const/clim/ecoclimap
			lfi2fa=config/lfi2fa.txt
			sfxtools=$pack/bin/SFXTOOLS
		EOF

		tmpl=config/pgdtmpl.sh
	elif echo $conf | grep -q C923
	then
		cat >> job.profile <<-EOF
			c923=$const/const/923N
			gridnam=config/grid.nam
			lfi2fa=config/lfi2fa.txt
		EOF

		tmpl=config/job923tmpl.sh
	else
		init=$(grep -E ' (EBAUCHE|ICMSH\w+INIT)$' init.txt | sed -re 's:.+ (.+) .+:\1:')
		if [ -n "$init" ] && [ ! -s $init ]
		then
			echo "Warning: IC file missing (cont'd): '$init'" >&2
			continue
		fi

		cat >> job.profile <<-EOF
			rrtm=$const/clim/rrtm
			ecoclimap=$const/clim/ecoclimap
		EOF

		tmpl=config/jobtmpl.sh
	fi

	ntask=$((ntaskt-ntaskio))
	ntpn=$((ntaskt/nnodes))

	echo "Creating $ddconf"
	mkdir -p $ddconf

	[ -s odb.txt ] && sed -e "s:_ntasks:$ntask:g" config/odb$name.sh >> odb.txt

	cp config/IFSenv.txt config/env.sh $ddconf
	if [ -s $cycle/$bin.nml ]
	then
		cp $cycle/$bin.nml $ddconf/vide.nml
	elif [ -s config/$bin.nml ]
	then
		cp config/$bin.nml $ddconf/vide.nml
	elif [ -s $cycle/vide.nml ]
	then
		cp $cycle/vide.nml $ddconf
	else
		cp config/vide.nml $ddconf
	fi

	sed -e "s:_name:$name:g" -e "s:_ntaskt:$ntaskt:g" \
		-e "s:_ntasks:$ntask:g" -e "s:_ntaskio:$ntaskio:g" \
		-e "s:_nnodes:$nnodes:g" -e "s:_ntpn:$ntpn:g" \
		-e "s:_nthreads:$nthread:g" -e "s:_maxmem:$mem:g" -e "s:_wall:$wall:g" \
		-e "s:_varexp:$env:" -e "/TAG PROFILE/r job.profile" \
		-e "/TAG CONST/r const.txt" -e "/TAG CLIM/r clim.txt" -e "/TAG SAT/r sat.txt" \
		-e "/TAG ODB/r odb.txt" -e "/TAG STAT/r stat.txt" -e "/TAG FPOS/r fpos.txt" \
		-e "/TAG INIT/r init.txt" $tmpl > $ddconf/$name.sh
	[ $name = "screen" ] && sed -i -re 's:(ICM..)ARPE:\1SCRE:g' $ddconf/$name.sh
	[ $name = "minim" ] && sed -i -re 's:(ICM..)ARPE:\1MINI:g' $ddconf/$name.sh
	[ $name = "anasurf" ] && sed -i -re 's:(ICM..)ARPE:\1CANS:g' $ddconf/$name.sh

	[ $nj -eq 0 ] && continue

	if [ $inter -eq 1 ]
	then
		if [ $nnodes -gt 1 -o $((ntaskt*nthread)) -gt 20 ]
		then
			echo "Error: job too big for interactive submission" >&2
			exit 1
		fi

		echo "--> interactive job submission for conf $conf"
		chmod u+x $ddconf/$name.sh
		(cd $ddconf; $name.sh)
		continue
	fi

	jobid=$(cd $ddconf; sbatch $name.sh)
	jobid=$(echo $jobid | tail -1 | awk '{print $NF}')
	echo "--> job submitted for conf $conf - jobid: $jobid"
	if [ -z "$jobid" ] || ! echo $jobid | grep -qE '^[0-9]+$'
	then
		echo "Error: unknown jobid format for conf $conf" >&2
		exit 1
	fi

	echo "$jobid $conf" >> jobs.txt
	if [ $(wc -l jobs.txt | awk '{print $1}') -eq $nj ]
	then
		jobwait
		rm jobs.txt
	fi
done

[ -s jobs.txt ] && jobwait

if [ ! -s jobmatch.txt ]
then
	echo "Info: no job matched the conditions"
fi
