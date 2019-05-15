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

if [ "$SLURM_JOB_NAME" ]
then
	printf "SLURM job card:
	Number of nodes: $SLURM_JOB_NUM_NODES
	Number of tasks: $SLURM_NTASKS
	Tasks per node: $((SLURM_NTASKS/SLURM_JOB_NUM_NODES))
	Number of threads per task: $SLURM_CPUS_PER_TASK
"
fi

# mandatory
ulimit -s unlimited
export DR_HOOK=0
export DR_HOOK_IGNORE_SIGNALS=-1
export DR_HOOK_SILENT=1
export KMP_STACKSIZE=2G

# additional
export EC_MPI_ATEXIT=0
export EC_PROFILE_HEAP=0
env > env.txt

lstRE="\.(log|out|err)|(ifs|meminfo|linux_bind|NODE|core|std(out|err))\."
alias mpiexe='mpiauto --wrap -np _ntaskt -nnp _ntpn --'
alias lnv='ln -sfv'

set -e
rm -f core.*

echo "Setting job profile" #TAG PROFILE

if [ -z "$nam" -o -z "$c923" -o -z "$gridnam" -o -z "$bin" ]
then
	echo "Error: mandatory variables not set
nam: '$nam'
c923: '$c923'
gridnam: '$gridnam'
bin: '$bin'
" >&2
	exit 1
fi

if [ -n "$varenv" ] && [ -s $varenv ]
then
	echo "Possibly influencing environment variables:"
	grep -f $varenv env.txt || echo "--> none"
fi

echo "Linking relief files"
lnv $c923/RELIEF_G/GTOPT030/* .

echo "Linking clims for Surfex (if required)" # TAG CLIM

if [ "$pgd" ]
then
	echo "Get PGD orography (local file $pgd)"
	cp $pgd Neworog
elif [ "$pgdfa" ]
then
	echo "Get PGD orography (distant file $pgdfa)"
	cp $pgdfa Neworog
fi

rm -f Const.Clim # error otherwise

if [ "$quadnam" ]
then
	echo "Launch MPI 'quad' job"
	sed -re 's:^ *N923=[0-9]:N923=1:' $quadnam > fort.4
	if [ ! -f mpiquadOK ]
	then
		mpiexe $bin > mpiquad.out 2> mpiquad.err
		find -type f -newer fort.4 | grep -vE $lstRE > mpiquadOK
		cat mpiquadOK | xargs ls -l
		mv Const.Clim Neworog # ???
	fi
fi

echo "Launch MPI 'lin' job 1"
sed -re 's:^ *N923=[0-9]:N923=1:' $nam > fort.4
mpiexe $bin > mpi1.out 2> mpi1.err
find -type f -newer fort.4 | grep -vE $lstRE | xargs ls -l
rm -f Neworog # ???

echo "Launch MPI 'lin' job 2"
lnv $c923/SURFACE_G/version2/i3e/* .
sed -re 's:^ *N923=[0-9]:N923=2:' $nam > fort.4
mpiexe $bin > mpi2.out 2> mpi2.err
find -type f -newer fort.4 | grep -vE $lstRE | xargs ls -l

echo "Launch MPI 'lin' job 3"
lnv $c923/N108/i3e/* .
for mm in 01 02 03 04 05 06 07 08 09 10 11 12
do
	cp Const.Clim Const.Clim.$mm
done

sed -re 's:^ *N923=[0-9]:N923=3:' $nam > fort.4
mpiexe $bin > mpi3.out 2> mpi3.err

lnv $c923/SURFACE_G/version2/i3e/* .
lnv $c923/SURFACE_L/EUROPEb_v1/i3e/* .
lnv $c923/CLIM_G/version2/i3e/rel_GL .

rm -f mpi[45689].*

for mm in 01 02 06 12
do
	echo "Clim - month $mm"
	cp Const.Clim.$mm Const.Clim

	echo "Launch MPI 'lin' job 4"
	lnv veg${mm}_GL veg_GL
	lnv lai${mm}_GL lai_GL
	sed -re 's:^ *N923=[0-9]:N923=4:' $nam > fort.4
	mpiexe $bin >> mpi4.out 2>> mpi4.err
	find -type f -newer fort.4 | grep -vE $lstRE | xargs ls -l

	echo "Launch MPI 'lin' job 5"
	lnv veg_${mm}_HR veg_HR
	lnv lai_${mm}_HR lai_HR
	sed -re 's:^ *N923=[0-9]:N923=5:' $nam > fort.4
	mpiexe $bin >> mpi5.out 2>> mpi5.err
	find -type f -newer fort.4 | grep -vE $lstRE | xargs ls -l

	echo "Launch MPI 'lin' job 6"
	for fic in $c923/CLIM_G/version2/i3e/*_${mm}_GL
	do
		lnv $fic $(basename ${fic/_${mm}_GL/_GL})
	done

	sed -re 's:^ *N923=[0-9]:N923=6:' $nam > fort.4
	xpnam --dfile $gridnam -i fort.4
	mpiexe $bin >> mpi6.out 2>> mpi6.err
	find -type f -newer fort.4 | grep -vE $lstRE | xargs ls -l

	echo "Launch MPI 'lin' job 8"
	lnv $c923/CLIM_G/ozone/ascii/abc_quadra_$mm abc_coef
	sed -re 's:^ *N923=[0-9]:N923=8:' $nam > fort.4
	mpiexe $bin >> mpi8.out 2>> mpi8.err
	find -type f -newer fort.4 | grep -vE $lstRE | xargs ls -l

	echo "Launch MPI 'lin' job 9"
	lnv $c923/CLIM_G/aerosols/ascii/aero.tegen.m${mm}_GL aero_GL
	sed -re 's:^ *N923=[0-9]:N923=9:' $nam > fort.4
	mpiexe $bin >> mpi9.out 2>> mpi9.err
	find -type f -newer fort.4 | grep -vE $lstRE | xargs ls -l

	mv Const.Clim Const.Clim.$mm
done

echo "Remove large files"
rm -f Neworog

rm -f stdout.* stderr.*

echo "Log files list:"
ls -l ifs.stat NODE.*

touch jobOK
