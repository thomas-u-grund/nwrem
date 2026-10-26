suppressMessages(library(relevent))
a <- commandArgs(TRUE); B <- Sys.getenv("BENCH"); id <- a[1]; sn <- a[2]; rp <- as.integer(a[3])
sets <- list(S1_nodsnd_nidrec=c("NODSnd","NIDRec"), S2_degree4=c("NODSnd","NIDRec","NIDSnd","NODRec"),
 S3_degree4_inertia=c("NODSnd","NIDRec","NIDSnd","NODRec","FrPSndSnd","FrRecSnd"), S4_recency=c("NODSnd","NIDRec","RSndSnd","RRecSnd"),
 S5_covariates=c("NODSnd","NIDRec","CovSnd","CovRec","CovInt"))
ev <- read.csv(file.path(B, paste0(id,"_events.csv"))); cv <- read.csv(file.path(B, paste0(id,"_cov.csv")))
el <- cbind(ev$eventtime, ev$sender, ev$receiver); n <- nrow(cv)
t0 <- proc.time()[["elapsed"]]
f <- rem.dyad(el, n, effects=sets[[sn]], covar=if (sn=="S5_covariates") list(CovSnd=cv$covsnd, CovRec=cv$covrec, CovInt=cv$covint) else NULL,
  ordinal=TRUE, fit.method="MLE", hessian=TRUE, gof=FALSE, verbose=FALSE)
t <- proc.time()[["elapsed"]] - t0
cat(sprintf('%s,%s,%d,%.3f,"%s","%s"\n', id, sn, rp, t, paste(sprintf("%.10g", f$coef), collapse=" "), paste(names(f$coef), collapse=" ")))
