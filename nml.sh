#!/bin/sh

set -e
echo "Conversion mitraillette"

if [ $# -eq 0 ]
then
	echo "Erreur : pas de cycle" >&2
	exit 1
fi

cy=$1
mkdir -p $cy

echo "Jobs expés"
grep -l FILE_PATH_EXPS old/$cy/protojobs/* | sed -re 's:.+/(.+)\.sh:\1:' > \
	info/xptable
grep -vl FILE_PATH_EXPS old/$cy/protojobs/* | sed -re 's:.+/(.+)\.sh:\1:' | \
	grep -v _PGDC_ > info/validconfs.txt
sort -u info/validconfs.txt info/xptable > info/confs.txt

echo "Répertoires jobs et namelist"
mkdir -p old/$cy/jobs
mkdir -p $cy/namelist $cy/quadnam $cy/selnam $cy/diffnam $cy/fpnam $cy/dfinam \
	$cy/deltanam $cy/fcnam

echo "Date fixe dans les scritps"
for fic in old/$cy/protojobs/*.sh
do
	grep -q FILE_PATH_EXPS $fic && continue

	xp=$(grep -E '^ *CNMEXPL=(\w+)' $fic | sed -re 's:^ *CNMEXPL=(\w+).*:\1:')
	nom=$(grep -E '^ *CNMEXPS=' $fic | sed -re 's:^ *CNMEXPS=\W?(\w+).*:\1:')
	dom=$(grep -iE '^ *dom\w+=' $fic | sed -re 's:^ *dom\w+=\W?(\w+).*:\1:i')
	dd=$(grep -E '^ *idate=([0-9]+)' $fic | sed -re 's:^ *idate=([0-9]+).*:\1:')
	gl=$(grep -E '^ *indgl=([0-9]+)' $fic | sed -re 's:^ *indgl=([0-9]+).*:\1:')
	lon=$(grep -E '^ *indlon=([0-9]+)' $fic | sed -re 's:^ *indlon=([0-9]+).*:\1:')
	str=$(grep -E '^ *instret=([0-9]+)' $fic | sed -re 's:^ *instret=([0-9]+).*:\1:')
	lev=$(grep -E '^ *inflevg=([0-9]+)' $fic | sed -re 's:^ *inflevg=([0-9]+).*:\1:')
	levf=$(grep -E '^ *inflevgfin=([0-9]+)' $fic | sed -re 's:^ *inflevgfin=([0-9]+).*:\1:')
	max=$(grep -E '^ *insmaxa=([0-9]+)' $fic | sed -re 's:^ *insmaxa=([0-9]+).*:\1:')
	an=$(grep -E '^ *iaa=([0-9]+)' $fic | sed -re 's:^ *iaa=([0-9]+).*:\1:')
	mm=$(grep -E '^ *imm=([0-9]+)' $fic | sed -re 's:^ *imm=([0-9]+).*:\1:')
	jj=$(grep -E '^ *ijj=([0-9]+)' $fic | sed -re 's:^ *ijj=([0-9]+).*:\1:')

	ficj=${fic/proto/}

	sed -re "s:\\\$\{iaa}:$an:g" -e "s:\\\$\{?imm}?:$mm:g" \
		-e "s:\\\$\{ijj}:$jj:g" -e "s:\\\$\{?CNMEXPL}?:$xp:g" \
		-e "s:\\\$\{?idate}?:$dd:g" -e "s:\\\$\{?indgl}?:$gl:g" \
		-e "s:\\\$\{?indlon}?:$indlon:g" -e "s:\\\$\{?instret}?:$str:g" \
		-e "s:\\\$\{?inflevg}?:$lev:g" -e "s:\\\$\{?inflevgfin}?:$levf:g" \
		-e "s:\\\$\{?insmaxa}?:$max:g" -e "s:\\\$\{?dom\w+}?:$dom:ig" $fic \
		-e "s:\\\$\{?CNMEXPS}?:$nom:g" > $ficj

	if echo $ficj | grep -qE '.+/.+_TSTDFI_'
	then
		cp $ficj ${ficj/_TSTDFI_/_DFIBIAS_}
		mv $ficj ${ficj/_TSTDFI_/_DFIINCR_}
	fi
done

echo "Valeurs fixes en namelist, delta namelist"
rm -f info/dfitable
while read conf bin mem wall cpu ntaskio ntaskt nnodes nthread
do
	nml=old/$cy/namelist/$conf.nam
	[ ! -s $nml ] && nml=old/$cy/namelist/${conf/_DFIBIAS_/_TSTDFI_}.nam
	[ ! -s $nml ] && nml=old/$cy/namelist/${conf/_DFIINCR_/_TSTDFI_}.nam
	[ ! -s $nml ] && nml=old/$cy/namelist/${conf}_lin.nam
	[ ! -s $nml ] && nml=old/$cy/namelist/${conf}_fp.nam
	[ ! -s $nml ] && continue

	ntask=$((ntaskt-ntaskio))

	if echo $conf | grep -qE '_DFIBIAS_'
	then
		sed -e "s/__NCOMBFLEN__/1800000/" -e "s/__MP_TYPE__/2/" \
			-e "s/__LOPT_SCALAR__/.TRUE./" -e "s/__MBX_SIZE__/1024000000/" \
			-e "s/__NTASK_IO__/$ntaskio/" -e "s/__NTASKS__/$ntask/" \
			-e "s/_lbias_/.TRUE./" -e "s/_lincr_/.FALSE./" $nml > \
			$cy/namelist/$conf.nam
		echo $conf >> info/dfitable
	elif echo $conf | grep -qE '_DFIINCR_'
	then
		sed -e "s/__NCOMBFLEN__/1800000/" -e "s/__MP_TYPE__/2/" \
			-e "s/__LOPT_SCALAR__/.TRUE./" -e "s/__MBX_SIZE__/1024000000/" \
			-e "s/__NTASK_IO__/$ntaskio/" -e "s/__NTASKS__/$ntask/" \
			-e "s/_lbias_/.FALSE./" -e "s/_lincr_/.TRUE./" $nml > \
			$cy/namelist/$conf.nam
		echo $conf >> info/dfitable
	else
		sed -e "s/__NCOMBFLEN__/1800000/" -e "s/__MP_TYPE__/2/" \
			-e "s/__LOPT_SCALAR__/.TRUE./" -e "s/__MBX_SIZE__/1024000000/" \
			-e "s/__NTASK_IO__/$ntaskio/" -e "s/__NTASKS__/$ntask/" \
			$nml > $cy/namelist/$conf.nam
	fi

	# suppression namelists vides et espaces
	cat $nml | xargs | sed -re 's:&\w+\s+/\s*::g' -e 's:\s+:\n:g' \
		> $cy/deltanam/$conf.nam

	if echo $nml | grep -qE '_lin\.nam'
	then
		sed -e "s/__NCOMBFLEN__/1800000/" -e "s/__MP_TYPE__/2/" \
			-e "s/__LOPT_SCALAR__/.TRUE./" -e "s/__MBX_SIZE__/1024000000/" \
			-e "s/__NTASK_IO__/$ntaskio/" -e "s/__NTASKS__/$ntask/" \
			${nml/_lin/_quad} > $cy/quadnam/$conf.nam
	elif echo $nml | grep -qE '_fp\.nam'
	then
		sed -e "s/__NCOMBFLEN__/1800000/" -e "s/__MP_TYPE__/2/" \
			-e "s/__LOPT_SCALAR__/.TRUE./" -e "s/__MBX_SIZE__/1024000000/" \
			-e "s/__NTASK_IO__/$ntaskio/" -e "s/__NTASKS__/$ntask/" \
			${nml/_fp/_fc} > /tmp/fc.nam
		sed -e "s/val_sitr/300./" -e "s/val_sipr/100000./" /tmp/fc.nam \
			> $cy/fcnam/$conf.nam1
		sed -e "s/val_sitr/350./" -e "s/val_sipr/100000./" /tmp/fc.nam \
			> $cy/fcnam/$conf.nam2
		sed -e "s/val_sitr/300./" -e "s/val_sipr/80000./" /tmp/fc.nam \
			> $cy/fcnam/$conf.nam3
	elif [ $conf = "L3_FPIN_HYD_MODEL_ARPPHYISBA" ]
	then
		sed -e "s/__NCOMBFLEN__/1800000/" -e "s/__MP_TYPE__/2/" \
			-e "s/__LOPT_SCALAR__/.TRUE./" -e "s/__MBX_SIZE__/1024000000/" \
			-e "s/__NTASK_IO__/$ntaskio/" -e "s/__NTASKS__/$ntask/" \
			$nml > /tmp/in.nam
		sed -e "s/NPOSTS(1)=-4/NPOSTS(1)=-3/" /tmp/in.nam > $cy/fcnam/$conf.nam1
		sed -e "s/NPOSTS(1)=-4/NPOSTS(1)=-0/" -e "s/h3/t0/" \
			-e "s/LEQLIMSAT=.TRUE./LEQLIMSAT=.FALSE./" /tmp/in.nam \
			> $cy/fcnam/$conf.nam2
	fi
done < config/profil_table

echo "Déplacement/conversion selnam"
grep -E "/.+\.selnam" old/$cy/jobs/* | grep -vE "selnam_fp|\.diff" | \
	sed -re 's:.+/(.+)\.sh.+/([^ ]+) +(.+):\1 \2 \3:' > info/selnam

while read conf fic selnam
do
	# peut arriver en double "conf.conf.selnam..."
	ficsel=$(echo $conf.$selnam | sed -re 's:('$conf'\.){2}:'$conf'.:')
	cp old/$cy/namelist/$fic $cy/selnam/$ficsel
done < info/selnam

echo "Déplacement diffnam"
grep -E "/.+\.selnam" old/$cy/jobs/* | grep -E "\.diff" | \
	sed -re 's:.+/(.+)\.sh.+/([^ ]+) +(.+):\1 \3:' > $cy/difftable
for fic in old/$cy/namelist/*.diff
do
	# petite erreur namelist 'CONV_PGD' 1 conf L3 AROMALP1300
	cp $fic $cy/diffnam/$(basename ${fic/_CONV_PGD/_CONVPGD} .diff)
done

echo "Déplacement/conversion fpnam"
grep -E '^ *\$E?CP.+/.+\.selnam_fp' old/$cy/jobs/* | \
	sed -re 's:.+/(.+)\.sh\: *\$E?CP .+/([^ ]+) +(.+):\1 \2 \3:' | \
	sed -re 's:([^ ]+) \1\.:\1 arpege.:' > $cy/fptable
while read conf ficout zzz
do
	fic=${ficout/arpege/$conf}
	if [ -s $cy/fpnam/$ficout ]
	then
		diff -q old/$cy/namelist/$fic $cy/fpnam/$ficout && continue

		echo "Erreur fpnam : $ficout différent pour $conf" >&2
		exit 1
	fi

	cp old/$cy/namelist/$fic $cy/fpnam/$fout
done < $cy/fptable

echo "Table analyses"
grep -E '^ *\$E?CP.+/.+(EBAUCHE|ICM??.+INIT)$' old/$cy/jobs/* | \
	sed -re 's:.+/(.+)\.sh\: *\$E?CP .+/([^ ]+) +(.+):\1 \2 \3:' | \
	grep -vE "_DFIBIAS_.+_analyse|_DFIINCR_.+_guess" > $cy/initable

echo "Table analyse surfex"
grep -E '^ *\$E?CP.+/.+INIT\.sfx *$' old/$cy/jobs/* | \
	sed -re 's:.+/(.+)\.sh\: *\$E?CP .+/([^ ]+) +.+INIT\.sfx:\1 \2:' \
	> $cy/inisfxtable

echo "Table forcage"
grep -E '^ *\$E?CP.+/.+ +ELS[AC].+' old/$cy/jobs/* | \
	sed -re 's:.+/(.+)\.sh\: *\$E?CP .+/(.+) +ELS.+:\1 \2:' | \
	sed -re 's:_COUPL0+[^ ]*::' | uniq > $cy/coupltable

echo "Tables clim, clim fp, filtre"
grep -E '^ *\$E?CP.+/.+ +(Const\.Clim(\.sfx)?|PGDFILE_.+\.fa) *$' old/$cy/jobs/* | \
	sed -re 's:.+/(.+)\.sh\: *\$E?CP .+/([^ ]+) +(Const\.Clim(\.sfx)?|PGDFILE_.+\.fa):\1 \2 \3:' \
	> $cy/climtable
grep -E '^ *\$E?CP.+/.+ +const\.clim(\.\w+)+ *$' old/$cy/jobs/* | \
	sed -re 's:.+/(.+)\.sh\: *\$E?CP .+/([^ ]+) +(const\.clim(\.\w+)+):\1 \2 \3:' \
	> $cy/climfptable
grep -E '^ *\$E?CP.+/.+ +matrix\.fil\.' old/$cy/jobs/* | \
	sed -re 's:.+/(.+)\.sh\: *\$E?CP .+/([^ ]+) +(matrix\.fil\.\w+):\1 \2 \3:' \
	> $cy/filtertable
grep -E '^ *\$E?CP.+/.+ +\w+\.(hdr|dir) *$' old/$cy/jobs/* | \
	sed -re 's:.+/(.+)\.sh\: *\$E?CP .+/([^ ]+) +(\w+\.(hdr|dir)):\1 \2 \3:' \
	> $cy/constable
grep -E '^ *file_lfi=PGD\w+\.lfi *$' old/$cy/jobs/* | \
	sed -re 's:.+/(.+)\.sh\: *file_lfi=(PGD\w+\.lfi):\1 \2:' | \
	sed -re 's:_PGDC_:_PGDS_:' > $cy/pgdtable
grep -E '\$CP +.+__CLIM_MODEL_(.+) *$' old/$cy/jobs/* | \
	sed -re 's:.+/(.+)\.sh\:.+__CLIM_MODEL_(.+)_m.+:\1 \1 Const.Clim.01:' | \
	sed -re 's:_C923_:_PGDS_:' -e 's:_SFEX::' > $cy/pgdfatable

echo "Table IO Server"
grep -E '^ *\$\{?IOPOLL}?' old/$cy/jobs/* | \
	sed -re 's:.+/(.+)\.sh\: *\$\{?IOPOLL}? *.*\-\-prefix +(\w+):\1 \2:' \
	> $cy/ioservtable
