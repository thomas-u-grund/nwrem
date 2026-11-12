# Extended nwrem tests (xt_*.do): notes

DRAFTS, NOT YET RUN. Written 2026-11-12 against nwrem 1.0.13 (develop) and the core at the same date, without starting
Stata. Expect a first run to show typing errors in the test code itself. Fix those before you read any failure as a
finding.

Run from the repository root with the usual runner (it sets the adopath, core, and plugin folder). The files contain
no sysdir/adopath lines. Each file ends with `di "ALL PASS"`. `xt_rem_suspected.do` instead ends with `exit 9` and
lists the failing checks when any suspected problem is confirmed.

## Files

| File | Runtime (Stata 17 BE, estimate) | Coverage |
|---|---|---|
| xt_rem_edges.do | ~30 s | Unsorted and reversed rows; monotone time transforms (shift, x1000, cube, exp, -1/t, +1e9); tied times (ceil(t/4), all t = 0, tie order = listed order); string, mixed, offset, non-consecutive and permuted ids; a valued event network; duplicate rows. Reference: relevent on W40. |
| xt_rem_closedform.do | ~20 s | Hand scores at theta = 0 for all 14 statistics on a 3-event toy (checked by R brute force), ll = -3 ln 6; binomial closed forms for covsnd, covrec, covevent (theta, ll, se); relevent references for FrPSndSnd+FrRecSnd, RSndSnd+RRecSnd, CovSnd, NODRec+CovInt, CovEvent; smallest data sets (2 events/3 actors, 3 events/2 actors, 60 actors/30 events). |
| xt_rem_clogit.do | ~60 s | Own Mata builder for the 14 statistics (written from the help file definitions) with clogit on n = 5, N = 150 (rseed 20261112); 7 model specs; tied times; actor-label permutation with permuted covariates and covevent matrix. |
| xt_rem_estimation.do | ~30 s | Seed reproducibility; seeds 1-5 reach the relevent optimum; every documented e() entry; `nwrem version` r() (reference "relevent 1.2-1", license "GPL-3", plugin "none (Mata only)"); postestimation (ereturn display, estat vce, lincom, test, nlcom, estimates store/replay/restore) on several result shapes; data, event list and name space unchanged. |
| xt_rem_options.do | ~40 s | All 14 effects at once (column order, degree shares in e(unidentified)); option order; one variable in covsnd/covrec/covint (collinear); constant statistics (ll = -40 ln 12 = -99.3962659915); seed(0), seed(2147483647); covariate x1000 and sign flip. |
| xt_rem_errors.do | ~15 s | Exact r() for every error exit (198, 482, 109, 111, 103, 416, 2001, 3498, 6088). After each error, e(b), e(ll), e(cmd) and the data are unchanged. |
| xt_rem_suspected.do | ~20 s | S1-S9, the suspected bugs below. |

Total: about 3.5 minutes.

## W40 reference sequence

These are 40 events at t = 1..40 on 4 actors (sender receiver), as in every xt file (`XT_W40`):
`1 3;1 3;1 3;1 3;2 1;4 2;2 4;2 4;1 3;4 3;3 1;4 2;3 2;4 2;1 3;1 3;2 4;4 2;2 4;2 4;3 1;3 1;1 2;1 3;3 4;4 1;1 3;3 1;1 2;1 3;4 2;2 1;4 2;4 2;3 2;2 3;1 3;2 4;4 2;2 3`

## R code for the references (relevent 1.2-1, R in /usr/local/bin/Rscript)

```r
suppressMessages(library(relevent))
ev <- read.table(text=gsub(";", "\n", "1 3 1;1 3 2;1 3 3;1 3 4;2 1 5;4 2 6;2 4 7;2 4 8;1 3 9;4 3 10;3 1 11;4 2 12;3 2 13;4 2 14;1 3 15;1 3 16;2 4 17;4 2 18;2 4 19;2 4 20;3 1 21;3 1 22;1 2 23;1 3 24;3 4 25;4 1 26;1 3 27;3 1 28;1 2 29;1 3 30;4 2 31;2 1 32;4 2 33;4 2 34;3 2 35;2 3 36;1 3 37;2 4 38;4 2 39;2 3 40"))
el <- cbind(ev[,3], ev[,1], ev[,2]); n <- 4
f <- function(eff, covar=NULL) { m <- rem.dyad(el, n, effects=eff, covar=covar, ordinal=TRUE, hessian=TRUE, gof=FALSE, verbose=FALSE)
  print(signif(m$coef, 10)); cat("se ", signif(sqrt(diag(m$cov)), 8), "\n"); cat("ll ", sprintf("%.8f", -m$residual.deviance/2), "\n") }
f(c("NODSnd","NIDRec"))        # 0.7303189 0.9508733 | se .8178162 .7872408 | ll -98.11630985
f(c("FrPSndSnd","FrRecSnd"))   # 1.1904497 0.9799925 | se .5667823 .5263519 | ll -90.69633794
f(c("RSndSnd","RRecSnd"))      # 0.8723779 0.7414476 | se .42498 .4206878  | ll -94.45007925
x <- c(0.5, -1, 2, 0)
f(c("CovSnd"), list(CovSnd=x))                 # -0.09789638 | se .1490603 | ll -99.17756849
f(c("CovInt","NODRec"), list(CovInt=x))        # NODRec -0.647783046 (1.013836), CovInt -0.008277574 (.1272633), ll -99.17186102
CE <- matrix(c(0,1,0,2, 1,0,3,0, 0,3,0,1, 2,0,1,0), 4, 4, byrow=TRUE)
f(c("CovEvent"), list(CovEvent=CE))            # -0.7880309 | se .2123185 | ll -90.14109494
```

The closed forms are binomial MLEs of a two-group statistic. With N events, M ordered pairs per event, k pairs with
statistic 1, a events on such pairs and b = N - a: exp(theta) = a(M-k)/(bk),
ll = a ln(a/(Nk)) + b ln(b/(N(M-k))), se = sqrt(N/(ab)). Hand scores of xt_rem_closedform.do were checked by brute
force in R (scratch scripts, not part of the repo).

### TODO-R (assertions not written)

Run these, then add `xt_rref` lines to Block C of xt_rem_closedform.do (marked `* TODO-R`):

```r
f(c("NIDSnd"))
f(c("NTDEGSnd"))
f(c("NTDEGRec"))
f(c("NIDSnd","NODRec"))
```

## Suspected bugs and code/help mismatches (from reading the code; checked in xt_rem_suspected.do)

1. **S1/S2 (core): large numeric actor ids get actor index 0.** nwset.ado:285-286 (two-mode 132-133) labels events
   `"n" + strofreal(id)`, which uses the %9.0g format. nwfromedge.ado:218, 246 build node names from a float
   dictionary with %18.0g. Ids above 16,777,216 (not exact in float) or of 1e9 and more (%9.0g prints 1.000e+09)
   produce labels that do not match. The events then get index 0, and RemState fails with a raw Mata error or a
   wrong fit. This affects nwdynam as well.
2. **S3: a missing sender or receiver** gives the label "n.", which is not found, so the index is 0 and the result is a
   raw Mata r(3301) inside RemState. Wanted: a refusal or the row dropped.
3. **S4: a missing event time is accepted.** The event is sorted last and silently used as the final event.
4. **S5 (DESIGN): an undirected event network is fitted as directed.** nwrem.ado never reads `directed`. nwdynam
   refuses the same input for choice/rate.
5. **S6: covsnd()/covrec()/covint() values are never checked for missing.** covevent() is checked (r(416),
   nwrem.ado:115-118). Mata sums skip missing cells.
6. **S7: long covariate names.** Column names `covsnd_<32-char var>` have 39 characters. Check that the names stay
   distinct and valid.
7. **S8: seed(-1) is the internal "not given" sentinel** (nwrem.ado:15, 131). A user who passes seed(-1) gets an
   unseeded run.
8. **S9 (DESIGN): covariates are read by row position** even when `_nwnode` is in the data. A re-sorted xvars
   dataset silently misaligns them.
9. **Stale comment:** nwrem.ado:24-35 says two-mode event networks are unreachable. `nwset ..., twomode eventtime()`
   reaches the guard (tested in xt_rem_errors.do as r(198) with `tm`). The matching comment in
   cscripts/test_nwrem_ado.do is stale too.
10. **Core `_nwsyntax`:** two network names give r(482) "not found" instead of a "one network only" message.
    nwunab is rclass and clobbers r().
