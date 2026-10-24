* dev/rem_unit4_crosscheck.do -- fits nwrem's own unit-4 covariate
* effects (through the REAL nwrem command, not RemFitMulti() called
* directly - the first unit crosschecked this way) on the EXACT SAME
* event + covariate data dev/rem_unit4_crosscheck.R fit with real
* relevent::rem.dyad(), matching this project's established crosscheck
* pattern.
*
* Real relevent::rem.dyad() reference (effects = NODSnd, CovSnd, CovRec,
* CovInt; covar = list(CovSnd=.., CovRec=.., CovInt=..); ordinal=TRUE,
* fit.method="MLE", this exact dev/rem_unit4_events.csv +
* dev/rem_unit4_covariates.csv - captured 2026-08-30 from
* dev/rem_unit4_crosscheck.R's own real console output):
*   NODSnd = -0.35420741
*   CovSnd = -0.02468606
*   CovRec = -0.09222275
*   CovInt = -0.14692381

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
import delimited "dev/rem_unit4_events.csv", clear varnames(1)
nwset sender receiver, eventtime(eventtime) name(chatlog4)

nwload chatlog4, xvars
* nwload's own node order is exactly the network's own actor order
* (confirmed via unw_core.do's get_nodenames()/get_eventlist() both
* resolving through the same node-index scheme) - merging the
* covariate CSV by node position (not by a merge key) matches
* dev/rem_unit4_crosscheck.R's own covsnd/covrec/covint vectors, which
* are indexed by raw actor ID 1..n in the same order the edgelist used.
import delimited "dev/rem_unit4_covariates.csv", clear varnames(1)
tempfile covdata
save `covdata'
nwload chatlog4, xvars
merge 1:1 _n using `covdata', nogenerate

nwrem chatlog4, nodsnd covsnd(covsnd) covrec(covrec) covint(covint)

di as text "{hline 70}"
di as text "nwrem fit vs. real relevent::rem.dyad() on the SAME data:"
di as text "  NODSnd = " %10.6f el(e(b),1,1) "   (relevent: -0.354207)"
di as text "  CovSnd = " %10.6f el(e(b),1,2) "   (relevent: -0.024686)"
di as text "  CovRec = " %10.6f el(e(b),1,3) "   (relevent: -0.092223)"
di as text "  CovInt = " %10.6f el(e(b),1,4) "   (relevent: -0.146924)"

matrix relevent4 = (-0.35420741, -0.02468606, -0.09222275, -0.14692381)
matrix diff4 = e(b) - relevent4
di as text "{hline 70}"
di as text "abs differences:"
matrix list diff4

scalar maxdiff4 = 0
forvalues k = 1/4 {
	scalar maxdiff4 = max(maxdiff4, abs(el(diff4,1,`k')))
}
di as text "max abs difference across all 4 coefficients: " %9.6f maxdiff4
assert maxdiff4 < 0.01

di as result "MATCH CONFIRMED (agreement to better than 0.01 across NODSnd + all 3 covariate effects)"
