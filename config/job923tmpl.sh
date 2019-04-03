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

echo "Linking clims for Surfex (if required)" # TAG CLIM

rm -f Const.Clim # error otherwise
lnv $c923/RELIEF_G/GTOPT030/* .

if [ "$quadnam" ]
then
	echo "Launch MPI 'quad' job"
	sed -re 's:^ *N923=[0-9]:N923=1:' $quadnam > fort.4
	mpiexe $bin > mpiquad.log 2> mpiquad.err
	mv Const.Clim Neworog # ???
else
	cp PGD*.fa Neworog
fi

echo "Launch MPI 'lin' job 1"
sed -re 's:^ *N923=[0-9]:N923=1:' $nam > fort.4
mpiexe $bin > mpi1.log 2> mpi1.err
rm Neworog # ???

echo "Launch MPI 'lin' job 2"
lnv $c923/SURFACE_G/version2/i3e/* .
sed -re 's:^ *N923=[0-9]:N923=2:' $nam > fort.4
mpiexe $bin > mpi2.log 2> mpi2.err

echo "Launch MPI 'lin' job 3"
lnv $c923/N108/i3e/* .
for mm in 01 02 03 04 05 06 07 08 09 10 11 12
do
	cp Const.Clim Const.Clim.$mm
done

sed -re 's:^ *N923=[0-9]:N923=3:' $nam > fort.4
mpiexe $bin > mpi3.log 2> mpi3.err

lnv $c923/SURFACE_G/version2/i3e/* .
lnv $c923/SURFACE_L/EUROPEb_v1/i3e/* .
lnv $c923/CLIM_G/version2/i3e/rel_GL .

rm -f mpi[45689].*

for mm in 01 02 03 04 05 06 07 08 09 10 11 12
do
	echo "Clim - month $mm"
	cp Const.Clim.$mm Const.Clim

	echo "Launch MPI 'lin' job 4"
	lnv veg${mm}_GL veg_GL
	lnv lai${mm}_GL lai_GL
	sed -re 's:^ *N923=[0-9]:N923=4:' $nam > fort.4
	mpiexe $bin >> mpi4.log 2>> mpi4.err

	echo "Launch MPI 'lin' job 5"
	lnv veg_${mm}_HR veg_HR
	lnv lai_${mm}_HR lai_HR
	sed -re 's:^ *N923=[0-9]:N923=5:' $nam > fort.4
	mpiexe $bin >> mpi5.log 2>> mpi5.err

	echo "Launch MPI 'lin' job 6"
	for fic in $c923/CLIM_G/version2/i3e/*_${mm}_GL
	do
		lnv $fic $(basename ${fic/_${mm}_GL/_GL})
	done

	sed -re 's:^ *N923=[0-9]:N923=6:' $nam > fort.4
	xpnam --dfile $gridnam -i fort.4
	mpiexe $bin >> mpi6.log 2>> mpi6.err

	echo "Launch MPI 'lin' job 8"
	lnv $c923/CLIM_G/ozone/ascii/abc_quadra_$mm abc_coef
	sed -re 's:^ *N923=[0-9]:N923=8:' $nam > fort.4
	mpiexe $bin >> mpi8.log 2>> mpi8.err

	echo "Launch MPI 'lin' job 9"
	lnv $c923/CLIM_G/aerosols/ascii/aero.tegen.m${mm}_GL aero_GL
	sed -re 's:^ *N923=[0-9]:N923=9:' $nam > fort.4
	mpiexe $bin >> mpi9.log 2>> mpi9.err

	mv Const.Clim Const.Clim.$mm
done

echo "Log files list:"
ls -l ifs.stat NODE.*

touch jobOK
