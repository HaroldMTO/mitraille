MAKEFLAGS += --no-print-directory

# ne pas mettre ~ pour P : il faut un chemin absolu
P = $(HOME)/proc/mitraille
B = ~/bin

.PHONY: build install mitra

build:
	# rien

install:
	! git status --porcelain 2>/dev/null | grep -qvE "^\?\? "
	make mitra
	make $B/mitraillette.sh
	make $B/mitratime.sh
	make $B/normdiff.sh
	make $B/statdiff.sh
	cp -uv modifnam.sh $B
	if git status >/dev/null 2>&1; then \
		grep -q $(shell git log -1 --pretty=format:%h 2>/dev/null) $P/version || \
			git log -1 --oneline >> $P/version; \
	fi

mitra:
	mkdir -p $P
	sed -re "s:mitra *=.+:mitra = \"$P\":" profils.R > $P/profils.R
	cp -pruv spdiff.R gpdiff.R surfdiff.R fpdiff.R statf.R const config
	cp -pru cy[4-5][0-9]* CY[4-5][0-9]* $P

$B/mitraillette.sh: mitraillette.sh
	sed -re "s:mitra=.+:mitra=$P:" mitraillette.sh > $B/mitraillette.sh
	chmod a+x $B/mitraillette.sh

$B/mitratime.sh: mitratime.sh
	sed -re "s:mitra=.+:mitra=$P:" mitratime.sh > $B/mitratime.sh
	chmod a+x $B/mitratime.sh

$B/normdiff.sh: normdiff.sh
	sed -re "s:mitra=.+:mitra=$P:" normdiff.sh > $B/normdiff.sh
	chmod a+x $B/normdiff.sh

$B/statdiff.sh: statdiff.sh
	sed -re "s:mitra=.+:mitra=$P:" statdiff.sh > $B/statdiff.sh
	chmod a+x $B/statdiff.sh
