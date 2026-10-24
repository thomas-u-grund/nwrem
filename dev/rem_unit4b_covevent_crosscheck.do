* dev/rem_unit4b_covevent_crosscheck.do -- fits nwrem's own CovEvent
* (dyadic/pairwise) covariate effect through the REAL nwrem command, on
* the EXACT SAME event + n x n covariate data
* dev/rem_unit4b_covevent_crosscheck.R fit with real relevent::rem.dyad(),
* matching dev/rem_unit4_crosscheck.do's own established pattern (the
* first crosscheck to run the real nwrem command rather than calling
* RemFitMulti() directly in Mata).
*
* Real relevent::rem.dyad() reference (effects = NODSnd, CovEvent; covar
* = list(CovEvent = <10x10 matrix>); ordinal=TRUE, fit.method="MLE",
* this exact dev/rem_unit4b_covevent_events.csv +
* dev/rem_unit4b_covevent_matrix.csv - captured 2026-08-31 from
* dev/rem_unit4b_covevent_crosscheck.R's own real console output):
*   NODSnd   =  0.63970946
*   CovEvent = -0.02603451

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
import delimited "dev/rem_unit4b_covevent_events.csv", clear varnames(1)
nwset sender receiver, eventtime(eventtime) name(chatlog4b)

* dev/rem_unit4b_covevent_crosscheck.R's own CovEvent matrix is a FULLY
* populated (genuinely asymmetric - independent runif() draws per cell,
* diagonal zeroed) n x n matrix, matching relevent's own "event-wise"
* effect semantics: value(i,j) need not equal value(j,i). Reshape the
* wide CSV (row i = actor i's OUTGOING value to every j, one column per
* j - confirmed against R's own matrix(..., n, n) row-major fill) into
* a long (sender, receiver, value) edgelist and declare it `directed'
* (nwset does not auto-symmetrize an edgelist - see nwrem.sthlp's own
* note on covevent()'s symmetry requirement), excluding the self-pairs
* that are never read (excluded from REM's own risk set).
import delimited "dev/rem_unit4b_covevent_matrix.csv", clear varnames(1)
gen long i = _n
reshape long v, i(i) j(jcol)
rename v value
rename jcol j
drop if i == j
order i j value

nwset i j value, name(covevnet) edgelist directed

nwrem chatlog4b, nodsnd covevent(covevnet)

di as text "{hline 70}"
di as text "nwrem fit vs. real relevent::rem.dyad() on the SAME data:"
di as text "  NODSnd   = " %10.6f el(e(b),1,1) "   (relevent: 0.639709)"
di as text "  CovEvent = " %10.6f el(e(b),1,2) "   (relevent: -0.026035)"

matrix relevent4b = (0.63970946, -0.02603451)
matrix diff4b = e(b) - relevent4b
di as text "{hline 70}"
di as text "abs differences:"
matrix list diff4b

scalar maxdiff4b = max(abs(el(diff4b,1,1)), abs(el(diff4b,1,2)))
di as text "max abs difference across both coefficients: " %9.6f maxdiff4b
assert maxdiff4b < 0.01

di as result "MATCH CONFIRMED (agreement to better than 0.01 across NODSnd + CovEvent)"
