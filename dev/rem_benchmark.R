# dev/rem_benchmark.R -- wall-clock timing of real relevent::rem.dyad()
# on a moderately sized event dataset, for direct comparison against
# nwrem's own timing on the identical dataset (dev/rem_benchmark.do).
# See the development notes' "benchmark speed against it" entry -- this
# is a comparison nwsaom's own development never did against RSiena (a
# disclosed gap there), done here for nwrem instead.

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
          "dev/rem_bench_events.csv", row.names = FALSE)

t0 <- Sys.time()
fit <- rem.dyad(edgelist, n, effects = c("NODSnd", "NIDRec"), ordinal = TRUE,
                 fit.method = "MLE", hessian = FALSE, gof = FALSE, verbose = FALSE)
t1 <- Sys.time()

cat("relevent::rem.dyad wall-clock (n =", n, ", nevents =", nevents, "):",
    as.numeric(difftime(t1, t0, units = "secs")), "seconds\n")
cat("coefficients:\n")
print(fit$coef)
