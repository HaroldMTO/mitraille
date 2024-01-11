Gndigits = round(log10(.Machine$double.eps))
Gnum = "-?\\d*\\.\\d+([eE]?[-+]?\\d+)?\\>"
Gint = "-?\\d+\\>"

getvar = function(var,nd,sep="=")
{
	re = sprintf("^ *\\<%s *%s *(%s|%s).*",var,sep,Gint,Gnum)
	unique(as.numeric(gsub(re,"\\1",grep(re,nd,value=TRUE))))
}

line2num = function(nd)
{
	lre = regmatches(nd,gregexpr(sprintf("(%s|\\<NaN\\>)",Gnum),nd))
	lre = lapply(lre,function(x) gsub("(\\d+)([-+]\\d+)","\\1E\\2",x))
	sapply(lre,as.numeric)
}

gpnorm = function(nd,lev,ind,noms)
{
	if (missing(ind)) {
		ind = grep("GPNORM +\\w+.* +AVERAGE",nd)
		indo = grep("GPNORM OUTPUT",nd[ind],invert=TRUE)
		ind = ind[indo]
	}

	if (length(ind) == 0) stop("no GP norms")

	if (missing(noms)) {
		noms = unique(sub(" *GPNORM +(\\w+.+?) +AVERAGE.+","\\1",nd[ind]))
	} else {
		i = grep(sprintf(" *GPNORM +(%s)\\>",paste(noms,collapse="|")),nd[ind])
		ind = ind[i]
	}

	indi = rep(ind,each=length(lev))+lev+1

	gpn = line2num(nd[indi])

	noms[noms == "SURFACE PRESSURE"] = "SURF P"
	noms[noms == "U VELOCITY"] = "U VELOC."
	noms[noms == "V VELOCITY"] = "V VELOC."
	noms = sub("TEMPERATURE","TEMP",noms)

	nt = length(gpn)/(3*length(lev)*length(noms))
	if (nt != as.integer(nt)) {
		cat("noms:",noms,"\n")
		cat("lev:",lev,"\n")
		cat("gpn:",dim(gpn),"\n")
		stop("gpn, noms, lev inconsistent")
	}

	dim(gpn) = c(3,length(lev),length(noms),nt)
	gpl = aperm(gpn,c(4,2,1,3))

	dimnames(gpl) = list(NULL,lev,c("ave","min","max"),noms)

	gpl
}

gpnorms = function(fic,fp=FALSE)
{
	flines = readLines(fic)

	ind = grep("^ *GPNORM +\\w+",flines)
	lgp = lapply(strsplit(sub(" +AVE +","",flines[ind+1])," +"),as.numeric)
	noms = sub(" *GPNORM +(\\w+) +.+","\\1",flines[ind])
	i = which(noms == "OUTPUT")
	noms[i] = paste("OUTPUT$",seq(length(i)),sep="")
	names(lgp) = noms

	if (fp) {
		lfp = fpgpnorms(flines)
		lgp = c(lgp,lfp)
	}

	lgp
}

fpgpnorms = function(flines)
{
	lgp = list()

	ind = grep("^ *(FULL-POS +)?GPNORMS( +OF FIELDS)?",flines)
	indf = grep("^ *(\\w+|[. '/])+\\w+ *: [+-]?\\d*\\.\\d+",flines)
	for (i in ind) {
		i1 = match(TRUE,indf > i+1)
		ind2 = which(diff(indf[-(1:i1)]) > 1)
		if (length(ind2) == 0) {
			ii = indf[-(1:i1-1)]
		} else {
			ii = indf[i1:(i1+ind2[1])]
		}

		gp = lapply(strsplit(sub(".+: +","",flines[ii])," +"),as.numeric)
		names(gp) = sub("^ *((\\w+|[. '/])+\\w+) *:.+","\\1",flines[ii])
		lgp = c(lgp,gp)
	}

	if (length(lgp) > 0) {
		for (nom in names(lgp)) {
			i = which(names(lgp) == nom)
			if (length(i) == 1) next

			names(lgp)[i] = paste(nom,"$",seq(length(i)),sep="")
		}
	}

	lgp
}

countfield = function(ind,ind1,nl2)
{
	if (length(ind1) > 1) {
		which(diff(ind[seq(ind1[1],ind1[2])]) > nl2)[1]
	} else {
		length(ind)
	}
}

indexpand = function(ind,nf,nl)
{
	rep(ind,each=nf)+(seq(nf)-1)*nl2
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

#lgp1 = gpnorms(cargs$fic1,as.logical(cargs$fp))
#lgp2 = gpnorms(cargs$fic2,as.logical(cargs$fp))

gpfre1 = "[UVW] VELOCITY|(SURFACE )?PRESSURE|TEMPERATURE|GRAD[LM]_\\w+|GEOPOTENTIAL"
gpfre2 = "MOIST AIR SPECIF|ISOBARE CAPACITY|SURFACE DIV|d\\(DIV\\)\\*dP"
gpfre3 = "(ATND|ADIAB|CTY|(SI)?SL)_(\\w+)"
gpfre = paste(gpfre1,gpfre2,gpfre3,sep="|")
lev = 0

nd = readLines(cargs$fic1)
nd = grep("^ *$",nd,value=TRUE,invert=TRUE)
nflevg = getvar("NFLEVG",nd)
has.levels = getvar("NSPPR",nd) > 0
nl2 = 2+has.levels*nflevg
nstop = getvar("NSTOP",nd)
ts1 = getvar("TSTEP",nd)
icnt4 = grep("START CNT4",nd)
if (length(icnt4) == 0) cat("--> no forecast conf (cnt4) in 1st file\n")

ind = grep("GPNORM +\\w+.* +AVERAGE",nd)
if (length(icnt4) > 0) ind = ind[ind > icnt4[1]]

# check presence of norms for GFL t0
indo = grep(sprintf("GPNORM +(%s|OUTPUT) +AVERAGE",gpfre),nd[ind],invert=TRUE)
if (length(indo) == 0) {
	cat("--> no GP norms in 1st file\n")
	q("no")
}

ind1 = grep(cargs$gpre,nd[ind-1],ignore.case=TRUE)
if (length(ind1) == 0 && cargs$gpre == "gpnorm gflt0") {
	# looking for GFL norms printed in cnt4 after spectral norms
	ind1 = grep("NORMS AT (NSTEP|END) CNT4",nd[ind-2-nl2],ignore.case=TRUE)
	if (length(ind1) == 0) {
		ind1 = grep("NORMS AT (NSTEP|END) CNT4",nd[ind-3-nl2],ignore.case=TRUE)
	}
}

if (length(ind1) == 0) {
	cat("--> no print for pattern",cargs$gpre,
		"in file 1, searching for norms by names found:\n")
	# looking for the 1st group of norm print
	ind = ind[indo]
	i1 = grep("^ *gpnorm +\\w",nd)
	if (length(i1) > 0) i1 = i1[i1 > icnt4[1]]
	if (length(i1) > 0) {
		# account for stepx (calling gp_model)
		if (all(ind > i1[1])) {
			ii = which(nd[i1] == nd[i1[1]])
			ind = ind[ind < i1[ii[2]]]
		} else {
			ind = ind[ind < i1[1]]
		}
	}

	noms = unique(sub(" *GPNORM +(\\w+.+?) +AVERAGE.+","\\1",nd[ind]))
	cat("",noms,"\n")
	gp1 = gpnorm(nd,lev,ind,noms)
} else {
	if (length(ind1) == 0) stop(paste("no GP norms for pattern",cargs$gpre))
	nf = countfield(ind,ind1,nl2)
	indi = indexpand(ind[ind1],nf,nl2)
	gp1 = gpnorm(nd,lev,indi)
}

nfrgdi = getvar(".+ NFRGDI",nd)
istep1 = seq(0,nstop,by=nfrgdi)
nt1 = dim(gp1)[1]
ii = grep("NORMS AT (NSTEP|END) CNT4",nd)
st1 = gsub("^ *NORMS AT (NSTEP|END) CNT4(\\w*) *","\\2",nd[ii])
st1 = gsub("\\(((PRE)DICTOR|(COR)RECTOR)\\) *","\\2\\3",st1)
if (any(regexpr("(TL|AD)",st1) > 0)) st1 = gsub("^(\\d+)","NL\\1",st1)
cat("nb of steps, file 1:",nstop,"- norms frequency:",nfrgdi,"- nb of norms:",nt1,"\n")
if (length(istep1) > nt1) {
	# norms for corrector of PC scheme not managed (let a chance for 1st norms)
	if (nt1 > 1) stopifnot(all(regexpr("CORRECTOR",nd[ii]) < 0))
	length(istep1) = nt1
}
stopifnot(nt1 <= length(st1))

nd = readLines(cargs$fic2)
nd = grep("^ *$",nd,value=TRUE,invert=TRUE)
nstop = getvar("NSTOP",nd)
ts2 = getvar("TSTEP",nd)
icnt4 = grep("START CNT4",nd)
if (length(icnt4) == 0) cat("--> no forecast conf (cnt4) in 2nd file\n")

ind = grep("GPNORM +\\w+.* +AVERAGE",nd)
if (length(icnt4) > 0) ind = ind[ind > icnt4[1]]

if (ts1 != ts2) stop("different TSTEP")

indo = grep(sprintf("GPNORM +(%s|OUTPUT) +AVERAGE",gpfre),nd[ind],invert=TRUE)
if (length(indo) == 0) {
	cat("--> no GP norms in 2nd file\n")
	q("no")
}

if (cargs$gpre == "gpnorm gflt0") {
	# looking for GFL norms printed in cnt4 after spectral norms
	ind1 = grep("NORMS AT (NSTEP|END) CNT4",nd[ind-2-nl2],ignore.case=TRUE)
} else {
	ind1 = grep(cargs$gpre,nd[ind-1],ignore.case=TRUE)
}

if (length(ind1) == 0) {
	cat("--> no print for pattern",cargs$gpre,
		"in file 2, searching for norms by names found:\n")
	# looking for the 1st group of norm print
	ind = ind[indo]
	i1 = grep("^ *gpnorm +\\w",nd)
	if (length(i1) > 0) i1 = i1[i1 > icnt4[1]]
	if (length(i1) > 0) {
		# account for stepx (calling gp_model)
		if (all(ind > i1[1])) {
			ii = which(nd[i1] == nd[i1[1]])
			ind = ind[ind < i1[ii[2]]]
		} else {
			ind = ind[ind < i1[1]]
		}
	}

	noms = unique(sub(" *GPNORM +(\\w+.+?) +AVERAGE.+","\\1",nd[ind]))
	cat("",noms,"\n")
	gp2 = gpnorm(nd,lev,ind,noms)
} else {
	if (length(ind1) == 0) stop(paste("no GP norms for pattern",cargs$gpre))
	nf = countfield(ind,ind1,nl2)
	indi = indexpand(ind[ind1],nf,nl2)
	gp2 = gpnorm(nd,lev,indi)
}

nfrgdi = getvar(".+ NFRGDI",nd)
istep2 = seq(0,nstop,by=nfrgdi)
nt2 = dim(gp2)[1]
ii = grep("NORMS AT (NSTEP|END) CNT4",nd)
st2 = gsub("^ *NORMS AT (NSTEP|END) CNT4(\\w*) +","\\2",nd[ii])
if (any(regexpr("(TL|AD)",st2) > 0)) st2 = gsub("^(\\d+)","NL\\1",st2)
cat("nb of steps, file 2:",nstop,"- norms frequency:",nfrgdi,"- nb of norms:",nt2,"\n")
if (length(istep2) > nt2) {
	# norms for corrector of PC scheme not managed (let a chance for 1st norms)
	if (nt2 > 1) stopifnot(all(regexpr("CORRECTOR",nd[ii]) < 0))
	length(istep2) = nt2
}
stopifnot(nt2 <= length(st2))

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

indt = match(istep2,istep1)
it = which(istep2 %in% istep1)
if (length(it) == 0) {
	cat("steps:",length(istep1),length(istep2),"\n")
	stop("no steps in common to compare\n")
}

if (nt1 != nt2) {
	# TL and TL/AD tests are not managed (too much complicated)
	stopifnot(nt1 <= length(istep1))
	stopifnot(nt2 <= length(istep2))
	nt = min(nt1,nt2)
	cat("--> different number of steps in files, limiting norms to",nt,"1st ones\n")
}

if (nt1 > length(istep1)) {
	ntest = (nt1+1)%/%length(istep1)

	if (nt1%%length(istep1) == 0) {
		cat("--> several runs in file, seems like a TL/AD test\n")
		ntest = nt1%/%length(istep1)
		stopifnot(nt2%%length(istep2) == 0)
		stopifnot(ntest == nt2%/%length(istep2))
	} else if ((nt1+1)%%length(istep1) == 0) {
		# 1 step is missing up to steps: last AD one
		cat("--> several runs in file, seems like an AD test\n")
		ntest = (nt1+1)%/%length(istep1)
		stopifnot(any(nt2+1 == ntest*length(istep2)))
	} else if ((nt1-1)%%(length(istep1)-1) == 0) {
		# there is just one more than steps (without 0): NL0
		cat("steps:",istep1,"- dim(gp1):",nt1,"\n")
		ntest = (nt1-1)%/%(length(istep1)-1)
		stopifnot(nt2 == nt1)
	} else {
		cat("ntest:",ntest,"- steps:",nt1,"/",length(istep1),"\n")
		stop("several runs in file but unrecognized pattern")
	}

	indt = seq(along=st1)
	if (length(indt) > nt1) length(indt) = nt1
}

it = which(! is.na(indt))
gp1 = gp1[na.omit(indt),,,na.omit(indv),drop=FALSE]
gp2 = gp2[it,,,iv,drop=FALSE]
st1 = st1[na.omit(indt)]
#ndiff = sapply(1:dim(gp1)[4],function(i) diffnorm(gp1[,1,1,i],gp2[,1,1,i]))
#ndiff = matrix(round(ndiff),ncol=dim(gp1)[4])
ndiff = array(round(diffnorm(gp1,gp2)),dim=dim(gp1))

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
	if (mnx) {
		for (i in seq(min(5,nt))) {
			sdiff = apply(ndiff,4,function(x) paste(sprintf("%g",x[i,1,]),collapse="/"))
			cat(format(st1[i],width=5),sprintf(fmt,sdiff),"\n")
		}
	} else {
		for (i in seq(min(5,nt))) cat(format(st1[i],width=5),sprintf(fmt,ndiff[i,1,1,]),"\n")
	}

	if (nt > 5) cat("...",nt-min(5,nt),"more 0 lines\n")
} else {
	if (nt > 30) {
		ind = seq(1,nt,by=nt%/%30)
	} else {
		ind = seq(nt)
	}

	if (mnx) {
		for (i in ind) {
			sdiff = apply(ndiff,4,function(x) paste(sprintf("%g",x[i,1,]),collapse="/"))
			cat(format(st1[i],width=5),sprintf(fmt,sdiff),"\n")
		}
	} else {
		for (i in ind) cat(format(st1[i],width=5),sprintf(fmt,ndiff[i,1,1,]),"\n")
	}
}

if (nt1 > length(istep1) && regexpr("gpnorm g(mv|fl)t0 traj",cargs$gpre) > 0) {
	gpnl = gp1[regexpr("NL",st1) > 0,,,,drop=FALSE]
	gptl = gp1[regexpr("TL",st1) > 0,,,,drop=FALSE]
	gpad = gp1[rev(regexpr("AD",st1) > 0),,,,drop=FALSE]

	cat("+ NL/TL comparison:\n")
	ndiff = array(round(diffnorm(gpnl,gptl)),dim=dim(gpnl))
	cat(" step",sprintf(fmt,noms),"\n")
	nt = dim(gpnl)[1]
	if (all(ndiff == 0)) {
		for (i in seq(min(5,nt))) cat(format(st1[i],width=5),sprintf(fmt,ndiff[i,1,1,]),"\n")
	} else {
		if (nt > 30) {
			ind = seq(1,nt,by=nt%/%30)
		} else {
			ind = seq(nt)
		}

		for (i in ind) cat(format(st1[i],width=5),sprintf(fmt,ndiff[i,1,1,]),"\n")
	}

	cat("+ NL/AD comparison:\n")
	ndiff = array(round(diffnorm(gpnl,gptl)),dim=dim(gpnl))
	cat(" step",sprintf(fmt,noms),"\n")
	nt = dim(gpnl)[1]
	if (all(ndiff == 0)) {
		for (i in seq(min(5,nt))) cat(format(st1[i],width=5),sprintf(fmt,ndiff[i,1,1,]),"\n")
	} else {
		if (nt > 30) {
			ind = seq(1,nt,by=nt%/%30)
		} else {
			ind = seq(nt)
		}

		for (i in ind) cat(format(st1[i],width=5),sprintf(fmt,ndiff[i,1,1,]),"\n")
	}
}
