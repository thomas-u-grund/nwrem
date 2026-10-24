# dev/rem_units25_crosscheck.R -- fits real relevent::rem.dyad() with the
# full unit-1/2/5 effect set (NODSnd, NIDRec, NIDSnd, NODRec, NTDegSnd,
# NTDegRec, FrPSndSnd, FrRecSnd) on a fixed, exported event dataset, for
# direct comparison against nwrem's own fit on the SAME data
# (dev/rem_units25_crosscheck.do). See dev/rem_relevent_crosscheck.R's own
# header for why this compares two estimators on IDENTICAL data rather than
# each against a "true" theta.

suppressMessages(library(relevent))

set.seed(20260829)
n <- 8
nevents <- 500

edgelist <- matrix(0, nevents, 3)
for (i in seq_len(nevents)) {
  pair <- sample(seq_len(n), 2)
  edgelist[i, ] <- c(i, pair[1], pair[2])
}

effects <- c("NODSnd", "NIDRec", "NIDSnd", "NODRec", "NTDegSnd", "NTDegRec",
             "FrPSndSnd", "FrRecSnd")
fit <- rem.dyad(edgelist, n, effects = effects, ordinal = TRUE,
                 fit.method = "MLE", hessian = FALSE, gof = FALSE, verbose = FALSE)

cat("relevent::rem.dyad coefficients (units 1/2/5, all 8 effects):\n")
print(fit$coef)

write.csv(data.frame(sender = edgelist[, 2], receiver = edgelist[, 3], eventtime = edgelist[, 1]),
          "dev/rem_units25_events.csv", row.names = FALSE)
cat("\nEvent data written to dev/rem_units25_events.csv (n =", n, ", nevents =", nevents, ")\n")
