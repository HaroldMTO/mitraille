noms = c("field","min","max","mean","rms","non0")
re3D = "^[HPS][0-9]{3,5}"
args = strsplit(commandArgs(trailingOnly=TRUE),split="=")
cargs = lapply(args,function(x) unlist(strsplit(x[-1],split=":")))
names(cargs) = sapply(args,function(x) x[1])

fics = cargs$fic
if (file.exists(fics) && file.info(fics)$isdir) fics = dir(fics,"\\.diff",full.names=TRUE)
stopifnot(length(fics) > 0 && file.exists(fics))

for (i in seq(along=fics)) {
	cat("\nfile",sub("\\.diff","",basename(fics[i])),":\n")
	df = try(read.table(fics[i],skip=1,col.names=noms),silent=TRUE)
	if (is(df,"try-error")) {
		system(paste("sed -i -re 's: +([A-Z][A-Z0-9_.]+):_\\1:g'",fics[i]))
		df = read.table(fics[i],skip=1,col.names=noms)
	}

	f3D = unique(sort(gsub(re3D,"",grep(re3D,df$field,value=TRUE))))
	f2D = unique(sort(grep(re3D,df$field,invert=TRUE,value=TRUE)))

	for (f in f2D) {
		ind = grep(f,df$field)
		cat(" 2D field",sprintf("%-16s",f),":",summary(df$mean[ind]),"\n")
	}

	cat("--\n")

	for (f in f3D) {
		ind = grep(sprintf("%s%s",re3D,f),df$field)
		cat(" 3D field",sprintf("%-16s",f),":",summary(df$mean[ind]),"\n")
	}
}
