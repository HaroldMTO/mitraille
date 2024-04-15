library(mfnode)

args = strsplit(commandArgs(trailingOnly=TRUE),split="=")
cargs = lapply(args,function(x) unlist(strsplit(x[-1],split=":")))
names(cargs) = sapply(args,function(x) x[1])

nd = readLines(cargs$fic1,skipNul=TRUE)
ts1 = getvar("TSTEP",nd)
has.fc = any(regexpr("^ *START CNT4",nd) > 0)
if (! has.fc) cat("--> no forecast conf (cnt4) in 1st file\n")

fp1 = fpgpnorm(nd,0)
#fp1 = fpnorm(nd,0)

if (is.null(fp1)) {
	cat("--> no FP norms in 1st file\n")
	q("no")
}

nfrpos = getvar("NFRPOS",nd)
step1 = sprintf("pp%d",seq(dim(fp1)[1]))
cat("nb of steps, file 1:",length(step1),"- norms frequency:",nfrpos,"\n")

nd = readLines(cargs$fic2,skipNul=TRUE)
ts2 = getvar("TSTEP",nd)

if (ts1 != ts2) stop("different TSTEP")

fp2 = fpgpnorm(nd,0)

if (is.null(fp2)) {
	cat("--> no FP norms in 2nd file\n")
	q("no")
}

nfrpos = getvar("NFRPOS",nd)
step2 = sprintf("pp%d",seq(dim(fp2)[1]))
cat("nb of steps, file 2:",length(step2),"- norms frequency:",nfrpos,"\n")

noms1 = dimnames(fp1)[[3]]
noms2 = dimnames(fp2)[[3]]

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

fp1 = fp1[na.omit(indt),1,na.omit(indv),drop=FALSE]
fp2 = fp2[it,1,iv,drop=FALSE]
#fp1 = sapply(fp1[na.omit(indv)],function(x) x[na.omit(indt),,drop=FALSE],simplify="array")
#fp2 = sapply(fp2[iv],function(x) x[it,,drop=FALSE],simplify="array")

step1 = step1[na.omit(indt)]
ndiff = array(round(digitsdiff(fp1,fp2)),dim=dim(fp1))

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
nt = dim(fp1)[1]
if (all(ndiff == 0)) {
	if (mnx) {
		for (i in seq(min(5,nt))) {
			sdiff = apply(ndiff,3,function(x) paste(sprintf("%g",x[i,,]),collapse="/"))
			cat(format(step1[i],width=5),sprintf(fmt,sdiff),"\n")
		}
	} else {
		for (i in seq(min(5,nt))) {
			cat(format(step1[i],width=5),sprintf(fmt,ndiff[i,1,]),"\n")
		}
	}

	if (nt > 5) cat("...",nt-min(5,nt),"more 0 lines\n")
} else {
	ind = seq(min(nt,15))

	if (mnx) {
		for (i in ind) {
			sdiff = apply(ndiff,4,function(x) paste(sprintf("%g",x[i,,]),collapse="/"))
			cat(format(step1[i],width=5),sprintf(fmt,sdiff),"\n")
		}
	} else {
		for (i in ind) cat(format(step1[i],width=5),sprintf(fmt,ndiff[i,1,]),"\n")
	}

	if (nt > 30) {
		cat("... (every",nt%/%30,"printed time-step)\n")
		ind = seq(15,nt,by=nt%/%30)[-1]
		for (i in ind) cat(format(step1[i],width=5),sprintf(fmt,ndiff[i,1,]),"\n")
	}
}
