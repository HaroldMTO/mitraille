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
grep -l FILE_PATH_EXPS old/$cy/protojobs/*.sh | sed -re 's:.+/(.+)\.sh:\1:' | \
	sort -u > info/xptable

echo "Répertoires jobs et namelist"
mkdir -p old/$cy/jobs
rm -f old/$cy/jobs/*

echo "Date fixe dans les scritps"
for fic in old/$cy/protojobs/[A-Z]*.sh
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
		basename ${ficj/_TSTDFI_/_DFIBIAS_} .sh
		basename ${ficj/_TSTDFI_/_DFIINCR_} .sh
	else
		basename $ficj .sh
	fi
done | grep -v _PGDC_ | sort -u > info/validconfs.txt

grep -f info/validconfs.txt config/profil_table | cut -f1 | sort -u \
	> info/mitconfs.txt
comm -23 info/validconfs.txt info/mitconfs.txt | grep -E '.+' &&
	echo "Attention : anciennes/nouvelles conf absentes de mitraillette" >&2

mkdir -p $cy/namelist $cy/quadnam $cy/selnam $cy/diffnam $cy/fpnam $cy/fcnam \
	$cy/deltanam

echo "Valeurs fixes en namelist, delta namelist"
rm -f $cy/namelist/* $cy/fcnam/* $cy/deltanam/*

while read conf bin mem wall cpu ntaskio ntaskt nnodes nthread
do
	echo $conf | grep -q '#conf' && continue

	nml=old/$cy/namelist/$conf.nam
	[ ! -s $nml ] && nml=old/$cy/namelist/${conf/_DFIBIAS_/_TSTDFI_}.nam
	[ ! -s $nml ] && nml=old/$cy/namelist/${conf/_DFIINCR_/_TSTDFI_}.nam
	[ ! -s $nml ] && nml=old/$cy/namelist/${conf}_lin.nam
	[ ! -s $nml ] && nml=old/$cy/namelist/${conf}_fp.nam
	[ ! -s $nml ] && nml=old/$cy/namelist/${conf}.selnam_dila
	[ ! -s $nml ] && nml=old/$cy/namelist/${conf}.selnam_pgd

	if [ ! -s $nml ]
	then
		[ -s old/$cy/jobs/$conf.sh ] && echo "--> pas de namelist $conf"
		continue
	fi

	ntask=$((ntaskt-ntaskio))

	cat > val.tmp <<-EOF
		s/__NCOMBFLEN__/1800000/
		s/__MP_TYPE__/2/
		s/__LOPT_SCALAR__/.TRUE./
		s/__MBX_SIZE__|substr6/1024000000/
		s/__NTASK_IO__/$ntaskio/
		s/__NTASKS__|substrC/$ntask/
	EOF

	if echo $conf | grep -qE '_DFIBIAS_'
	then
		sed -rf val.tmp -e "s/_lbias_/.TRUE./" -e "s/_lincr_/.FALSE./" $nml > \
			$cy/namelist/$conf.nam
	elif echo $conf | grep -qE '_DFIINCR_'
	then
		sed -rf val.tmp -e "s/_lbias_/.FALSE./" -e "s/_lincr_/.TRUE./" $nml > \
			$cy/namelist/$conf.nam
	elif [ $conf = "L3_FPIN_HYD_MODEL_ARPPHYISBA" ]
	then
		sed -rf val.tmp -e "s/NPOSTS(1)=-4/NPOSTS(1)=-3/" $nml > \
			$cy/fcnam/$conf.nam1
		sed -rf val.tmp -e "s/LEQLIMSAT=.TRUE./LEQLIMSAT=.FALSE./" -e "s/h3/t0/" \
			-e "s/NPOSTS(1)=-4/NPOSTS(1)=-0/" $nml > $cy/fcnam/$conf.nam2
		sed -rf val.tmp $nml > $cy/namelist/$conf.nam
	elif echo $nml | grep -qE '_lin\.nam'
	then
		sed -rf val.tmp ${nml/_lin/_quad} > $cy/quadnam/$conf.nam
		sed -rf val.tmp $nml > $cy/namelist/$conf.nam
	elif echo $nml | grep -qE '_fp\.nam'
	then
		sed -rf val.tmp -e "s/val_sitr/300./" -e "s/val_sipr/100000./" \
			${nml/_fp/_fc} > $cy/fcnam/$conf.nam1
		sed -rf val.tmp -e "s/val_sitr/350./" -e "s/val_sipr/100000./" \
			${nml/_fp/_fc} > $cy/fcnam/$conf.nam2
		sed -rf val.tmp -e "s/val_sitr/300./" -e "s/val_sipr/80000./" \
			${nml/_fp/_fc} > $cy/fcnam/$conf.nam3
		sed -f val.tmp $nml > $cy/namelist/$conf.nam
	elif echo $nml | grep -qE 'selnam_(dila|pgd)'
	then
		cp $nml $cy/namelist/$conf.nam
	else
		sed -rf val.tmp $nml > $cy/namelist/$conf.nam
	fi

	# conversion deltanam : suppression namelists vides et espaces
	cat $cy/namelist/$conf.nam | tr -d '\t' | tr '\n' '\t' | sed -re 's:&\w+\s+/\s*::g' \
		-e 's:\t+:\n:g' > $cy/deltanam/$conf.nam
done < config/profil_table
rm val.tmp

echo "Déplacement/conversion selnam"
grep -E "/.+\.selnam" old/$cy/jobs/* | grep -vE "selnam_(fp|dila|pgd)|\.diff" |\
	sed -re 's:.+/(.+)\.sh.+/([^ ]+) +(.+):\1 \2 \3:' | \
	sed -re 's:\w+\.selnam_(exseg1|sfex)$:EXSEG1.nam:' > info/selnam
rm -f $cy/selnam/*
while read conf fic selnam
do
	# peut arriver en double "conf.conf.selnam..."
	ficsel=$(echo $conf.$selnam | sed -re 's:('$conf'\.){2}:'$conf'.:')
	cp old/$cy/namelist/$fic $cy/selnam/$ficsel
done < info/selnam

echo "Déplacement diffnam"
rm -f $cy/diffnam/*
for fic in $(find old/$cy/namelist -name \*.diff)
do
	# petite erreur namelist 'CONV_PGD' 1 conf L3 AROMALP1300
	cp $fic $cy/diffnam/$(basename ${fic/_CONV_PGD/_CONVPGD} .diff)
done

echo "Déplacement/conversion fpnam"
grep -E '^ *\$E?CP.+/.+\.selnam_fp' old/$cy/jobs/* | \
	sed -re 's:.+/(.+)\.sh\: *\$E?CP .+/([^ ]+) +(.+):\1 \2 \3:' | \
	sed -re 's:([^ ]+) \1\.:\1 arpege.:' | sort > $cy/fptable
echo "L3_FPOF_HYD_GPLALON_OPE2_ARPPHYISBA alaro.selnam_fp_0 sel_0" >> $cy/fptable
if [ ! -s alaro.selnam_fp_0 ]
then
	cp old/$cy/namelist/L3_FPOF_HYD_GPLALON_OPE2_ARPPHYISBA.nam \
		old/$cy/namelist/alaro.selnam_fp_0
fi
rm -f $cy/fpnam/*
while read conf ficout zzz
do
	fic=${ficout/arpege/$conf}
	if [ -s $cy/fpnam/$ficout ]
	then
		diff -q old/$cy/namelist/$fic $cy/fpnam/$ficout && continue

		echo "Erreur fpnam : $ficout différent pour $conf" >&2
		exit 1
	fi

	cp old/$cy/namelist/$fic $cy/fpnam/$ficout || echo "Erreur $conf $fic" >&2
done < $cy/fptable

echo "Table analyses"
grep -E '^ *\$E?CP +.+(EBAUCHE|ICM??.+INIT) *$' old/$cy/jobs/*.sh | \
	sed -re 's:.+/(.+)\.sh\: *\$E?CP .+/([^ ]+) +(.+):\1 \2 \3:' | \
	grep -vE "_DFIBIAS_.+_analyse|_DFIINCR_.+_guess" | sort > $cy/initable

echo "Table analyses surfex"
grep -E '^ *\$E?CP +.+INIT\.sfx *$' old/$cy/jobs/* | \
	sed -re 's:.+/(.+)\.sh\: *\$E?CP +(.+/)?([^ ]+) +.+INIT\.sfx:\1 \3:' | \
	sort > $cy/inisfxtable

echo "Table forcages"
grep -E '^ *(\$E?CP|ln -\w*) (.+/)?.+ +ELS[AC].+' old/$cy/jobs/*.sh | \
	sed -re 's:.+/(.+)\.sh\: *(\$E?CP|ln -\w*) (.+/)?(.+) +ELS.+:\1 \4:' | \
	sed -re 's:_COUPL0+[^ ]*::' | sort -u > $cy/coupltable

echo "Tables clim, clim fp, filtre, const, pgd et pgdfa"
grep -E '^ *\$E?CP +.+ +(Const\.Clim(\.sfx)?|PGDFILE_.+\.fa) *$' \
	old/$cy/jobs/*.sh | \
	sed -re 's:.+/(.+)\.sh\: *\$E?CP +(.+/)?([^ ]+) +(Const\.Clim(\.sfx)?|PGDFILE_.+\.fa):\1 \3 \4:' |\
	sort > $cy/climtable
grep -E '^ *\$E?CP +.+ +const\.clim(\.\w+)+ *$' old/$cy/jobs/*.sh | \
	sed -re 's:.+/(.+)\.sh\: *\$E?CP +.+/([^ ]+) +(const\.clim(\.\w+)+):\1 \2 \3:' |\
	sort > $cy/climfptable
grep -E '^ *\$E?CP +.+ +matrix\.fil\.' old/$cy/jobs/*.sh | \
	sed -re 's:.+/(.+)\.sh\: *\$E?CP +.+/([^ ]+) +(matrix\.fil\.\w+):\1 \2 \3:' |\
	sort > $cy/filtertable
grep -E '^ *\$E?CP +.+ +\w+\.(hdr|dir) *$' old/$cy/jobs/*.sh | \
	sed -re 's:.+/(.+)\.sh\: *\$E?CP +.+/([^ ]+) +(\w+\.(hdr|dir)):\1 \2 \3:' | \
	sort > $cy/constable
grep -E '^ *file_lfi=PGD\w+\.lfi *$' old/$cy/jobs/*PGDC*.sh | \
	sed -re 's:.+/(.+)\.sh\: *file_lfi=(PGD\w+\.lfi):\1 \2:' | \
	sed -re 's:_PGDC_:_PGDS_:' > $cy/pgdtable
grep -E '^ *\$E?CP +PGDFILE_.+\.fa +Neworog *$' old/$cy/jobs/*C923* | \
	sed -re 's:.+/(.+)\.sh\: *\$CP +(PGDFILE_.+\.fa) +Neworog:\1 \2:' \
	>> $cy/pgdtable
sort $cy/pgdtable > pgd.tmp
mv pgd.tmp $cy/pgdtable
grep -E '\$CP +.+__CLIM_MODEL_(.+) *$' old/$cy/jobs/*C923*.sh | \
	sed -re 's:.+/(.+)\.sh\:.+__CLIM_MODEL_(.+)_m.+:\1 \1 Const.Clim.01:' | \
	sed -re 's:_C923_:_PGDS_:' -e 's:_SFEX::' > $cy/pgdfatable
grep -E '\$CP +.+SURFEX_FILES/(.+) *$' old/$cy/jobs/*PGDI*.sh | \
	sed -re 's:.+/(.+)\.sh\: *\$CP +.+/SURFEX_FILES/(.+) *$:\1 \1 \2:' | \
	sed -re 's:_PGDI_:_C923_:' >> $cy/pgdfatable
sort $cy/pgdfatable > pgd.tmp
mv pgd.tmp $cy/pgdfatable

echo "Table IO Server"
grep -E '^ *\$\{?IOPOLL}?' old/$cy/jobs/*.sh | \
	sed -re 's:.+/(.+)\.sh\: *\$\{?IOPOLL}? *.*\-\-prefix +(\w+):\1 \2:' | \
	sort > $cy/ioservtable

echo "Diff tables"
for fic in $cy/*table
do
	diff -Bbq $fic config || true
done

exit
cd ~saez/mitraille/cy46t1
grep -lE '\<COMPLETED\>' ~saez/mitraille/cy46/*/O* | \
	sed -re 's:.+/O(.+)\.o.+:\1:' | sort -u > ~/tmp/validconfs.txt

for fic in mitraille_*/O*.o*
do
	conf=$(basename $fic | sed -re 's:O(.+)\..+:\1:')
	grep -A 1200 'debug =>cat$' $fic | tail -n +2 | awk '{if ($1=="debug") exit;
		print $0;
	}' > ~/mitraille/pat/cy46t1/$conf.nam
done
