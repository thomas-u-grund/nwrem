# dev/rem_unit4_crosscheck.R -- fits real relevent::rem.dyad() with
# CovSnd/CovRec/CovInt static covariate effects (plus NODSnd as a
# baseline, to avoid the whole model being just 3 correlated covariate
# effects with nothing to anchor them) on a fixed, exported event
# dataset, for direct comparison against nwrem's own fit on the SAME
# data (dev/rem_unit4_crosscheck.do). See dev/rem_relevent_crosscheck.R's
# own header for why this compares two estimators on IDENTICAL data.

suppressMessages(library(relevent))

set.seed(20260830)
n <- 10
nevents <- 400

edgelist <- matrix(0, nevents, 3)
for (i in seq_len(nevents)) {
  pair <- sample(seq_len(n), 2)
  edgelist[i, ] <- c(i, pair[1], pair[2])
}

covsnd <- c(1, 3, 2, 5, 1, 4, 2, 3, 5, 1)
covrec <- c(2, 1, 4, 1, 3, 2, 5, 1, 2, 4)
covint <- c(0, 1, 0, 1, 1, 0, 0, 1, 0, 1)

fit <- rem.dyad(edgelist, n, effects = c("NODSnd", "CovSnd", "CovRec", "CovInt"),
                 covar = list(CovSnd = covsnd, CovRec = covrec, CovInt = covint),
                 ordinal = TRUE, fit.method = "MLE", hessian = FALSE, gof = FALSE,
                 verbose = FALSE)

cat("relevent::rem.dyad coefficients (NODSnd + CovSnd/CovRec/CovInt):\n")
print(fit$coef)

write.csv(data.frame(sender = edgelist[, 2], receiver = edgelist[, 3], eventtime = edgelist[, 1]),
          "dev/rem_unit4_events.csv", row.names = FALSE)
write.csv(data.frame(node = seq_len(n), covsnd = covsnd, covrec = covrec, covint = covint),
          "dev/rem_unit4_covariates.csv", row.names = FALSE)
cat("\nEvent + covariate data written (n =", n, ", nevents =", nevents, ")\n")
