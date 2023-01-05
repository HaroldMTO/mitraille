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
	noms[noms == "TEMPRATURE"] = "TEMP"
	noms[noms == "U VELOCITY"] = "U VELOC."
	noms[noms == "V VELOCITY"] = "V VELOC."
	noms = sub("ADIAB_","ADIA_",noms)
	noms = sub("GRAD([LM])","GR\\1",noms)

	nt = length(gpn)/(3*length(lev)*length(noms))
	stopifnot(nt == as.integer(nt))

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

countfield = function(ind,ind2,nl2)
{
	which(diff(ind[seq(ind2[1],ind2[2])]) > nl2)[1]
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
gpfre3 = "(ATND|ADIAB|CTY|SISL)_\\w+"
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
if (length(icnt4) == 0) {
	cat("--> no forecast conf (cnt4) in 1st file\n")
	quit("no")
}

ind = grep("GPNORM +\\w+.* +AVERAGE",nd)
ind = ind[ind > icnt4[1]]

# check presence of norms for GFL t0
indo = grep(sprintf("GPNORM +(%s|OUTPUT) +AVERAGE",gpfre),nd[ind],invert=TRUE)
if (length(indo) == 0) {
	cat("--> no GP norms in 1st file\n")
	q("no")
}

if (cargs$gpre == "gpnorm gflt0") {
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
	gp1 = gpnorm(nd,lev,ind,noms)
} else {
	ind1 = grep(cargs$gpre,nd[ind-1],ignore.case=TRUE)
	if (length(ind1) == 0) stop(paste("no GP norms for pattern",cargs$gpre))
	nf = countfield(ind,ind1,nl2)
	indi = indexpand(ind[ind1],nf,nl2)
	gp1 = gpnorm(nd,lev,indi)
}

nfrgdi = getvar(".+ NFRGDI",nd)
istep1 = seq(0,nstop,by=nfrgdi)
nt = dim(gp1)[1]
if (length(istep1) > nt) length(istep1) = nt

nd = readLines(cargs$fic2)
nd = grep("^ *$",nd,value=TRUE,invert=TRUE)
nstop = getvar("NSTOP",nd)
ts2 = getvar("TSTEP",nd)
icnt4 = grep("START CNT4",nd)
if (length(icnt4) == 0) {
	cat("--> no forecast conf (cnt4) in 1st file\n")
	quit("no")
}

ind = grep("GPNORM +\\w+.* +AVERAGE",nd)
ind = ind[ind > icnt4[1]]

if (ts1 != ts2) stop("different TSTEP")

indo = grep(sprintf("GPNORM +(%s|OUTPUT) +AVERAGE",gpfre),nd[ind],invert=TRUE)
if (length(indo) == 0) {
	cat("--> no GP norms in 2nd file\n")
	q("no")
}

if (cargs$gpre == "gpnorm gflt0") {
	# looking for the 1st group of norm print
	ind = ind[indo]
	i1 = grep("^ *gpnorm +\\w",nd)
	if (length(i1) > 0) i1 = i1[i1 > icnt4[1]]
	if (length(i1) > 0) ind = ind[ind < i1[1]]

	noms = unique(sub(" *GPNORM +(\\w+.+?) +AVERAGE.+","\\1",nd[ind]))
	gp2 = gpnorm(nd,lev,ind,noms)
} else {
	ind1 = grep(cargs$gpre,nd[ind-1],ignore.case=TRUE)
	if (length(ind1) == 0) stop(paste("no GP norms for pattern",cargs$gpre))
	nf = countfield(ind,ind1,nl2)
	indi = indexpand(ind[ind1],nf,nl2)
	gp2 = gpnorm(nd,lev,indi)
}

nfrgdi = getvar(".+ NFRGDI",nd)
istep2 = seq(0,nstop,by=nfrgdi)
nt = dim(gp2)[1]
if (length(istep2) > nt) length(istep2) = nt

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

gp1 = gp1[na.omit(indt),,,na.omit(indv),drop=FALSE]
gp2 = gp2[it,,,iv,drop=FALSE]
ndiff = sapply(1:dim(gp1)[4],function(i) diffnorm(gp1[,1,1,i],gp2[,1,1,i]))
ndiff = matrix(round(ndiff),ncol=dim(gp1)[4])

noms = abbreviate(noms1[na.omit(indv)])
if (max(nchar(noms)) > 5) {
	fmt = "%6g"
	cat(" step",sprintf("%6s",noms),"\n")
} else {
	fmt = "%5g"
	cat(" step",sprintf("%5s",noms),"\n")
}

nt = dim(gp1)[1]
if (all(ndiff == 0)) {
	for (i in seq(min(5,nt))) cat(format(i-1,width=5),sprintf(fmt,ndiff[i,]),"\n")
	if (nt > 5) cat("...",nt-min(5,nt),"more 0 lines\n")
} else {
	if (nt > 30) {
		ind = seq(1,nt,by=nt%/%30)
	} else {
		ind = seq(nt)
	}

	for (i in ind) cat(format(i-1,width=5),sprintf(fmt,ndiff[i,]),"\n")
}
