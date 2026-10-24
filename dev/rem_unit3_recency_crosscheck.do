* dev/rem_unit3_recency_crosscheck.do -- fits nwrem's own recency-rank
* effects (RSndSnd/RRecSnd) through the REAL nwrem command, on the
* EXACT SAME event data dev/rem_unit3_recency_crosscheck.R fit with
* real relevent::rem.dyad(), matching dev/rem_unit4_crosscheck.do's
* own established pattern (nwrem, not RemFitMulti() called directly).
*
* Real relevent::rem.dyad() reference (effects = NODSnd, RSndSnd,
* RRecSnd; ordinal=TRUE, fit.method="MLE", this exact
* dev/rem_unit3_recency_events.csv - captured 2026-09-01 from
* dev/rem_unit3_recency_crosscheck.R's own real console output; R's own
* coef vector comes back re-ordered by name, not effects= order, so
* these are matched by NAME not position):
*   NODSnd  = -0.07381101
*   RRecSnd =  0.08866211
*   RSndSnd = -0.13629907

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
* (not needed here: unw_ergm.do belongs to another package)
do unw_rem.do

nwclear
import delimited "dev/rem_unit3_recency_events.csv", clear varnames(1)
nwset sender receiver, eventtime(eventtime) name(chatlog3)

nwrem chatlog3, nodsnd rsndsnd rrecsnd

di as text "{hline 70}"
di as text "nwrem fit vs. real relevent::rem.dyad() on the SAME data:"
di as text "  NODSnd  = " %10.6f el(e(b),1,1) "   (relevent: -0.073811)"
di as text "  RSndSnd = " %10.6f el(e(b),1,2) "   (relevent: -0.136299)"
di as text "  RRecSnd = " %10.6f el(e(b),1,3) "   (relevent:  0.088662)"

matrix relevent3 = (-0.07381101, -0.13629907, 0.08866211)
matrix diff3 = e(b) - relevent3
di as text "{hline 70}"
di as text "abs differences:"
matrix list diff3

scalar maxdiff3 = 0
forvalues k = 1/3 {
	scalar maxdiff3 = max(maxdiff3, abs(el(diff3,1,`k')))
}
di as text "max abs difference across all 3 coefficients: " %9.6f maxdiff3
assert maxdiff3 < 0.01

di as result "MATCH CONFIRMED (agreement to better than 0.01 across NODSnd + RSndSnd + RRecSnd)"
