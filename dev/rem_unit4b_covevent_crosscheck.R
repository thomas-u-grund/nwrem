# dev/rem_unit4b_covevent_crosscheck.R -- fits real relevent::rem.dyad()
# with a CovEvent (dyadic/pairwise) covariate effect (plus NODSnd as a
# baseline, matching dev/rem_unit4_crosscheck.R's own reasoning: without
# it, a model of CovEvent alone has nothing to anchor its own scale
# against) on a fixed, exported event dataset, for direct comparison
# against nwrem's own fit on the SAME data
# (dev/rem_unit4b_covevent_crosscheck.do). See
# dev/rem_relevent_crosscheck.R's own header for why this compares two
# estimators on IDENTICAL data.
#
# CovEvent's own input shape (single, time-invariant covariate: an n x n
# matrix, confirmed via ?rem.dyad's own documentation, not assumed) is
# genuinely different from CovSnd/CovRec/CovInt's per-actor vectors -
# this is exactly the "different data shape" reason CovEvent was
# deferred out of dev/rem_unit4_crosscheck.R's own scope.

suppressMessages(library(relevent))

set.seed(20260831)
n <- 10
nevents <- 400

edgelist <- matrix(0, nevents, 3)
for (i in seq_len(nevents)) {
  pair <- sample(seq_len(n), 2)
  edgelist[i, ] <- c(i, pair[1], pair[2])
}

covevent <- matrix(runif(n * n, 0, 5), n, n)
diag(covevent) <- 0   # self-pairs are never in the risk set; value is never read

fit <- rem.dyad(edgelist, n, effects = c("NODSnd", "CovEvent"),
                 covar = list(CovEvent = covevent),
                 ordinal = TRUE, fit.method = "MLE", hessian = FALSE, gof = FALSE,
                 verbose = FALSE)

cat("relevent::rem.dyad coefficients (NODSnd + CovEvent):\n")
print(fit$coef)

write.csv(data.frame(sender = edgelist[, 2], receiver = edgelist[, 3], eventtime = edgelist[, 1]),
          "dev/rem_unit4b_covevent_events.csv", row.names = FALSE)
write.csv(covevent, "dev/rem_unit4b_covevent_matrix.csv", row.names = FALSE)
cat("\nEvent + CovEvent matrix data written (n =", n, ", nevents =", nevents, ")\n")
