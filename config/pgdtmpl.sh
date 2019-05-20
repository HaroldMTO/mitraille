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

# mandatory PGD specific environment
export DR_HOOK_NOT_MPI=1

env > env.txt

lstRE="\.(log|out|err)|(ifs|meminfo|linux_bind|NODE|core|std(out|err))\."
alias mpiexe='mpiauto --wrap -np _ntaskt -nnp _ntpn --'
alias mpiexe1='mpiauto --wrap -nn 1 -np 1 -nnp 1 --'
alias lnv='ln -sfv'

set -e
rm -f core.*

echo "Setting job profile" #TAG PROFILE

if [ -z "$nam" -o -z "$bin" -o -z "$ecoclimap" ]
then
	echo "Error: mandatory variables not set
nam: '$nam'
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

if [ -s IFSenv.txt ]
then
	echo "Noticeable missing environment variables:"
	vars=$(grep -f IFSenv.txt env.txt | sed -re 's:=.*::' | xargs | tr ' ' '|')
	grep -vE "^($vars)$" IFSenv.txt || echo "--> none"
fi

echo "Stack limit: $(ulimit -s)"

echo "Linking Ecoclimap files"
lnv $ecoclimap/* .

echo "Linking constants for Surfex" # TAG CONST

echo "Getting namelist $nam"
cp $nam OPTIONS.nam

echo "Launch MPI job"
if [ ! -f mpiOK ]
then
	mpiexe $bin > mpi.out 2> mpi.err
	find -type f -newer OPTIONS.nam | grep -vE $lstRE > mpiOK
	cat mpiOK | xargs ls -l
fi

if [ -n "$pgd" -a -n "$pgdfa" ]
then
	echo "Making FA PGD:"
	ls $pgd $pgdfa
	$LFITOOLS faempty $pgdfa test.fa
	$sfxtools sfxlfi2fa --sfx-fa--file test.fa --sfx-lfi-file $pgd

	if [ ! -f mpisfxOK ]
	then
		mpiexe1 $sfxtools > mpisfx.out 2> mpisfx.err
		find -type f -newer test.fa | grep -vE $lstRE > mpisfxOK
		cat mpisfxOK | xargs ls -l
	fi

	$LFITOOLS testfa < $lfi2fa
fi

rm -f stdout.* stderr.*

echo "Log files list:"
ls -l LISTING_PGD.txt

touch jobOK
