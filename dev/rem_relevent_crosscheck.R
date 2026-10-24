# dev/rem_relevent_crosscheck.R -- fits real relevent::rem.dyad() on a
# fixed, exported event dataset, for direct comparison against nwrem's
# own fit on the SAME data (dev/rem_relevent_crosscheck.do). See
# the development notes / the development notes section 3a-ii for why this
# compares two estimators against each other on IDENTICAL data (which
# must agree, both being MLE for the same likelihood/data) rather than
# comparing either estimator's point estimate against a "true" theta
# (which, per that section's own finding, is not a reliable comparison
# for this effect family at moderate sample sizes -- a real, disclosed
# statistical property, not something this script works around).
#
# relevent's OWN license (the development notes): GPL (>=2), Carter T.
# Butts. This script only CALLS the installed package as a black box to
# obtain a reference value, exactly as dev/saom_rsiena_crosscheck.R
# calls RSiena -- no relevent source is read or reproduced here.

suppressMessages(library(relevent))

set.seed(20260828)
n <- 10
nevents <- 400

# Simple synthetic generative process (independent of nwrem's own
# rem_simulate_unit1 in cscripts/test_nwrem_mata.do, deliberately -- a
# uniform-random event stream is enough here since this script's whole
# point is "do two estimators agree on the SAME fixed data", not "does
# either estimator recover a known true theta").
edgelist <- matrix(0, nevents, 3)
for (i in seq_len(nevents)) {
  pair <- sample(seq_len(n), 2)
  edgelist[i, ] <- c(i, pair[1], pair[2])
}

fit <- rem.dyad(edgelist, n, effects = c("NODSnd", "NIDRec"), ordinal = TRUE,
                 fit.method = "MLE", hessian = TRUE, gof = FALSE, verbose = FALSE)

cat("relevent::rem.dyad coefficients:\n")
print(fit$coef)
cat("\nSEs (from Hessian):\n")
print(sqrt(diag(solve(fit$hessian))))

write.csv(data.frame(sender = edgelist[, 2], receiver = edgelist[, 3], eventtime = edgelist[, 1]),
          "dev/rem_crosscheck_events.csv", row.names = FALSE)
cat("\nEvent data written to dev/rem_crosscheck_events.csv (n =", n, ", nevents =", nevents, ")\n")

# ---------------------------------------------------------------------
# CAPTURED REFERENCE VALUES -- filled in from this script's own real
# output (see dev/rem_relevent_crosscheck.do for nwrem's own fit on the
# exact same dev/rem_crosscheck_events.csv), matching
# dev/saom_rsiena_crosscheck.do's own "captured real reference values as
# constants in a comment" convention.
# ---------------------------------------------------------------------
