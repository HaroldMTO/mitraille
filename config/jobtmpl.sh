#!/bin/sh

#SBATCH -p normal64
#SBATCH -J _name
#SBATCH -N _nnodes
#SBATCH -n _ntaskt
#SBATCH -c _nthreads
#SBATCH --time "_wall"
#SBATCH --exclusiv
#SBATCH -o _name.log

if [ "$SLURM_JOB_NAME" ]
then
	printf "SLURM job card:
	Number of nodes: $SLURM_JOB_NUM_NODES
	Number of tasks: $SLURM_NTASKS
	Tasks per node: $((SLURM_NTASKS/SLURM_JOB_NUM_NODES))
	Number of threads per task: $SLURM_CPUS_PER_TASK
"
fi

ulimit -s unlimited
env > env.txt

set -e

alias mpiexe='mpiauto --verbose --wrap -np _ntaskt -nnp _ntpn --'
alias lnv='ln -sfv'

echo "Setting job profile" #TAG PROFILE

if [ -z "$nam" -o -z "$bin" -o -z "$rrtm" ]
then
	echo "Error: mandatory variables not set
nam: '$nam'
bin: '$bin'
rrtm: '$rrtm'
" >&2
	exit 1
fi

echo "Linking clims and filters for Surfex and FullPOS (if required)" # TAG CLIM

echo "Linking constants for RRTM radiation scheme"
lnv $rrtm/* .

echo "Linking Initial Conditions" # TAG INIT

# conf GM 400, 500
if [ -s EBAUCHE ]
then
	cp -f EBAUCHE ICMSHARPEINIT
	chmod 644 ICMSHARPEINIT
fi

# conf GM/LAM 400, 500, 600
[ -s ICMSHARPEINIT ] && cp -f ICMSHARPEINIT ICMSHARPEIMIN

if [ "$initsfx" ]
then
	echo "Linking Initial Condition and Ecoclimap constants for Surfex"
	lnv $initsfx ICMSHARPEINIT.sfx
	lnv $ecoclimap/* .
fi

if [ "$lbc" ]
then
	echo "Getting Boundary Conditions files:"
	ls $lbc*

	i=0
	for fic in $(ls $lbc*)
	do
		if echo $fic | grep -q _COUPL999
		then
			ficout=ELSCFARPEALBC999
		else
			ficout=$(printf "ELSCFARPEALBC%03d" $i)
		fi

		lnv $fic $ficout
		i=$((i+1))
	done

	# 0 and 1 together (sometimes)
	[ $i -eq 1 ] && lnv $fic $(printf "ELSCFARPEALBC%03d" $i)
fi

echo "Getting main namelist"
cp $nam fort.4

# conf IFS
lnv fort.4 fort.25

if [ "$selnam" ]
then
	echo "Getting side namelist $selnam"
	fout=$(echo $selnam | sed -re 's:.+\.([^.]+\.nam):\1:')
	cp $selnam $fout

	# restart option: only for conf with SURFEX for the moment
	if [ "$diffnam" ]
	then
		echo "Make restart namelists for PGD from delta files:"
		ls ${diffnam}_CONVPGD.nam ${diffnam}_CONVPGD.selnam_exseg1
		xpnam --dfile="${diffnam}_CONVPGD.nam" --inplace fort.4
		xpnam --dfile="${diffnam}_CONVPGD.selnam_exseg1" --inplace $fout

		echo "Launch MPI job"
		mpiexe $bin > mpipgd.log 2> mpipgd.err

		mv ICMSHARPE+0000.sfx Const.Clim.sfx

		echo "Make namelist for PREP from delta file:"
		ls ${diffnam}_CONVPREP.nam
		cp $nam fort.4
		xpnam --dfile="${diffnam}_CONVPREP.nam" --inplace fort.4

		echo "Launch MPI job"
		mpiexe $bin > mpiprep.log 2> mpiprep.err
		mv ICMSHARPE+0000.sfx ICMSHARPEINIT.sfx

		echo "Change orography in PGD (Const.Clim.sfx)"
		$LFITOOLS testfa < $orog
	fi

	# reset initial namelists
	cp $nam fort.4
	cp $selnam $fout
fi

if [ "$fpnam" ]
then
	echo "Getting FPOS frequency namelists" # TAG FPOS

	for fic in $fpnam
	do
		# fpnam: ...[0-9] or ..fp
		ech=$(echo $fic | sed -re 's:.+([0-9]+|fp)$:\1:')
		if [ $ech = "fp" ]
		then
			i=0
			while [ $i -lt 24 ]
			do
				cp $fic $(printf "xxt%06d00" $i)
				i=$((i+1))
			done

			cp $fic xxt00010000
		elif [ $ech -eq 0 ]
		then
			cp $fic xxt00000000
		else
			cp $fic $(printf "xxt%06d00" $ech)
		fi
	done
fi

echo "Launch MPI job"
mpiexe $bin > mpi.log 2> mpi.err

if [ "$fcnam" ]
then
	echo "Launching other jobs"
	rm -f mpifc.log mpifc.err
	for fnam in $fcnam
	do
		cp $fnam fort.4
		mpiexe $bin >> mpifc.log 2>> mpifc.err
	done

	cp $nam fort.4
fi

if [ "$diffnam" ]
then
	echo "Launch MPI job with restart"
	mkdir start
	mv NODE.001_01 ICMSHARPE+* start
	mpiexe $bin >> mpidiff.log 2>> mpidiff.err

	echo "Compare last forecast step:"
	fcst=$(ls -1 ICMSHARPE+* | sort | tail -1)
	DR_HOOK=0 DR_HOOK_NOT_MPI=1 $LFITOOLS lfidiff --lfi-file-1 start/$fcst \
		--lfi-file-2 $fcst
fi

if [ "$ios" ]
then
	echo "Post-processing files (IO server)"
	$UTILS/io_poll --prefix ICMSH
	[ "$fpnam" ] && $UTILS/io_poll --prefix PF

	alias lnv='lfi_move -pack -force'
fi

echo "Rename files"
for fic in $(find -name \*ARPE+\* | grep -E 'ICMSH|PF|DHF(DL|ZO)')
do
	prefix=$(echo $fic | sed -re 's:\./(.+)ARPE.*\+[0-9]+:\1:')
	case $ftype in
		ICMSH) ftype=HIST;;
		DHFDL) ftype=DDHFDL;;
		DHFZO) ftype=DDHFZO;;
		PF) ftype=$(echo $fic | sed -re 's:PFARPE(.+)\+[0-9]+:\1:');;
	esac

	ech=$(echo $fic | sed -re 's:.+\+0{2,3}([0-9]{1,2}):\1:')
	lnv $fic $(printf "ARPE__ech%04d.$ftype\n" $ech)
done

echo "Log and profiling files:"
ls -l ifs.stat NODE.*

touch jobOK
