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

export DR_HOOK_NOT_MPI=1
ulimit -s unlimited
env > env.txt

set -e

alias mpiexe='mpiauto --verbose --wrap -np _ntaskt -nnp _ntpn --'
alias mpiexe1='mpiauto --verbose --wrap -nn 1 -np 1 -nnp 1 --'
alias lnv='ln -sfv'

echo "Setting job profile" #TAG PROFILE

if [ -z "$selnam" -o -z "$bin" -o -z "$ecoclimap" ]
then
	echo "Error: mandatory variables not set
selnam: '$selnam'
bin: '$bin'
ecoclimap: '$ecoclimap'
" >&2
	exit 1
fi

echo "Linking constants for Surfex" # TAG CONST
lnv $ecoclimap/* .

echo "Getting namelist $selnam"
nam=$(echo $selnam | sed -re 's:.+\.([^.]+\.nam):\1:')
cp $selnam $nam

echo "Launch MPI job"
mpiexe $bin > mpi.log 2> mpi.err

if [ -n "$pgd" -o -n "$pgdfa" ]
then
	echo "Making FA PGD:"
	ls $pgd $pgdfa
	$LFITOOLS faempty ../$pgdfa test.fa
	$sfxtools sfxlfi2fa --sfx-fa--file test.fa --sfx-lfi-file $pgd

	mpiexe1 $sfxtools > mpisfx.log 2> mpisfx.err

	$LFITOOLS testfa < $lfi2fa
fi

echo "Log files list:"
ls -l LISTING_PGD.txt

touch jobOK
