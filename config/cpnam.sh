cpnam()
{
	sed -re 's/__NTASK_IO__/_ntaskio/' -e 's/__NTASKS__/_ntasks/' $1 | \
		tr -d '\t' | tr '\n' '\t' | sed -re 's:,&\t\s*:,:g' -e 's:\t+:\n:g' > $3
	xpnam --dfile=$2 --inplace $3
}
