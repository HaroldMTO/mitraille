Gndigits = round(log10(.Machine$double.eps))
Gnum = "-?\\d*\\.\\d+([eE]?[-+]?\\d+)?\\>"
Gint = "-?\\d+\\>"

getarg = function(x,args)
{
	ind = grep(sprintf("\\<%s=",x),args)
	if (length(ind) == 0) return(NULL)

	strsplit(sub(sprintf("\\<%s=",x),"",args[ind]),split=":")[[1]]
}

getvar = function(var,nd,sep="=")
{
	re = sprintf("^ *\\<%s *%s *(%s|%s).*",var,sep,Gint,Gnum)
	unique(as.numeric(gsub(re,"\\1",grep(re,nd,value=TRUE))))
}

line2num = function(nd)
{
	lre = regmatches(nd,gregexpr(sprintf("(%s|\\<NaN\\>)",Gnum),nd))
	lre = lapply(lre,function(x) gsub("(\\d+)(\\-\\d+)","\\1E\\2",x))
	sapply(lre,as.numeric)
}

spnorm = function(nd,lev,ind)
{
	if (missing(ind)) {
		ind = grep("SPECTRAL NORMS",nd)
		inds = grep("NORMS AT NSTEP CNT4",nd[ind-1])
		ind = ind[inds]
	}

	spsp = as.numeric(gsub("SPECTRAL NORMS.+ ([-0-9.E+]+|NaN)$","\\1",nd[ind]))

	noms = strsplit(nd[ind[1]+1]," {2,}")[[1]][-1]
	noms[noms == "KINETIC ENERGY"] = "TKE"

	indi = rep(ind,each=length(lev))+lev+2

	spn = line2num(nd[indi])

	nt = length(spn)/(length(lev)*length(noms))
	stopifnot(nt == as.integer(nt))

	dim(spn) = c(length(noms),length(lev),nt)
	spn = aperm(spn,c(3,2,1))

	if (length(lev) == 1) {
		spn = c(spn,spsp)
		noms = c(noms,"SP")
		dim(spn) = c(nt,length(lev),length(noms))
	}

	if (any(regexpr("\\<LNHDYN *= *T",nd) > 0)) {
		if (has.levels) {
			indi = indi+nflevg+2
			indn = ind[1]+nflevg+3
		} else {
			indi = indi+2
			indn = ind[1]+3
		}

		spnh = line2num(nd[indi])

		nomsnh = strsplit(nd[indn]," {2,}")[[1]][-1]
		nomsnh[nomsnh == "LOG(PRE/PREHYD)"] = "LOG(P/P_hyd)"
		nomsnh[nomsnh == "d4 = VERT DIV + X"] = "d4 (= vdiv+X)"

		dim(spnh) = c(length(nomsnh),length(lev),nt)
		spnh = aperm(spnh,c(3,2,1))
		spn = c(spn,spnh)
		noms = c(noms,nomsnh)
		dim(spn) = c(nt,length(lev),length(noms))
	}

	ip = grep("LOG\\(P/P_hyd\\)|d4",noms,invert=TRUE)
	noms[ip] = abbreviate(noms[ip])

	istep = sub("NORMS AT NSTEP CNT4( \\(PREDICTOR\\))? +(\\d+)","\\2",nd[ind-1])
	dimnames(spn) = list(istep,lev,noms)

	spn
}

diffnorm = function(x,y)
{
	x0 = pmax(abs(x),abs(y))
	ndiff = pmax(Gndigits,1+log10(abs(y-x))-log10(x0))-Gndigits
	ndiff[which(x0 == 0)] = 0
	ndiff
}

args = strsplit(commandArgs(trailingOnly=TRUE),split="=")
cargs = lapply(args,function(x) unlist(strsplit(x[-1],split=":")))
names(cargs) = sapply(args,function(x) x[1])
lev = 0

nd = readLines(cargs$fic1)
nd = grep("^ *$",nd,value=TRUE,invert=TRUE)
nflevg = getvar("NFLEVG",nd)
has.levels = getvar("NSPPR",nd) > 0
nstop = getvar("NSTOP",nd)
ts1 = getvar("TSTEP",nd)

ind = grep("SPECTRAL NORMS",nd)
ind1 = grep("NORMS AT NSTEP CNT4",nd[ind-1])
sp1 = spnorm(nd,lev,ind[ind1])
nfrsdi = getvar(".+ NFRSDI",nd)
istep1 = seq(0,nstop,by=nfrsdi)

nt = dim(sp1)[1]
if (length(istep1) > nt) length(istep1) = nt

nd = readLines(cargs$fic2)
nd = grep("^ *$",nd,value=TRUE,invert=TRUE)
nflevg = getvar("NFLEVG",nd)
has.levels = getvar("NSPPR",nd) > 0
nstop = getvar("NSTOP",nd)
ts2 = getvar("TSTEP",nd)

ind = grep("SPECTRAL NORMS",nd)
ind1 = grep("NORMS AT NSTEP CNT4",nd[ind-1])
sp2 = spnorm(nd,lev,ind[ind1])
nfrsdi = getvar(".+ NFRSDI",nd)
istep2 = seq(0,nstop,by=nfrsdi)

nt = dim(sp2)[1]
if (length(istep2) > nt) length(istep2) = nt

noms1 = dimnames(sp1)[[3]]
noms2 = dimnames(sp2)[[3]]

indv = match(noms1,noms2)
if (any(is.na(indv))) cat("missing variables :",noms1[is.na(indv)],"\n")

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

sp1 = sp1[na.omit(indt),,na.omit(indv),drop=FALSE]
sp2 = sp2[it,,iv,drop=FALSE]
ndiff = sapply(1:dim(sp1)[3],function(i) diffnorm(sp1[,1,i],sp2[,1,i]))
ndiff = matrix(round(ndiff),ncol=dim(sp1)[3])
cat(" step",sprintf("%5s",noms1[na.omit(indv)]),"\n")
nt = dim(sp1)[1]
if (all(ndiff == 0)) {
	for (i in seq(min(5,nt))) cat(format(i-1,width=5),sprintf("%5g",ndiff[i,]),"\n")
	if (nt > 5) cat("...",nt-min(5,nt),"more 0 lines\n")
} else {
	if (nt > 30) {
		ind = seq(1,nt,by=nt%/%30)
	} else {
		ind = seq(nt)
	}

	for (i in ind) cat(format(i-1,width=5),sprintf("%5g",ndiff[i,]),"\n")
}