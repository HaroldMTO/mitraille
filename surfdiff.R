Gndigits = round(log10(.Machine$double.eps))
Gnum = "-?\\d*\\.\\d+([eE]?[-+]?\\d+)?\\>"

gpnorm2D = function(nd)
{
	ind = grep("^ *NUMFLDS=",nd)
	indo = grep("^ *GPNORM OUTPUT",nd)

	nfg = as.integer(sub(" *NUMFLDS= *(\\d+) .+","\\1",nd[ind]))
	ind = ind[nfg > 0]
	nfg = nfg[nfg > 0]
	# in CANARI, several prints of the setup of surface fields
	ind = ind[! duplicated(nd[ind-1])]
	surf = list()
	group = character()

	for (i in seq(along=ind)) {
		group[i] = sub("^.+ (\\w+) +- +.+","\\1",nd[ind[i]-1])
		gnames = sub("^ *\\w+( +\\d+)+ +(\\w+(\\.\\w+)?).+","\\2",nd[ind[i]+seq(nfg[i])])
		gnames = substr(gnames,1,16)

		ii = grep(sprintf("\\<%s\\>",group[i]),nd[indo-1])
		if (length(ii) == 0) {
			group[i] = sub("^ *(\\w+) +.+","\\1",nd[ind[i]+1])
			ii = grep(sprintf("\\<%s\\>",group[i]),nd[indo-1])
			if (length(ii) == 0) {
				#cat("--> no GP norms for group",group[i],i,"\n")
				next
			}
		}

		while (length(ii) > 0) {
			if (regexpr(", +FIELD +\\d+",nd[indo[ii[1]]-1]) > 0) {
				# nfg lines AVE, every 4 lines (group, GPNORM, AVE, 1)
				indi = indo[ii[1]]+(seq(nfg[i])-1)*4+1
				ii = ii[-seq(nfg[i])]
			} else if (regexpr(" \\d+ +FIELDS\\>",nd[indo[ii[1]]-1]) > 0) {
				# nfg lines AVE, every 3 lines (GPNORM, AVE, 1)
				indi = indo[ii[1]]+(seq(nfg[i])-1)*3+1
				ii = ii[-1]
			} else {
				# nfg lines after GPNORM and AVE
				indi = indo[ii[1]]+seq(nfg[i])+1
				ii = ii[-1]
			}

			gpre = regmatches(nd[indi],gregexpr(sprintf("(%s|NaN)",Gnum),nd[indi]))
			gpre = lapply(gpre,function(x) gsub("(\\d+)(\\-\\d+)","\\1E\\2",x))
			gpn = t(sapply(gpre,as.numeric))
			dimnames(gpn) = list(gnames,c("ave","min","max"))
			if (length(surf) < i) {
				surf[[i]] = gpn
			} else {
				n = length(surf[[i]])
				stopifnot(n %% length(gpn) == 0)
				surf[[i]] = array(c(surf[[i]],gpn),c(dim(gpn),n/length(gpn)+1))
				dimnames(surf[[i]])[1:2] = dimnames(gpn)
			}
		}
	}

	names(surf) = group[seq(along=surf)]
	surf[sapply(surf,length) > 0]
}

diffnorm = function(x,y)
{
	x0 = pmax(abs(x),abs(y))
	ndiff = pmax(Gndigits,1+log10(abs(y-x))-log10(x0))-Gndigits
	ndiff[is.nan(ndiff)] = 0
	ndiff
}

args = strsplit(commandArgs(trailingOnly=TRUE),split="=")
cargs = lapply(args,function(x) unlist(strsplit(x[-1],split=":")))
names(cargs) = sapply(args,function(x) x[1])

nd = readLines(cargs$fic1)
nd = grep("^ *$",nd,value=TRUE,invert=TRUE)
surf1 = gpnorm2D(nd)

nd = readLines(cargs$fic2)
nd = grep("^ *$",nd,value=TRUE,invert=TRUE)
surf2 = gpnorm2D(nd)

mnx = "mnx" %in% names(cargs) && as.logical(cargs$mnx)

noms1 = names(surf1)
noms2 = names(surf2)
indv = match(noms1,noms2)
if (any(is.na(indv))) cat("missing clim variables in 2nd file :",noms1[is.na(indv)],"\n")
iv = which(noms2 %in% noms1)
if (any(is.na(indv))) cat("new clim variables :",noms2[is.na(indv)],"\n")
if (length(iv) == 0) {
	cat("variables (1):",noms1,"\n")
	cat("variables (2):",noms2,"\n")
	stop("no clim variables in common to compare\n")
}

for (i in na.omit(indv)) {
	gp1 = surf1[[i]]
	gp2 = surf2[[indv[i]]]
	ndiff = array(round(diffnorm(gp1,gp2)),dim=dim(gp1))
	if (length(dim(gp1)) == 2) dim(ndiff) = c(dim(ndiff),1)

	noms = sprintf("%-16s",dimnames(gp1)[[1]])
	step = sprintf("Setup %d",seq(dim(ndiff)[3]))

	cat(sprintf("Group %-13s",names(surf1)[i]),paste(step,collapse="\t"),"\n")
	if (mnx) {
		for (j in seq(dim(ndiff)[1])) {
			sdiff = apply(ndiff[j,,],2,function(x) paste(sprintf("%g",x),collapse="/"))
			cat("\t",noms[j],sprintf("% 7d",sdiff),"\n")
		}
	} else {
		for (j in seq(dim(ndiff)[1])) cat("\t",noms[j],sprintf("% 7d",ndiff[j,1,]),"\n")
	}
}

if (FALSE) {
for (i in na.omit(indv)) {
	gp1 = surf1[[i]]
	gp2 = surf2[[indv[i]]]
	ndiff = array(round(diffnorm(gp1,gp2)),dim=dim(gp1))
	if (length(dim(gp1)) == 2) dim(ndiff) = c(dim(ndiff),1)

	noms = sprintf("%-16s",dimnames(gp1)[[1]])
	step = sprintf("Setup %d",seq(dim(ndiff)[3]))

	if (max(nchar(noms))*length(noms) > 65) noms = abbreviate(noms,5)
	if (max(nchar(noms)) > 12 || mnx) {
		fmt = "%12s"
	} else if (max(nchar(noms)) > 7 || mnx) {
		fmt = "%8s"
	} else if (max(nchar(noms)) > 5) {
		fmt = "%6s"
	} else {
		fmt = "%5s"
	}
	cat(" step",sprintf(fmt,noms),"\n")
	if (mnx) {
		for (j in seq(dim(ndiff)[3])) {
			sdiff = apply(ndiff[,,j],1,function(x) paste(sprintf("%g",x),collapse="/"))
			cat(step[j],sprintf(fmt,sdiff),"\n")
		}
	} else {
		for (j in seq(dim(ndiff)[3])) cat(step[j],sprintf(fmt,ndiff[,1,j]),"\n")
	}
}
}
