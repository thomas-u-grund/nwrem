# dev/rem_unit3_recency_crosscheck.R -- fits real relevent::rem.dyad()
# with the RSndSnd/RRecSnd recency-rank effects (plus NODSnd as a
# baseline, matching this project's own established pattern for a
# family that would otherwise have nothing to anchor its own scale
# against) on a fixed, exported event dataset, for direct comparison
# against nwrem's own fit on the SAME data
# (dev/rem_unit3_recency_crosscheck.do). See
# dev/rem_relevent_crosscheck.R's own header for why this compares two
# estimators on IDENTICAL data.
#
# RSndSnd/RRecSnd are relevent's own "recency" family - reciprocal RANK
# of a partner among an actor's own past contacts (most recent = rank
# 1), NOT a frequency/fraction like FrPSndSnd/FrRecSnd (unit 2, already
# crosschecked in dev/rem_units25_crosscheck.R). No `covar` argument is
# needed - unlike the CovSnd/CovRec/CovInt/CovEvent family, relevent
# builds its own internal recency-list state (`rrl`) directly from the
# edgelist.

suppressMessages(library(relevent))

set.seed(20260901)
n <- 10
nevents <- 400

edgelist <- matrix(0, nevents, 3)
for (i in seq_len(nevents)) {
  pair <- sample(seq_len(n), 2)
  edgelist[i, ] <- c(i, pair[1], pair[2])
}

fit <- rem.dyad(edgelist, n, effects = c("NODSnd", "RSndSnd", "RRecSnd"),
                 ordinal = TRUE, fit.method = "MLE", hessian = FALSE, gof = FALSE,
                 verbose = FALSE)

cat("relevent::rem.dyad coefficients (NODSnd + RSndSnd + RRecSnd):\n")
print(fit$coef)

write.csv(data.frame(sender = edgelist[, 2], receiver = edgelist[, 3], eventtime = edgelist[, 1]),
          "dev/rem_unit3_recency_events.csv", row.names = FALSE)
cat("\nEvent data written (n =", n, ", nevents =", nevents, ")\n")
