mitra = "~/mitraille"

args = strsplit(commandArgs(trailingOnly=TRUE),split="=")
cargs = lapply(args,function(x) strsplit(x[-1],split=":")[[1]])
names(cargs) = sapply(args,function(x) x[1])

temps = read.table("elapse.txt",col.names=c("conf","tei"))
x = as.numeric(as.difftime(temps$tei),units="mins")
x2 = .5 + x + sqrt(5+2*x)
temps$tei2 = round(x2,-floor(log10(x2)))

profils = read.table(sprintf("%s/config/profil_table",mitra),header=TRUE,
	comment.char="")
names(profils)[1] = "conf"

ic = temps$conf %in% profils$conf
ind = match(temps$conf[ic],profils$conf)
profils$cputime[ind] = temps$tei2[ic]
profils$walltime[ind] = profils$cputime[ind]

ic = ! profils$conf %in% temps$conf
profils$cputime[ic] = round(profils$cputime[ic]/as.numeric(cargs$factor))
profils$walltime[ic] = profils$cputime[ic]

names(profils)[1] = "#conf"
cat("Writing new profil_table\n")
write.table(profils,"profil_table",quote=FALSE,row.names=FALSE,sep="\t")
