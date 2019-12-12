#!/bin/sh

#SBATCH -p normal64
#SBATCH -J _name
#SBATCH -N _nnodes
#SBATCH -n _ntaskt
#SBATCH -c _nthreads
#SBATCH --time "_wall"
#SBATCH --exclusiv
#SBATCH -o _name.log
#SBATCH --export=_varexp

cpnam()
{
	cp vide.nml $2
	tmpnam=$(mktemp tmpXXX.nam)
	sed -re "s/__NTASK_IO__/_ntaskio/" -e "s/__NTASKS__/_ntasks/" $1 > $tmpnam
	xpnam --dfile=$tmpnam --inplace $2
	unlink $tmpnam
}

if [ "$SLURM_JOB_NAME" ]
then
	printf "SLURM job card:
	Number of nodes: $SLURM_JOB_NUM_NODES
	Number of tasks: $SLURM_NTASKS
	Tasks per node: $((SLURM_NTASKS/SLURM_JOB_NUM_NODES))
	Number of threads per task: $SLURM_CPUS_PER_TASK
"
fi

lstRE="\.(log|out|err)|(ifs|meminfo|linux_bind|NODE|core|std(out|err))\."
alias mpiexe='mpiauto --wrap -np _ntaskt -nnp _ntpn --'
alias lnv='ln -sfv'

set -e

echo -e "\nSetting job profile" #TAG PROFILE

if [ -z "$nam" -o -z "$bin" -o -z "$rrtm" ]
then
	echo "Error: mandatory variables not set
nam: '$nam'
bin: '$bin'
rrtm: '$rrtm'
" >&2
	exit 1
fi

if [ -s env.sh ]
then
	echo -e "\nNoticeable missing environment variables:"
	vars=$(env | grep -f IFSenv.txt | sed -re 's:=.*::' | xargs | tr ' ' '|')
	if grep -vE "^($vars)$" IFSenv.txt
	then
		echo "--> new setting of all mandatory variables"
		. env.sh
	else
		echo "--> none"
	fi
fi

env > env.txt

if [ -s $varenv ]
then
	echo -e "\nPossibly influencing environment variables:"
	grep -f $varenv env.txt || echo "--> none"
fi

echo -e "\nStack limit: $(ulimit -s)"

echo -e "\nLinking clims and filters for Surfex and FullPOS (if required)" # TAG CLIM

echo -e "\nLinking constants for RRTM radiation scheme"
lnv $rrtm/* .

echo -e "\nLinking Initial Conditions" # TAG INIT

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
	echo -e "\nLinking Initial Conditions for Surfex"
	lnv $initsfx ICMSHARPEINIT.sfx
fi

if [ "$ecoclimap" ]
then
	echo -e "\nLinking Ecoclimap constants for Surfex"
	lnv $ecoclimap/* .
fi

if [ "$lbc" ]
then
	echo -e "\nGetting Boundary Conditions files:"
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

	# dirty: 0 and 1 together (sometimes)
	[ $i -eq 1 ] && lnv $fic $(printf "ELSCFARPEALBC%03d" $i)
fi

echo -e "\nGetting main namelist"
cpnam $nam fort.4

# conf IFS
lnv fort.4 fort.25

if [ "$selnam" ]
then
	echo -e "\nGetting side namelist $selnam"
	fout=$(echo $selnam | sed -re 's:.+\.(.+\.nam):\1:')
	cp $selnam $fout

	# restart option: only for conf with SURFEX for the moment
	if [ "$diffnam" ]
	then
		mkdir -p pgdprep
		# mandatory PGD specific environment: DR_HOOK_NOT_MPI
		export DR_HOOK_NOT_MPI=1

		echo -e "\nMake restart namelists for PGD from delta files:"
		ls ${diffnam}_CONVPGD.nam ${diffnam}_CONVPGD.selnam_exseg1
		xpnam --dfile="${diffnam}_CONVPGD.nam" --inplace fort.4
		xpnam --dfile="${diffnam}_CONVPGD.selnam_exseg1" --inplace $fout

		echo -e "\nLaunch MPI job"
		if [ ! -f pgdprep/Const.Clim.sfx ]
		then
			mpiexe $bin > mpipgd.out 2> mpipgd.err
			find -type f -newer $fout | grep -vE $lstRE | xargs ls -l

			mv ICMSHARPE+0000.sfx pgdprep/Const.Clim.sfx
		fi

		echo -e "\nMake namelist for PREP from delta file:"
		ls ${diffnam}_CONVPREP.nam
		cpnam $nam fort.4
		xpnam --dfile="${diffnam}_CONVPREP.nam" --inplace fort.4

		echo -e "\nLaunch MPI job"
		if [ ! -f pgdprep/ICMSHARPEINIT.sfx ]
		then
			mpiexe $bin > mpiprep.out 2> mpiprep.err
			find -type f -newer fort.4 | grep -vE $lstRE | xargs ls -l

			mv ICMSHARPE+0000.sfx pgdprep/ICMSHARPEINIT.sfx
		fi

		echo -e "\nChange orography in PGD (Const.Clim.sfx)"
		cp -f pgdprep/* .
		$LFITOOLS testfa < $orog

		# reset initial namelists
		cpnam $nam fort.4
	fi
fi

if [ "$fpnam" ]
then
	echo -e "\nGetting FPOS frequency namelists" # TAG FPOS

	for fic in $fpnam*
	do
		# fpnam: ...[0-9] or ..fp
		ech=$(echo $fic | sed -re 's:[^0-9]+([0-9]+|fp)$:\1:')
		if [ $ech = "fp" ]
		then
			i=0
			while [ $i -lt 24 ]
			do
				lnv $fic $(printf "xxt%06d00" $i)
				i=$((i+1))
			done

			lnv $fic xxt00010000
		else
			lnv $fic $(printf "xxt%06d00" $ech)
		fi
	done
fi

echo -e "\nLaunch MPI job"
if [ ! -f mpiOK ]
then
	touch fort.4
	mpiexe $bin > mpi.out 2> mpi.err
	find -type f -newer fort.4 | grep -vE $lstRE > mpiOK
	cat mpiOK | xargs ls -l
fi

if [ "$fcnam" ] && [ ! -f mpifcOK ]
then
	echo -e "\nLaunching other jobs"
	rm -f mpifc.out mpifc.err
	for fnam in $fcnam*
	do
		echo -e "\n. job with namelist $fnam"
		cpnam $fnam fort.4

		mpiexe $bin >> mpifc.out 2>> mpifc.err
		find -type f -newer fort.4 | grep -vE $lstRE >> mpifcOK
	done

	cat mpifcOK | xargs ls -l

	cpnam $nam fort.4
fi

if [ "$diffnam" ]
then
	echo -e "\nLaunch MPI job with restart"
	if [ ! -f mpidiffOK ]
	then
		mkdir -p start
		mv NODE.001_01 ICMSHARPE+* start
		touch fort.4
		mpiexe $bin > mpidiff.out 2> mpidiff.err
		find -type f -newer fort.4 | grep -vE $lstRE > mpidiffOK
		cat mpidiffOK | xargs ls -l
	fi

	echo -e "\nCompare last forecast step:"
	fcst=$(ls -1 ICMSHARPE+* | sort | tail -1)
	DR_HOOK=0 DR_HOOK_NOT_MPI=1 $LFITOOLS lfidiff --lfi-file-1 start/$fcst \
		--lfi-file-2 $fcst
elif echo $nam | grep -qE '/GM_FCTI_HYD_SL2_VFE_ARPPHYISBA_SLT_REST\.nam'
then
	echo -e "\nLaunch MPI job with restart (special ARPEGE/ISBA conf)"
	if [ ! -f mpidiffOK ]
	then
		touch fort.4
		mpiexe $bin > mpidiff.out 2> mpidiff.err
		find -type f -newer fort.4 | grep -vE $lstRE > mpidiffOK
		cat mpidiffOK | xargs ls -l
	fi
fi

if [ "$ios" ]
then
	echo -e "\nPost-processing files (IO server)"
	if [ ! -f ioOK ]
	then
		touch ioOK.tmp
		io_poll --prefix ICMSH
		[ "$fpnam" ] && io_poll --prefix PF
		find -type f -newer ioOK.tmp > ioOK.tmp
		mv ioOK.tmp ioOK
		cat ioOK | xargs ls -l
	fi
fi

echo -e "\nRename files"
for fic in $(find -maxdepth 1 -name \*ARPE\* | \
	grep -E '(ICMSH|PF|DHF(DL|ZO))ARPE.*+[0-9]{4}')
do
	ech=$(echo $fic | sed -re 's:.+\+0{,3}([0-9]{1,})(\.sfx)?:\1:')
	prefix=$(echo $fic | sed -re 's:\./(.+)ARPE.+:\1:')
	case $prefix in
		ICMSH) ftype=HIST;;
		DHFDL) ftype=DDHFDL;;
		DHFZO) ftype=DDHFZO;;
		PF) ftype=$(echo $fic | sed -re 's:\./PFARPE(.+)\+[0-9]+.*:\1:');;
	esac

	if [ "$ios" ] && [ $prefix = "ICMSH" -o $prefix = "PF" ]
	then
		lfi_move -pack -force $fic $(printf "ARPE.%04d.$ftype\n" $ech)
	else
		lnv $fic $(printf "ARPE.%04d.$ftype\n" $ech)
	fi
done

echo -e "\nRemove large init files"
[ -s EBAUCHE ] && rm ICMSHARPEINIT
rm -f ICMSHARPEIMIN

rm -f stdout.* stderr.* core.*

echo -e "\nLog and profiling files:"
ls -l _name.log NODE.001_01 env.txt mpi*.out mpi*.err
ls -l | grep -E '(meminfo\.txt|ifs\.stat|linux_bind\.txt)'

touch jobOK
