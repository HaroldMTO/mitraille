Gndigits = round(log10(.Machine$double.eps))

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

diffnorm = function(x,y)
{
	x0 = pmax(abs(x),abs(y))
	ndiff = pmax(Gndigits,1+log10(abs(y-x))-log10(x0)) - Gndigits
	ndiff[is.nan(ndiff)] = 0
	ndiff
}

args = strsplit(commandArgs(trailingOnly=TRUE),split="=")
cargs = lapply(args,function(x) unlist(strsplit(x[-1],split=":")))
names(cargs) = sapply(args,function(x) x[1])

lgp1 = gpnorms(cargs$fic1,as.logical(cargs$fp))
lgp2 = gpnorms(cargs$fic2,as.logical(cargs$fp))

if (identical(lgp1,lgp2)) {
	cat("  --> no GP norms difference\n")
} else {
	ind = match(names(lgp2),names(lgp1))
	if (any(is.na(ind))) cat("new norms :",names(lgp2)[is.na(ind)],"\n")

	ind = match(names(lgp1),names(lgp2))
	if (any(is.na(ind))) cat("missing norms :",names(lgp1)[is.na(ind)],"\n")

	for (i in which(! is.na(ind))) {
		ndiff = diffnorm(lgp1[[i]],lgp2[[ind[i]]])
		if (all(ndiff == 0)) next

		cat("\t",names(lgp1)[i],":",sprintf("\t%.4g",ndiff),"\n")
	}
}
