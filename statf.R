nomsd = c("field","min","max","mean","rms","non0")
nomsf = c("field","min","max","mean","rms","quadmean","non0")
re3D = "^[HPS][0-9]{3,5}"
args = strsplit(commandArgs(trailingOnly=TRUE),split="=")
cargs = lapply(args,function(x) unlist(strsplit(x[-1],split=":")))
names(cargs) = sapply(args,function(x) x[1])

ext = "diff"
if ("ext" %in% names(cargs)) ext = cargs$ext
if (ext == "diff") {
	noms = nomsd
	main = "Mean difference (w/r to ref.)"
	ylab = "Mean difference"
} else if (ext == "txt") {
	noms = nomsf
	main = "Mean value"
	ylab = "Mean value"
}

fics = cargs$fic
if (file.exists(fics) && file.info(fics)$isdir)
	fics = dir(fics,sprintf("\\.%s",ext),full.names=TRUE)
stopifnot(length(fics) > 0 && all(file.exists(fics)))

graph = FALSE
if ("graph" %in% names(cargs)) graph = as.logical(cargs$graph)

for (i in seq(along=fics)) {
	cat("\nfile",sub(sprintf("\\.%s",ext),"",basename(fics[i])),":\n")
	df = try(read.table(fics[i],col.names=noms),silent=TRUE)
	if (is(df,"try-error")) {
		system(paste("sed -i -re 's: +([A-Z][A-Z0-9_.]+):_\\1:g'",fics[i]))
		df = read.table(fics[i],col.names=noms)
	}

	f3D = unique(sort(gsub(re3D,"",grep(re3D,df$field,value=TRUE))))
	f2D = unique(sort(grep(re3D,df$field,invert=TRUE,value=TRUE)))

	for (f in f2D) {
		ind = grep(f,df$field)
		cat(" 2D field",sprintf("%-16s",f),":",summary(df$mean[ind]),"\n")
	}

	if (length(f3D) > 0) {
		cat("--\n")

		for (f in f3D) {
			ind = grep(sprintf("%s%s",re3D,f),df$field)
			cat(" 3D field",sprintf("%-16s",f),":",summary(df$mean[ind]),"\n")
		}
	}

	if (graph) {
		lsf2 = lapply(f2D,function(f) df$mean[grep(f,df$field)])
		names(lsf2) = f2D
		lsf3 = lapply(f3D,function(f) df$mean[grep(sprintf("%s%s",re3D,f),df$field)])
		names(lsf3) = f3D

		if (i == 1) {
			df2 = as.data.frame(lsf2)
			df3 = as.data.frame(lsf3)
			nlev = dim(df3)[1]
		} else {
			df2 = merge(df2,as.data.frame(lsf2),all=TRUE)
			df3 = merge(df3,as.data.frame(lsf3),all=TRUE)
		}

		lsf2 = lapply(f2D,function(f) df$rms[grep(f,df$field)])
		names(lsf2) = f2D
		lsf3 = lapply(f3D,function(f) df$rms[grep(sprintf("%s%s",re3D,f),df$field)])
		names(lsf3) = f3D

		if (i == 1) {
			dfr2 = as.data.frame(lsf2)
			dfr3 = as.data.frame(lsf3)
		} else {
			dfr2 = merge(dfr2,as.data.frame(lsf2),all=TRUE)
			dfr3 = merge(dfr3,as.data.frame(lsf3),all=TRUE)
		}
	}
}

if (graph) {
	taux = .1
	dfn = df2-taux*dfr2
	dfx = df2+taux*dfr2
	png("ts2D.png")
	matplot(df2,type="o",pch=20,lty=1,main=paste(main,"of 2D fields"),
		xlab="Forecast step (number)",ylab=ylab,ylim=range(dfn,dfx))
	matpoints(dfn,pch="-")
	matpoints(dfx,pch="+")
	legend("bottomright",names(df2),pch=20,lty=1,col=seq(along=df2))
	dev.off()

	m3 = as.matrix(df3)
	m3 = as.array(m3)
	dim(m3) = c(nlev,length(fics),dim(m3)[2])

	mr3 = as.matrix(dfr3)
	mr3 = as.array(mr3)
	dim(mr3) = c(nlev,length(fics),dim(mr3)[2])

	noms3 = names(df3)
	ind = match(c("TEMPERATURE","HUMI.SPECIFI","TKE"),noms3)
	if (all(is.na(ind))) {
		cat("--> fields T, Q and TKE not present\n")
	} else {
		m3 = m3[,,ind]
		mr3 = mr3[,,ind]

		mn = m3-taux*mr3
		mx = m3+taux*mr3

		png("ts3D.png")
		par(mfrow=c(2,2),cex=.8)
		for (i in c(1,nlev%/%3,(2*nlev)%/%3,nlev)) {
			matplot(m3[i,,],type="o",pch=20,lty=1,main=paste(main,"of 2D fields"),
				sub=paste("level",i),xlab="Forecast step (number)",ylab=ylab,
				ylim=range(mn[i,,],mx[i,,]))
			matpoints(mn[i,,],pch="-")
			matpoints(mx[i,,],pch="+")
			legend("bottomright",noms3[ind],pch=20,lty=1,col=seq(along=ind))
		}
		dev.off()
	}
}
