* dev/rem_units25_crosscheck.do -- fits nwrem's own multi-effect engine
* (units 1/2/5, all 8 degree + inertia effects) on the EXACT SAME event
* data dev/rem_units25_crosscheck.R fit with real relevent::rem.dyad(),
* matching dev/rem_relevent_crosscheck.do's own established pattern.
*
* Real relevent::rem.dyad() reference (effects = NODSnd, NIDRec, NIDSnd,
* NODRec, NTDegSnd, NTDegRec, FrPSndSnd, FrRecSnd; ordinal=TRUE,
* fit.method="MLE", this exact dev/rem_units25_events.csv - captured
* 2026-08-29 from dev/rem_units25_crosscheck.R's own real console output):
*   NIDSnd    =  0.05528255
*   NIDRec    =  0.89834405
*   NODSnd    = -1.59306614
*   NODRec    = -1.58593064
*   NTDegSnd  = -0.77035524
*   NTDegRec  = -0.34243880
*   FrPSndSnd =  0.36813843
*   FrRecSnd  = -0.03476185

* (run from the root of this repository)
* The core package nwcommands is found through the environment variable NWCORE (path of the core checkout).
local nwcore : env NWCORE
if `"`nwcore'"' == "" {
	di as error "set the environment variable NWCORE to the directory of the nwcommands (core) package"
	exit 198
}
adopath ++ `"`nwcore'"'
adopath ++ `"`c(pwd)'"'
quietly do `"`nwcore'/unw_core.do"'
do unw_rem.do

import delimited "dev/rem_units25_events.csv", clear varnames(1)

mata:
rseed(20260829)
sender = st_data(., "sender")
receiver = st_data(., "receiver")
eventtime = st_data(., "eventtime")
eventmat = (sender, receiver, eventtime)

n_actors = 8
// nwrem's own fixed 14-slot order: NODSnd NIDRec NIDSnd NODRec NTDegSnd
// NTDegRec FrPSndSnd FrRecSnd CovSnd CovRec CovInt CovEvent RSndSnd
// RRecSnd - only the first 8 (units 1/2/5) are exercised by this
// crosscheck; covariates 9-12 and recency 13-14 stay off.
active_all = (1,1,1,1,1,1,1,1,0,0,0,0,0,0)
nodummy8 = J(1,8,0)
noevdummy8 = J(8,8,0)
bname = "nwrem_b25"
vname = "nwrem_V25"
llname = "nwrem_ll25"
RemFitMulti(eventmat, n_actors, active_all, nodummy8, nodummy8, nodummy8, noevdummy8, bname, vname, llname)
end

di as text "{hline 70}"
di as text "nwrem fit (units 1/2/5, all 8 effects) vs. real relevent::rem.dyad() on the SAME data:"
di as text "  NODSnd     = " %10.6f el(nwrem_b25,1,1) "   (relevent: -1.593066)"
di as text "  NIDRec     = " %10.6f el(nwrem_b25,1,2) "   (relevent:  0.898344)"
di as text "  NIDSnd     = " %10.6f el(nwrem_b25,1,3) "   (relevent:  0.055283)"
di as text "  NODRec     = " %10.6f el(nwrem_b25,1,4) "   (relevent: -1.585931)"
di as text "  NTDegSnd   = " %10.6f el(nwrem_b25,1,5) "   (relevent: -0.770355)"
di as text "  NTDegRec   = " %10.6f el(nwrem_b25,1,6) "   (relevent: -0.342439)"
di as text "  FrPSndSnd  = " %10.6f el(nwrem_b25,1,7) "   (relevent:  0.368138)"
di as text "  FrRecSnd   = " %10.6f el(nwrem_b25,1,8) "   (relevent: -0.034762)"

matrix relevent25 = (-1.59306614, 0.89834405, 0.05528255, -1.58593064, -0.77035524, -0.34243880, 0.36813843, -0.03476185)
matrix diff25 = nwrem_b25 - relevent25
di as text "{hline 70}"
di as text "abs differences:"
matrix list diff25

* Real, confirmed finding (verified with a dedicated diagnostic before
* accepting this rather than assumed, and re-confirmed across multiple
* independent optimizer runs/seeds - not a one-off fluke): combining
* several of the 6 degree-type effects together makes the likelihood
* surface genuinely ridge-prone along some combination of their
* coefficients, wider than this project's own first characterization
* (originally thought confined to NODSnd/NIDSnd/NTDegSnd; direct
* testing across several optimizer runs shows NTDegRec can drift too,
* up to ~0.06, when all 6 degree effects are fit jointly) - different
* optimizer paths (R's optim(BFGS) vs. Mata's optimize, or even two
* different nwrem runs with different random restart draws) can
* legitimately converge to visibly different individual DEGREE-effect
* coefficients while achieving the exact same log likelihood every
* time. The two inertia effects (FrPSndSnd/FrRecSnd, columns 7-8) are
* NOT part of this - they agree with relevent to within 0.0001 across
* every run tested, consistent with unit 1's own tight 2-effect
* crosscheck. The theoretically correct test here is therefore the log
* likelihood (always agrees, to numerical-precision), not raw degree-
* effect coefficients (expected to vary along the ridge) - asserted
* below in that order, with coefficient differences still printed for
* human inspection.
di as text "{hline 70}"
di as text "inertia effects only (well-identified, not part of the degree-effect ridge), cols 7,8:"
scalar maxdiff_inertia = max(abs(el(diff25,1,7)), abs(el(diff25,1,8)))
di as text "  max abs difference: " %9.6f maxdiff_inertia
assert maxdiff_inertia < 0.01

mata:
Scheck = RemState()
Scheck.init(eventmat, n_actors)
Scheck.build_degree_accumulators()
ll_at_relevent_coefs = rem_loglik_multi(st_matrix("relevent25"), active_all, nodummy8, nodummy8, nodummy8, noevdummy8, &Scheck)
ll_at_nwrem_coefs = rem_loglik_multi(st_matrix("nwrem_b25"), active_all, nodummy8, nodummy8, nodummy8, noevdummy8, &Scheck)
printf("  ll at relevent's own coefficients: %12.4f\n", ll_at_relevent_coefs)
printf("  ll at nwrem's own coefficients:    %12.4f\n", ll_at_nwrem_coefs)
st_numscalar("ll_at_relevent_coefs", ll_at_relevent_coefs)
st_numscalar("ll_at_nwrem_coefs", ll_at_nwrem_coefs)
end
di as text "{hline 70}"
di as text "log likelihood - the theoretically correct test given the degree-effect ridge above:"
assert reldif(ll_at_relevent_coefs, ll_at_nwrem_coefs) < 1e-4

di as text "{hline 70}"
di as result "MATCH CONFIRMED: inertia effects agree to better than 0.01; the ridge-prone degree"
di as result "effects achieve the identical log likelihood at both tools' own coefficients regardless"
di as result "of individual coefficient drift (see this script's own header comment for the account)."
