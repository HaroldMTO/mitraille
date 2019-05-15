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

if [ -z "$nam" -o -z "$bin" ]
then
	echo "Error: mandatory variables not set
nam: '$nam'
bin: '$bin'
" >&2
	exit 1
fi

if [ -n "$varenv" ] && [ -s $varenv ]
then
	echo "Possibly influencing environment variables:"
	grep -f $varenv env.txt || echo "--> none"
fi

echo "Getting main namelist $nam"
cp $nam fort.4

echo "Launch MPI job"
mpiexe $bin > mpi.out 2> mpi.err
find -type f -newer fort.4 | grep -vE $lstRE | xargs ls -l

echo "Rename files"
lnv MATDILA MDI
lnv MATDILA MCO

rm -f stdout.* stderr.*

touch jobOK
