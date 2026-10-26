suppressMessages(library(relevent))
B <- Sys.getenv("BENCH")
sizes <- data.frame(id=c("e200","e1000","e5000","e20000"), nev=c(200,1000,5000,20000), n=c(20,30,50,100))
sets <- list(
  S1_nodsnd_nidrec = list(eff=c("NODSnd","NIDRec"), cov=FALSE),
  S2_degree4       = list(eff=c("NODSnd","NIDRec","NIDSnd","NODRec"), cov=FALSE),
  S3_degree4_inertia = list(eff=c("NODSnd","NIDRec","NIDSnd","NODRec","FrPSndSnd","FrRecSnd"), cov=FALSE),
  S4_recency       = list(eff=c("NODSnd","NIDRec","RSndSnd","RRecSnd"), cov=FALSE),
  S5_covariates    = list(eff=c("NODSnd","NIDRec","CovSnd","CovRec","CovInt"), cov=TRUE))
allids <- sizes$id
only <- Sys.getenv("ONLY_SIZES"); if (nzchar(only)) sizes <- sizes[sizes$id %in% strsplit(only,",")[[1]],]
gen <- function(nev, n, seed) {
  set.seed(seed)
  cs <- rnorm(n); cr <- rnorm(n); ci <- rnorm(n)
  ws <- exp(0.7*rnorm(n) + 0.3*cs); wr <- exp(0.7*rnorm(n) + 0.2*cr)
  el <- matrix(0, nev, 3); last <- NULL
  for (i in seq_len(nev)) {
    u <- runif(1)
    if (i > 1 && u < 0.2) { j <- sample.int(i-1,1); s <- el[j,2]; r <- el[j,3] }
    else if (i > 1 && u < 0.3) { j <- sample.int(i-1,1); s <- el[j,3]; r <- el[j,2] }
    else { s <- sample.int(n,1,prob=ws); r <- sample.int(n,1,prob=wr); while (r==s) r <- sample.int(n,1,prob=wr) }
    el[i,] <- c(i,s,r)
  }
  # make sure every actor appears
  miss <- setdiff(seq_len(n), unique(c(el[,2],el[,3])))
  for (m in miss) { k <- sample.int(nev,1); if (runif(1)<.5) el[k,2] <- m else el[k,3] <- m
    if (el[k,2]==el[k,3]) el[k,3] <- (el[k,3] %% n) + 1 }
  stopifnot(all(el[,2]!=el[,3]), length(unique(c(el[,2],el[,3])))==n)
  list(el=el, cs=cs, cr=cr, ci=ci)
}
res <- list()
for (k in seq_len(nrow(sizes))) {
  sz <- sizes[k,]; d <- gen(sz$nev, sz$n, 20261026+match(sz$id, allids))
  write.csv(data.frame(sender=d$el[,2], receiver=d$el[,3], eventtime=d$el[,1]), file.path(B, paste0(sz$id,"_events.csv")), row.names=FALSE)
  write.csv(data.frame(covsnd=d$cs, covrec=d$cr, covint=d$ci), file.path(B, paste0(sz$id,"_cov.csv")), row.names=FALSE)
  reps <- if (sz$nev >= 20000) 3 else 5
  for (sn in names(sets)) for (hess in c(TRUE, FALSE)) {
    st <- sets[[sn]]
    for (rp in seq_len(reps)) {
      t0 <- proc.time()[["elapsed"]]
      out <- tryCatch({ setTimeLimit(elapsed=600, transient=TRUE)
        f <- rem.dyad(d$el, sz$n, effects=st$eff, covar=if (st$cov) list(CovSnd=d$cs, CovRec=d$cr, CovInt=d$ci) else NULL,
                      ordinal=TRUE, fit.method="MLE", hessian=hess, gof=FALSE, verbose=FALSE)
        f$coef }, error=function(e) NULL)
      el_t <- proc.time()[["elapsed"]] - t0
      res[[length(res)+1]] <- data.frame(size=sz$id, set=sn, hessian=hess, rep=rp, secs=el_t, ok=!is.null(out),
          coef=if (is.null(out)) "" else paste(sprintf("%.10g", out), collapse=" "), names=if (is.null(out)) "" else paste(names(out), collapse=" "))
      cat(sz$id, sn, hess, rp, round(el_t,2), "\n"); flush.console()
      if (el_t > 120 && rp >= 2) break
    }
  }
  write.csv(do.call(rbind,res), file.path(B, paste0("R_times_", Sys.getenv("TAG","all"), ".csv")), row.names=FALSE)
}
