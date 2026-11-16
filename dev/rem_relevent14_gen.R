# dev/rem_relevent14_gen.R -- generates the reference values of cscripts/test_nwrem_relevent14.do (nwrem 1.4.0) with the R package
# relevent (1.2-1): event logs, covariates, risk sets, and for every case the coefficients, standard errors and log likelihood
# of two relevent routes:
#   "trust": the statistics are taken from relevent's own routines (rem.dyad.lambda with unit coefficients) and fitted with
#            rem() (analytic gradient and Hessian, trust-region optimiser): the exact maximum of relevent's likelihood;
#   "dyad":  rem.dyad() itself (BFGS with a numerical Hessian), where the model is a rem.dyad model; it stops earlier (the
#            fifth to sixth digit of the coefficients, the fourth of the standard errors).
# Cases that rem.dyad() cannot fit (risk sets, entry/exit windows, the symmetric shared out-partner statistic) have the "trust"
# route only; for them the statistics are built here, with the likelihood still computed by relevent's rem().
# Run from the root of the repository: Rscript dev/rem_relevent14_gen.R   (writes cscripts/ref14/*)
suppressMessages(library(relevent))
outdir <- "cscripts/ref14"
dir.create(outdir, showWarnings = FALSE, recursive = TRUE)

nwrem_order <- c("nodsnd","nidrec","nidsnd","nodrec","ntdegsnd","ntdegrec","frpsndsnd","frrecsnd","covsnd","covrec","covint","covevent",
                 "rsndsnd","rrecsnd","otpsnd","itpsnd","ospsnd","ispsnd","fesnd","ferec","feint",
                 "psabba","psabby","psabxa","psabxb","psabxy","psabay")
relname <- c(nodsnd="NODSnd",nidrec="NIDRec",nidsnd="NIDSnd",nodrec="NODRec",ntdegsnd="NTDegSnd",ntdegrec="NTDegRec",frpsndsnd="FrPSndSnd",
             frrecsnd="FrRecSnd",rsndsnd="RSndSnd",rrecsnd="RRecSnd",covsnd="CovSnd",covrec="CovRec",covint="CovInt",covevent="CovEvent",
             otpsnd="OTPSnd",itpsnd="ITPSnd",ospsnd="OSPSnd",ispsnd="ISPSnd",fesnd="FESnd",ferec="FERec",feint="FEInt",
             psabba="PSAB-BA",psabby="PSAB-BY",psabxa="PSAB-XA",psabxb="PSAB-XB",psabxy="PSAB-XY",psabay="PSAB-AY")
allenam <- c("NIDSnd","NIDRec","NODSnd","NODRec","NTDegSnd","NTDegRec","FrPSndSnd","FrRecSnd","RRecSnd","RSndSnd","CovSnd","CovRec","CovInt","CovEvent",
             "OTPSnd","ITPSnd","OSPSnd","ISPSnd","FESnd","FERec","FEInt","PSAB-BA","PSAB-B0","PSAB-BY","PSA0-X0","PSA0-XA","PSA0-XY","PSAB-X0",
             "PSAB-XA","PSAB-XB","PSAB-XY","PSA0-AY","PSAB-A0","PSAB-AY")
# relevent's coefficient name -> the name nwrem gives the coefficient
nwname <- function(rn) {
  rn <- sub("^CovSnd\\.(.*)$", "covsnd_x\\1", rn); rn <- sub("^CovRec\\.(.*)$", "covrec_x\\1", rn)
  rn <- sub("^CovInt\\.(.*)$", "covint_x\\1", rn); rn <- sub("^CovEvent\\.(.*)$", "covevent_cev\\1", rn)
  rn <- sub("^FESnd\\.(.*)$", "fesnd_\\1", rn); rn <- sub("^FERec\\.(.*)$", "ferec_\\1", rn); rn <- sub("^FEInt\\.(.*)$", "feint_\\1", rn)
  rn <- sub("^PSAB-", "psab", rn)
  ifelse(grepl("_", rn), rn, tolower(rn))
}

sim_log <- function(n, m, seed, ties = FALSE, entry = rep(-Inf, n), exit = rep(Inf, n)) {
  repeat {
    set.seed(seed)
    ws <- exp(rnorm(n, 0, .7)); wr <- exp(rnorm(n, 0, .7))
    el <- matrix(0, m, 3)
    t <- 0
    for (i in 1:m) {
      t <- t + rexp(1, n / 2)
      if (i > 1 && runif(1) < .15) { el[i, 2:3] <- el[i - 1, 3:2] }          # a reply
      else if (i > 3 && runif(1) < .15) { el[i, 2:3] <- el[sample(i - 1, 1), 2:3] }   # a repeated dyad
      else { act <- (entry <= t & t <= exit); repeat { s <- sample(n, 1, prob = ws * act); r <- sample(n, 1, prob = wr * act); if (s != r) break }; el[i, 2:3] <- c(s, r) }
      if (any(!(entry[el[i, 2:3]] <= t & t <= exit[el[i, 2:3]]))) { el[i, 2:3] <- { act <- (entry <= t & t <= exit); repeat { s <- sample(n, 1, prob = ws * act); r <- sample(n, 1, prob = wr * act); if (s != r) break }; c(s, r) } }
      el[i, 1] <- t
    }
    if (length(unique(c(el[, 2], el[, 3]))) == n) break
    seed <- seed + 1000
  }
  el
}

dyadtypes <- function(n) { id <- matrix(0L, n, n); k <- 0L; for (j in 1:n) for (l in 1:n) if (j != l) { k <- k + 1L; id[j, l] <- k }; id }

# the statistic cube (iterations x dyad types x parameters) from relevent's own routines (rem.dyad.lambda with unit coefficients);
# the dyad types are numbered row-major (sender, then receiver)
cube_relevent <- function(elx, n, effects, covar) {
  {
    M <- NROW(elx)
    flags <- allenam %in% effects
    skel <- rem.dyad(NULL, n, effects = effects, covar = covar, verbose = FALSE)
    pn <- names(skel$coef)
    cv <- if (!is.null(covar)) covarPrep(covar, n = n, m = M, effects = flags) else NULL
    acl <- accum.interact(elx); cumi <- acl.deg(acl, n, "in"); cumo <- acl.deg(acl, n, "out")
    rrl <- if (any(flags[9:10])) accum.rrl(elx) else NULL
    ps <- if (any(flags[22:34])) acl.ps(elx, n) else NULL
    tri <- if (any(flags[15:18])) acl.tri(acl) else NULL
    id <- dyadtypes(n); net <- n * (n - 1)
    jj <- row(id)[id > 0][order(id[id > 0])]; kk <- col(id)[id > 0][order(id[id > 0])]
    cube <- array(0, c(M, net, length(pn)), dimnames = list(NULL, NULL, pn))
    for (p in seq_along(pn)) {
      pv <- rep(0, length(pn)); pv[p] <- 1
      for (i in 1:M) {
        L <- rem.dyad.lambda(pv, i, flags, n, M, acl[[i]], cumi, cumo, rrl, cv, ps, tri)   # lambda() wants the acl of the iteration only
        cube[i, , p] <- L[cbind(jj, kk)]
      }
    }
    cube
  }
}

# own symmetric shared out-partner statistic (relevent's OSPSnd is asymmetric; see rem_sim.c)
cube_osp <- function(elx, n) {
  M <- NROW(elx); id <- dyadtypes(n); net <- n * (n - 1)
  jj <- row(id)[id > 0][order(id[id > 0])]; kk <- col(id)[id > 0][order(id[id > 0])]
  cube <- array(0, c(M, net, 1))
  C <- matrix(0, n, n)
  for (i in 1:M) {
    if (i > 1) C[elx[i - 1, 2], elx[i - 1, 3]] <- C[elx[i - 1, 2], elx[i - 1, 3]] + 1
    S <- matrix(0, n, n)
    for (a in 1:n) for (b in 1:n) if (a != b) S[a, b] <- sum(pmin(C[a, ], C[b, ]))
    cube[i, , 1] <- S[cbind(jj, kk)]
  }
  cube
}

ref_trust <- function(el, n, cube, interval, supp = NULL, estimator = "MLE", prior = list(mu = 0, sigma = 100, nu = 4), cond = 0, endtime = NULL) {
  m <- NROW(el); id <- dyadtypes(n)
  types <- id[cbind(el[, 2], el[, 3])]
  rows <- 1:m
  if (interval) {
    T <- endtime
    evl <- rbind(cbind(types, el[, 1]), c(0, T))
    rows <- 1:(m + 1)
  } else evl <- cbind(types, 1:m)
  cb <- cube[rows, , , drop = FALSE]
  sp <- if (is.null(supp)) matrix(TRUE, length(rows), n * (n - 1)) else supp[rows, , drop = FALSE]
  if (cond > 0) {                                   # drop the conditioned events from the likelihood, keep their history
    keep <- (cond + 1):length(rows)
    t0 <- evl[cond, 2]
    evl <- evl[keep, , drop = FALSE]
    if (interval) evl[, 2] <- evl[, 2] - t0 else evl[, 2] <- seq_len(nrow(evl))
    cb <- cb[keep, , , drop = FALSE]; sp <- sp[keep, , drop = FALSE]
  }
  f <- rem(evl, list(list(global = cb)), list(sp), timing = if (interval) "interval" else "ordinal", estimator = estimator, prior.param = prior)
  list(coef = f$coef, se = if (estimator == "MLE") f$se else f$sd, ll = f$loglik, hess = f$hessian)
}

ref_dyad <- function(el, n, effects, covar, interval, cond = 0, method = "MLE", endtime = NULL, prior = list(mu = 0, sigma = 100, nu = 4)) {
  m <- NROW(el)
  elx <- if (interval) rbind(el, c(endtime, NA, NA)) else el
  f <- rem.dyad(elx, n, effects = effects, covar = covar, ordinal = !interval, fit.method = method, hessian = TRUE, gof = FALSE, verbose = FALSE,
                optim.control = list(reltol = 1e-14, maxit = 5000), conditioned.obs = cond,
                prior.mean = prior$mu, prior.scale = prior$sigma, prior.nu = prior$nu)
  se <- sqrt(diag(f$cov))
  list(coef = f$coef, se = se, ll = -f$residual.deviance / 2)
}

results <- list()
cases <- list()
curcovar <- NULL
# relevent numbers the covariates of an effect by position (covsnd_x1, covsnd_x2); nwrem names them by variable
posname <- function(p) {
  for (e in c("CovSnd", "CovRec", "CovInt")) {
    m <- regmatches(p, regexec(paste0("^", tolower(e), "_x([0-9]+)$"), p))[[1]]
    if (length(m) == 2 && !is.null(curcovar[[e]])) return(paste0(tolower(e), "_", colnames(curcovar[[e]])[as.integer(m[2])]))
  }
  p
}
add_result <- function(case, route, r) {
  results[[length(results) + 1]] <<- data.frame(case = case, route = route, param = sapply(nwname(names(r$coef)), posname, USE.NAMES = FALSE), coef = as.numeric(r$coef),
                                                se = as.numeric(r$se), ll = r$ll, stringsAsFactors = FALSE)
}
write_case <- function(case, n, el, opts, actors = NULL, nets = list(), note = "") {
  write.csv(data.frame(sender = el[, 2], receiver = el[, 3], t = el[, 1]), sprintf("%s/%s.events.csv", outdir, case), row.names = FALSE)
  if (!is.null(actors)) write.csv(actors, sprintf("%s/%s.actors.csv", outdir, case), row.names = FALSE, na = "")
  for (nm in names(nets)) {
    M <- nets[[nm]]; id <- dyadtypes(n)
    d <- data.frame(i = row(M)[row(M) != col(M)], j = col(M)[row(M) != col(M)], value = M[row(M) != col(M)])
    write.csv(d, sprintf("%s/%s.%s.csv", outdir, case, nm), row.names = FALSE)
  }
  cases[[length(cases) + 1]] <<- data.frame(case = case, n = n, m = NROW(el), opts = opts, nets = paste(names(nets), collapse = " "),
                                            actors = !is.null(actors), note = note, stringsAsFactors = FALSE)
}

# ---- one generic case runner ---------------------------------------------------------------------------------------------------
# eff: nwrem effect names; covar: relevent covar list; nwopts: the nwrem option text for the covariates; extra: interval, cond ...
run_case <- function(case, n, m, seed, eff, covar = NULL, nwopts = "", interval = FALSE, cond = 0, endtime = NULL, actors = NULL, nets = list(),
                     dyad = TRUE, own_osp = FALSE, supp = NULL, method = "MLE", note = "", tomit = NULL, el = NULL, prior = list(mu = 0, sigma = 100, nu = 4)) {
  curcovar <<- covar
  if (is.null(el)) el <- sim_log(n, m, seed)
  if (interval && is.null(endtime)) endtime <- el[NROW(el), 1] + 1
  releff <- relname[setdiff(eff, tomit)]
  if (own_osp) releff <- setdiff(releff, "OSPSnd")
  cube <- cube_relevent(if (interval) rbind(el, c(endtime, NA, NA)) else el, n, releff, covar)
  if (own_osp) {
    cube2 <- cube_osp(if (interval) rbind(el, c(endtime, NA, NA)) else el, n)
    dimnames(cube2)[[3]] <- "OSPSnd"
    cube <- abind_cube(cube, cube2)
  }
  # coefficient order of the cube: relevent's order, kept (matched by name in the test)
  est <- if (method == "MLE") "MLE" else "BPM"
  r1 <- ref_trust(el, n, cube, interval, supp = supp, estimator = est, prior = prior, cond = cond, endtime = endtime)
  add_result(case, "trust", r1)
  if (dyad && !own_osp && is.null(supp)) {
    r2 <- ref_dyad(el, n, releff, covar, interval, cond = cond, method = method, endtime = if (interval) endtime else NULL, prior = prior)
    add_result(case, "dyad", r2)
  }
  if (interval) nwopts <- paste(nwopts, "interval endtime(", format(endtime, digits = 17), ")")
  write_case(case, n, el, nwopts, actors = actors, nets = nets, note = note)
  invisible(r1)
}
abind_cube <- function(a, b) {
  d <- dim(a); P <- d[3] + dim(b)[3]
  out <- array(0, c(d[1], d[2], P), dimnames = list(NULL, NULL, c(dimnames(a)[[3]], dimnames(b)[[3]])))
  out[, , seq_len(d[3])] <- a; out[, , d[3] + seq_len(dim(b)[3])] <- b
  out
}

# ==================================================================================================================================
# the cases
# ==================================================================================================================================
std <- c("nodsnd", "nidrec")
std4 <- c("nodsnd", "nidrec", "nidsnd", "nodrec")
actors_for <- function(n, seed, entry = NULL, exit = NULL) {
  set.seed(seed + 77)
  d <- data.frame(aid = 1:n, x1 = round(rnorm(n), 3), x2 = round(runif(n, -1, 2), 3), x3 = round(rnorm(n, 1, .5), 3))
  if (!is.null(entry)) d$entry <- entry
  if (!is.null(exit)) d$exit <- exit
  d
}
covlist <- function(d, vars) as.matrix(d[, vars, drop = FALSE])
randnet <- function(n, seed, p = 1) { set.seed(seed + 5); M <- matrix(round(rnorm(n * n), 3), n, n); diag(M) <- 0; M }

# A: the effects of 1.3.0 on new logs (the base of the comparison)
for (k in 1:3) run_case(sprintf("a%d", k), 7, 250, 100 + k, c("nodsnd", "nidrec", "nidsnd", "nodrec", "frpsndsnd", "frrecsnd", "rsndsnd", "rrecsnd"),
                        nwopts = "nodsnd nidrec nidsnd nodrec frpsndsnd frrecsnd rsndsnd rrecsnd")

# B: the waiting-time (interval) likelihood
for (k in 1:3) run_case(sprintf("b%d", k), 6, 150 + 50 * k, 200 + k, std, nwopts = "nodsnd nidrec", interval = TRUE)
for (k in 4:5) run_case(sprintf("b%d", k), 7, 250, 200 + k, c(std4, "frpsndsnd", "frrecsnd"), nwopts = "nodsnd nidrec nidsnd nodrec frpsndsnd frrecsnd", interval = TRUE)
run_case("b6", 7, 300, 206, c("nodsnd", "rsndsnd", "rrecsnd"), nwopts = "nodsnd rsndsnd rrecsnd", interval = TRUE)
a <- actors_for(7, 207)
run_case("b7", 7, 250, 207, c("covsnd", "covrec", "nodsnd"), covar = list(CovSnd = covlist(a, "x1"), CovRec = covlist(a, "x2")),
         nwopts = "nodsnd covsnd(x1) covrec(x2)", actors = a, interval = TRUE)
run_case("b8", 6, 200, 208, std, nwopts = "nodsnd nidrec condition(20)", interval = TRUE, cond = 20)
run_case("b9", 6, 200, 209, c(std, "frpsndsnd"), nwopts = "nodsnd nidrec frpsndsnd condition(30)", cond = 30)
run_case("b10", 7, 250, 210, c("ntdegsnd", "ntdegrec", "nodsnd"), nwopts = "ntdegsnd ntdegrec nodsnd", interval = TRUE)
run_case("b11", 7, 250, 211, c("nodsnd", "nidrec", "rsndsnd"), nwopts = "nodsnd nidrec rsndsnd condition(10)", interval = TRUE, cond = 10)

# C: triadic and shared-partner effects
for (k in 1:3) run_case(sprintf("c_otp%d", k), 7, 200, 300 + k, c("nodsnd", "otpsnd"), nwopts = "nodsnd otpsnd")
for (k in 1:3) run_case(sprintf("c_itp%d", k), 7, 200, 310 + k, c("nodsnd", "itpsnd"), nwopts = "nodsnd itpsnd")
for (k in 1:3) run_case(sprintf("c_isp%d", k), 7, 200, 320 + k, c("nodsnd", "ispsnd"), nwopts = "nodsnd ispsnd")
for (k in 1:3) run_case(sprintf("c_osp%d", k), 7, 200, 330 + k, c("nodsnd", "ospsnd"), nwopts = "nodsnd ospsnd", own_osp = TRUE,
                        note = "symmetric ospsnd statistic (relevent 1.2-1 has an asymmetric one); trust route only")
run_case("c_all1", 8, 300, 341, c("nodsnd", "nidrec", "otpsnd", "itpsnd", "ispsnd"), nwopts = "nodsnd nidrec otpsnd itpsnd ispsnd")
run_case("c_all2", 8, 300, 342, c("nodsnd", "nidrec", "otpsnd", "itpsnd", "ospsnd", "ispsnd"), nwopts = "nodsnd nidrec otpsnd itpsnd ospsnd ispsnd", own_osp = TRUE)
run_case("c_int1", 7, 250, 343, c("nodsnd", "otpsnd", "ispsnd"), nwopts = "nodsnd otpsnd ispsnd", interval = TRUE)
run_case("c_rec1", 7, 250, 344, c("frpsndsnd", "rsndsnd", "otpsnd", "itpsnd"), nwopts = "frpsndsnd rsndsnd otpsnd itpsnd")

# D: fixed effects
run_case("d_fesnd", 6, 250, 401, c("fesnd"), nwopts = "fesnd")
run_case("d_ferec", 6, 250, 402, c("ferec"), nwopts = "ferec")
run_case("d_feint", 6, 250, 403, c("feint"), nwopts = "feint")
run_case("d_fesr", 6, 300, 404, c("fesnd", "ferec", "nodsnd"), nwopts = "fesnd ferec nodsnd")
run_case("d_feint2", 5, 300, 405, c("feint", "frpsndsnd"), nwopts = "feint frpsndsnd")
run_case("d_feiv", 6, 250, 406, c("fesnd", "ferec", "nidrec"), nwopts = "fesnd ferec nidrec", interval = TRUE)

# E: participation shifts
for (nm in c("psabba", "psabby", "psabxa", "psabxb", "psabxy", "psabay"))
  run_case(sprintf("e_%s", nm), 7, 250, 500 + match(nm, c("psabba", "psabby", "psabxa", "psabxb", "psabxy", "psabay")), c("nodsnd", nm), nwopts = paste("nodsnd", nm))
run_case("e_all", 7, 400, 507, c("psabba", "psabby", "psabxa", "psabxb", "psabxy", "psabay"), nwopts = "psabba psabby psabxa psabxb psabxy psabay")
run_case("e_mix", 7, 300, 508, c("nodsnd", "frpsndsnd", "psabba", "psabay", "psabxy"), nwopts = "nodsnd frpsndsnd psabba psabay psabxy")
run_case("e_int", 7, 300, 509, c("nodsnd", "psabba", "psabxa"), nwopts = "nodsnd psabba psabxa", interval = TRUE)

# F: several covariates per effect, several covariate networks
a <- actors_for(7, 601)
run_case("f_cov1", 7, 250, 601, c("covsnd", "covrec", "nodsnd"), covar = list(CovSnd = covlist(a, c("x1", "x2")), CovRec = covlist(a, "x3")),
         nwopts = "nodsnd covsnd(x1 x2) covrec(x3)", actors = a)
a <- actors_for(7, 602)
run_case("f_cov2", 7, 250, 602, c("covint", "nodsnd"), covar = list(CovInt = covlist(a, c("x1", "x3"))), nwopts = "nodsnd covint(x1 x3)", actors = a, interval = TRUE)
n1 <- randnet(7, 603); n2 <- randnet(7, 604)
run_case("f_cev", 7, 250, 603, c("covevent", "nodsnd"), covar = list(CovEvent = local({ z <- array(0, c(2, 7, 7)); z[1, , ] <- n1; z[2, , ] <- n2; z })), nwopts = "nodsnd covevent(cev1 cev2)",
         nets = list(cev1 = n1, cev2 = n2))

# G: posterior-mode estimation (relevent's fit.method "BPM": independent t priors)
run_case("g1", 6, 200, 701, c("nodsnd", "nidrec", "frpsndsnd"), nwopts = "nodsnd nidrec frpsndsnd postmode", method = "BPM")
run_case("g2", 6, 200, 702, c("nodsnd", "nidrec", "rsndsnd"), nwopts = "nodsnd nidrec rsndsnd postmode", method = "BPM", interval = TRUE)
run_case("g3", 6, 200, 703, c("nodsnd", "nidrec", "frpsndsnd"), nwopts = "nodsnd nidrec frpsndsnd postmode priormean(.3) priorscale(2) priordf(3)", method = "BPM",
         prior = list(mu = .3, sigma = 2, nu = 3))
run_case("g4", 6, 200, 704, c("nodsnd", "otpsnd", "psabba"), nwopts = "nodsnd otpsnd psabba postmode priorscale(1.5)", method = "BPM", prior = list(mu = 0, sigma = 1.5, nu = 4))

# H: risk sets: dyad mask, actor windows (rem() with a support matrix is the reference; rem.dyad cannot do these)
supp_mask <- function(n, M, rows) { id <- dyadtypes(n); jj <- row(id)[id > 0][order(id[id > 0])]; kk <- col(id)[id > 0][order(id[id > 0])]
  matrix(rep(M[cbind(jj, kk)] != 0, each = rows), rows, n * (n - 1)) }
supp_win <- function(n, tt, entry, exit) { id <- dyadtypes(n); jj <- row(id)[id > 0][order(id[id > 0])]; kk <- col(id)[id > 0][order(id[id > 0])]
  out <- matrix(FALSE, length(tt), n * (n - 1))
  for (i in seq_along(tt)) { act <- (entry <= tt[i] & tt[i] <= exit); out[i, ] <- act[jj] & act[kk] }
  out }
for (k in 1:3) {
  n <- 7; el <- sim_log(n, 250, 800 + k)
  set.seed(810 + k); M <- matrix(rbinom(n * n, 1, .65), n, n); diag(M) <- 0
  for (i in 1:NROW(el)) M[el[i, 2], el[i, 3]] <- 1
  run_case(sprintf("h_mask%d", k), n, 250, 800 + k, c("nodsnd", "nidrec", "frpsndsnd"), nwopts = "nodsnd nidrec frpsndsnd riskset(risk)", el = el, nets = list(risk = M),
           supp = supp_mask(n, M, NROW(el)))
}
{
  n <- 7; el <- sim_log(n, 250, 820)
  set.seed(821); M <- matrix(rbinom(n * n, 1, .65), n, n); diag(M) <- 0
  for (i in 1:NROW(el)) M[el[i, 2], el[i, 3]] <- 1
  run_case("h_maskint", n, 250, 820, c("nodsnd", "rsndsnd"), nwopts = "nodsnd rsndsnd riskset(risk)", el = el, interval = TRUE, nets = list(risk = M),
           supp = supp_mask(n, M, NROW(el) + 1))
}
for (k in 1:3) {
  n <- 8; T <- 40
  entry <- c(-Inf, -Inf, 6, 12, -Inf, 20, -Inf, 3); exit <- c(Inf, 30, Inf, Inf, 24, Inf, 35, Inf)
  if (k == 2) { entry <- c(5, -Inf, -Inf, 10, -Inf, -Inf, 15, -Inf); exit <- c(Inf, Inf, 25, Inf, 33, Inf, Inf, 38) }
  if (k == 3) { entry <- c(-Inf, 8, -Inf, -Inf, 16, -Inf, 4, -Inf); exit <- c(Inf, Inf, 28, 36, Inf, 20, Inf, Inf) }
  el <- sim_log(n, 300, 830 + k, entry = entry, exit = exit)
  a <- actors_for(n, 830 + k, entry = ifelse(is.infinite(entry), NA, entry), exit = ifelse(is.infinite(exit), NA, exit))
  run_case(sprintf("h_win%d", k), n, 300, 830 + k, c("nodsnd", "nidrec", "rsndsnd"), nwopts = "nodsnd nidrec rsndsnd entry(entry) exit(exit)", el = el, actors = a,
           supp = supp_win(n, el[, 1], entry, exit))
  if (k == 1) {
    endt <- el[300, 1] + 3
    run_case("h_winint", n, 300, 830 + k, c("nodsnd", "frpsndsnd"), nwopts = "nodsnd frpsndsnd entry(entry) exit(exit)", el = el, actors = a, interval = TRUE, endtime = endt,
             supp = supp_win(n, c(el[, 1], endt), entry, exit))
  }
}

write.csv(do.call(rbind, results), sprintf("%s/results.csv", outdir), row.names = FALSE)
write.csv(do.call(rbind, cases), sprintf("%s/cases.csv", outdir), row.names = FALSE)
cat("cases:", length(cases), " results rows:", length(do.call(rbind, results)[[1]]), "\n")
