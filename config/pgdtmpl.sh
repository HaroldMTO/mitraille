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
export DR_HOOK_NOT_MPI=1
export DR_HOOK_IGNORE_SIGNALS=-1
export DR_HOOK_SILENT=1
export KMP_STACKSIZE=2G

# additional
export EC_MPI_ATEXIT=0
export EC_PROFILE_HEAP=0
unset DATA
env > env.txt

lstRE="\.(log|out|err)|(ifs|meminfo|linux_bind|NODE|core|std(out|err))\."
alias mpiexe='mpiauto --wrap -np _ntaskt -nnp _ntpn --'
alias mpiexe1='mpiauto --wrap -nn 1 -np 1 -nnp 1 --'
alias lnv='ln -sfv'

set -e
rm -f core.*

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

if [ -n "$varenv" ] && [ -s $varenv ]
then
	echo "Possibly influencing environment variables:"
	grep -f $varenv env.txt || echo "--> none"
fi

echo "Linking constants for Surfex" # TAG CONST
lnv $ecoclimap/* .

echo "Getting namelist $selnam"
nam=$(echo $selnam | sed -re 's:.+\.([^.]+\.nam):\1:')
cp $selnam $nam

echo "Launch MPI job"
mpiexe $bin > mpi.out 2> mpi.err
find -type f -newer $nam | grep -vE $lstRE | xargs ls -l

if [ -n "$pgd" -a -n "$pgdfa" ]
then
	echo "Making FA PGD:"
	ls $pgd $pgdfa
	$LFITOOLS faempty $pgdfa test.fa
	$sfxtools sfxlfi2fa --sfx-fa--file test.fa --sfx-lfi-file $pgd

	mpiexe1 $sfxtools > mpisfx.out 2> mpisfx.err
	find -type f -newer test.fa | grep -vE $lstRE | xargs ls -l

	$LFITOOLS testfa < $lfi2fa
fi

rm -f stdout.* stderr.*

echo "Log files list:"
ls -l LISTING_PGD.txt

touch jobOK
