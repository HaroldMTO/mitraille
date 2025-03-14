#!/bin/sh

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
	sed -re 's/__NTASK_IO__/_ntaskio/' -e 's/__NTASKS__/_ntasks/' $1 | \
		tr -d '\t' | tr '\n' '\t' | sed -re 's:,&\t\s*:,:g' -e 's:\t+:\n:g' > $3
	xpnam --dfile=$2 --inplace $3
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

PATH=$PATH:/opt/softs/mpiauto:~gco/public/bin:~petithommeh/util/io_serv_tools
env > env.txt

lstRE="\.(log|out|err)|(ifs|meminfo|linux_bind|NODE|core|std(out|err))\."
alias mpiexe='mpiauto --wrap -np _ntaskt -nnp _ntpn --'
alias lnv='ln -sfv'

set -e
rm -f core.*

echo -e "\nSetting job profile" #TAG PROFILE

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
	echo -e "\nPossibly influencing environment variables:"
	grep -f $varenv env.txt || echo "--> none"
fi

if [ -s IFSenv.txt ]
then
	echo -e "\nNoticeable missing environment variables:"
	vars=$(grep -f IFSenv.txt env.txt | sed -re 's:=.*::' | xargs | tr ' ' '|')
	grep -vE "^($vars)$" IFSenv.txt || echo "--> none"
fi

echo -e "\nStack limit: $(ulimit -s)"

echo -e "\nGetting main namelist $nam"
cpnam $nam vide.nml fort.4

echo -e "\nLaunch MPI job"
mpiexe $bin > mpi.out 2> mpi.err
find -type f -newer fort.4 | grep -vE $lstRE | xargs ls -l

echo -e "\nRename files"
lnv MATDILA MDI
lnv MATDILA MCO

rm -f stdout.* stderr.*

echo -e "\nLog and profiling files:"
ls -l _name.log env.txt mpi*.out mpi*.err
ls -l | grep -E '(meminfo\.txt|ifs\.stat|linux_bind\.txt)'

touch jobOK
