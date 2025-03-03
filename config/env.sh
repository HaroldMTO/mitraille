# mandatory variables for main binaries (silent settings)
ulimit -s unlimited
export DR_HOOK=1
export DR_HOOK_IGNORE_SIGNALS=-1
export DR_HOOK_SILENT=1
export KMP_STACKSIZE=4G

# additionnal variables for main binaries (information settings)
export EC_PROFILE_HEAP=0
export EC_MPI_ATEXIT=0
export EC_MEMINFO=0
