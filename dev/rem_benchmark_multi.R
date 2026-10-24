# dev/rem_benchmark_multi.R -- wall-clock timing of real relevent::rem.dyad()
# fitting the FULL 8-effect degree+inertia model (not just unit 1's own
# 2-effect model, which dev/rem_benchmark.R already timed), for direct
# comparison against nwrem's own timing on the identical dataset
# (dev/rem_benchmark_multi.do). Answers "how does the multi-effect engine
# perform against R" directly, rather than assuming unit 1's own 2x
# number still holds once several correlated effects and the retry-based
# optimizer are both in play.

suppressMessages(library(relevent))

set.seed(2026828)
n <- 30
nevents <- 2000

edgelist <- matrix(0, nevents, 3)
for (i in seq_len(nevents)) {
  pair <- sample(seq_len(n), 2)
  edgelist[i, ] <- c(i, pair[1], pair[2])
}

write.csv(data.frame(sender = edgelist[, 2], receiver = edgelist[, 3], eventtime = edgelist[, 1]),
          "dev/rem_bench_multi_events.csv", row.names = FALSE)

effects8 <- c("NODSnd", "NIDRec", "NIDSnd", "NODRec", "NTDegSnd", "NTDegRec", "FrPSndSnd", "FrRecSnd")

t0 <- Sys.time()
fit <- rem.dyad(edgelist, n, effects = effects8, ordinal = TRUE,
                 fit.method = "MLE", hessian = FALSE, gof = FALSE, verbose = FALSE)
t1 <- Sys.time()

cat("relevent::rem.dyad wall-clock, 8-effect model (n =", n, ", nevents =", nevents, "):",
    as.numeric(difftime(t1, t0, units = "secs")), "seconds\n")
cat("coefficients:\n")
print(fit$coef)
