library(mfnode)

args = strsplit(commandArgs(trailingOnly=TRUE),split="=")
cargs = lapply(args,function(x) unlist(strsplit(x[-1],split=":")))
names(cargs) = sapply(args,function(x) x[1])

nd = readLines(cargs$fic1,skipNul=TRUE)
ts1 = getvar("TSTEP",nd)
has.fc = any(regexpr("^ *START CNT4",nd) > 0)
if (! has.fc) cat("--> no forecast conf (cnt4) in 1st file\n")

if (is.null(cargs$re)) {
	nd = grep("^ *gpnorm gflt0",nd,invert=TRUE,ignore.case=TRUE,value=TRUE)
	gp1 = gpnorm(nd,lev=0,gpout=gpfre)
} else {
	if (regexpr("gpnorm gfl",cargs$re,ignore.case=TRUE) > 0) {
		gp1 = gpnorm(nd,lev=0,cargs$re,gpout=gpfre)
	} else {
		gp1 = gpnorm(nd,lev=0,cargs$re,gpfre)
	}
}

if (is.null(gp1)) {
	cat("--> no GP norms in 1st file\n")
	q("no")
}

nfrgdi = getvar(".+ NFRGDI",nd)
cat("nb of steps, file 1:",dim(gp1)[1],"- norms frequency:",nfrgdi,"\n")
step1 = dimnames(gp1)[[1]]

nd = readLines(cargs$fic2,skipNul=TRUE)
ts2 = getvar("TSTEP",nd)

if (ts1 != ts2) stop("different TSTEP")

if (is.null(cargs$re)) {
	nd = grep("^ *gpnorm gflt0",nd,invert=TRUE,ignore.case=TRUE,value=TRUE)
	gp2 = gpnorm(nd,lev=0,gpout=gpfre)
} else {
	if (regexpr("gpnorm gfl",cargs$re,ignore.case=TRUE) > 0) {
		gp2 = gpnorm(nd,lev=0,cargs$re,gpout=gpfre)
	} else {
		gp2 = gpnorm(nd,lev=0,cargs$re,gpfre)
	}
}

if (is.null(gp2)) {
	cat("--> no GP norms in 2nd file\n")
	q("no")
}

nfrgdi = getvar(".+ NFRGDI",nd)
cat("nb of steps, file 2:",dim(gp2)[1],"- norms frequency:",nfrgdi,"\n")
step2 = dimnames(gp2)[[1]]

noms1 = dimnames(gp1)[[4]]
noms2 = dimnames(gp2)[[4]]

indv = match(noms1,noms2)
if (any(is.na(indv))) cat("missing variables in 2nd file :",noms1[is.na(indv)],"\n")

indv = match(noms2,noms1)
iv = which(noms2 %in% noms1)
if (any(is.na(indv))) cat("new variables :",noms2[is.na(indv)],"\n")
if (length(iv) == 0) {
	cat("variables (1):",noms1,"\n")
	cat("variables (2):",noms2,"\n")
	stop("no variables in common to compare\n")
}

indt = match(step2,step1)
it = which(step2 %in% step1)
if (length(it) == 0) {
	cat("steps:",length(step1),length(step2),"\n")
	stop("no steps in common to compare\n")
}

if (length(step1) != length(step2)) {
	nt = min(length(step1),length(step2))
	cat("--> different number of steps in files, limiting norms to",nt,"1st ones\n")
}

it = which(! is.na(indt))
gp1 = gp1[na.omit(indt),,,na.omit(indv),drop=FALSE]
gp2 = gp2[it,,,iv,drop=FALSE]
step1 = step1[na.omit(indt)]
ndiff = array(round(digitsdiff(gp1,gp2)),dim=dim(gp1))

mnx = "mnx" %in% names(cargs) && as.logical(cargs$mnx)

noms = noms1[na.omit(indv)]
if (max(nchar(noms))*length(noms) > 65) noms = abbreviate(noms,5)
if (max(nchar(noms)) > 7 || mnx) {
	fmt = "%8s"
} else if (max(nchar(noms)) > 5) {
	fmt = "%6s"
} else {
	fmt = "%5s"
}

cat(" step",sprintf(fmt,noms),"\n")
nt = dim(gp1)[1]
if (all(ndiff == 0)) {
	ind = seq(min(nt,5))
} else {
	ind = seq(min(nt,15))
}

if (mnx) {
	sdiff = apply(ndiff,c(1,4),function(x) paste(sprintf("%g",x[1,]),collapse="/"))
	for (i in ind) cat(format(step1[i],width=5),sprintf(fmt,sdiff[i,]),"\n")
} else {
	for (i in ind) cat(format(step1[i],width=5),sprintf(fmt,ndiff[i,1,1,]),"\n")
}

if (all(ndiff == 0)) {
	if (nt > 5) cat("...",nt-length(ind),"more 0 lines\n")
} else {
	if (nt > 30) {
		cat("... (every",nt%/%30,"printed time-step)\n")
		ind = seq(length(ind),nt,by=nt%/%30)[-1]
		for (i in ind) cat(format(step1[i],width=5),sprintf(fmt,ndiff[i,1,1,]),"\n")
	}
}

if (any(regexpr("TL|AD",step1) > 0) && ! is.null(cargs$re) &&
	regexpr("gpnorm g(mv|fl)t0 traj",cargs$re) > 0) {
	gpnl = gp1[grep("TL|AD",step1,invert=TRUE),,,,drop=FALSE]
	gptl = gp1[regexpr("TL",step1) > 0,,,,drop=FALSE]
	gpad = gp1[rev(regexpr("AD",step1) > 0),,,,drop=FALSE]

	cat("+ NL/TL comparison:\n")
	ndiff = array(round(diffnorm(gpnl,gptl)),dim=dim(gpnl))
	cat(" step",sprintf(fmt,noms),"\n")
	nt = dim(gpnl)[1]
	if (all(ndiff == 0)) {
		for (i in seq(min(5,nt))) {
			cat(format(step1[i],width=5),sprintf(fmt,ndiff[i,1,1,]),"\n")
		}
	} else if (nt < 30) {
		for (i in seq(nt)) cat(format(step1[i],width=5),sprintf(fmt,ndiff[i,1,1,]),"\n")
	} else {
		for (i in seq(15)) cat(format(step1[i],width=5),sprintf(fmt,ndiff[i,1,1,]),"\n")
		cat("...\n")
		ind = seq(15,nt,by=nt%/%30+1)[-1]
		for (i in ind) cat(format(step1[i],width=5),sprintf(fmt,ndiff[i,1,1,]),"\n")
	}

	cat("+ NL/AD comparison:\n")
	ndiff = array(round(diffnorm(gpnl,gptl)),dim=dim(gpnl))
	cat(" step",sprintf(fmt,noms),"\n")
	nt = dim(gpnl)[1]
	if (all(ndiff == 0)) {
		for (i in seq(min(5,nt))) {
			cat(format(step1[i],width=5),sprintf(fmt,ndiff[i,1,1,]),"\n")
		}
	} else if (nt < 30) {
		for (i in seq(nt)) cat(format(step1[i],width=5),sprintf(fmt,ndiff[i,1,1,]),"\n")
	} else {
		for (i in seq(15)) cat(format(step1[i],width=5),sprintf(fmt,ndiff[i,1,1,]),"\n")
		cat("...\n")
		ind = seq(15,nt,by=nt%/%30+1)[-1]
		for (i in ind) cat(format(step1[i],width=5),sprintf(fmt,ndiff[i,1,1,]),"\n")
	}
}

