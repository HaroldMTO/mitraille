args = strsplit(commandArgs(trailingOnly=TRUE),split="=")
cargs = lapply(args,function(x) strsplit(x[-1],split=":")[[1]])
names(cargs) = sapply(args,function(x) x[1])

namold = strsplit(readLines(cargs$ficold),"/")
namnew = strsplit(readLines(cargs$ficnew),"/")

nomsold = sapply(namold,"[",2)
nomsnew = sapply(namnew,"[",2)
ind = match(nomsnew,nomsold)

for (i in seq(along=nomsnew)) {
	varsnew = strsplit(namnew[[i]][-(1:2)],",")[[1]]
	snam = sprintf("&%s",nomsnew[i])

	if (is.na(ind[i])) {
		sadd = sprintf("\t%s=++",varsnew)
		snam = sprintf("%s\n%s",snam,paste(sadd,collapse=",\n"))
	} else {
		varsold = strsplit(namold[[ind[i]]][-(1:2)],",")[[1]]

		if (any(! varsold %in% varsnew)) {
			ssup = sprintf("\t%s=--",varsold[! varsold %in% varsnew])
			snam = sprintf("%s,\n%s",snam,paste(ssup,collapse=",\n"))
		}

		if (any(! varsnew %in% varsold)) {
			sadd = sprintf("\t%s=++",varsnew[! varsnew %in% varsold])
			snam = sprintf("%s\n%s",snam,paste(sadd,collapse=",\n"))
		}
	}

	snam = sprintf("%s\n/\n",snam)
	cat(snam)
}
