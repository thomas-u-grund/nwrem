cscript

* xt_rem_estimation.do -- DRAFT, not yet run.
* Estimation determinism (seed), the documented stored results (help file "Stored results"), nwrem version, and
* Stata's generic postestimation commands on every result shape (1 effect = 1 x 1 e(V), several effects, covariate
* and covevent labels). Identities asserted: lincom of one coefficient returns _b and _se; test of one coefficient
* returns chi2 = (b/se)^2; e(V) symmetric with the same row and column names as e(b).
* Also: nwrem leaves the data in memory, the network and helper scalars/matrices as they were.
* Expected runtime: about 30 seconds (Stata 17 BE).
* Run from the repository root; the test runner sets the adopath. No sysdir/adopath here.

capture program drop nwinstall
local nwcore : env NWCORE
if `"`nwcore'"' != "" quietly do `"`nwcore'/unw_core.do"'
quietly do unw_rem.do

mata: XT_W40 = (1,3 \ 1,3 \ 1,3 \ 1,3 \ 2,1 \ 4,2 \ 2,4 \ 2,4 \ 1,3 \ 4,3 \ 3,1 \ 4,2 \ 3,2 \ 4,2 \ 1,3 \ 1,3 \ 2,4 \ 4,2 \ 2,4 \ 2,4 \ 3,1 \ 3,1 \ 1,2 \ 1,3 \ 3,4 \ 4,1 \ 1,3 \ 3,1 \ 1,2 \ 1,3 \ 4,2 \ 2,1 \ 4,2 \ 4,2 \ 3,2 \ 2,3 \ 1,3 \ 2,4 \ 4,2 \ 2,3)

capture program drop xt_w40
program xt_w40
	clear
	quietly set obs 40
	quietly gen long sender = .
	quietly gen long receiver = .
	mata: st_store(., ("sender", "receiver"), XT_W40)
	quietly gen double t = _n
end

capture program drop xt_post
program xt_post
	* generic postestimation on the result in memory; every command must run, identities checked for coefficient 1
	local names : colnames e(b)
	local k : word count `names'
	local c1 : word 1 of `names'
	assert rowsof(e(V)) == `k' & colsof(e(V)) == `k'
	assert "`: rownames e(V)'" == "`names'"
	assert "`: colnames e(V)'" == "`names'"
	tempname V Vt
	matrix `V' = e(V)
	matrix `Vt' = `V''
	assert mreldif(`V', `Vt') < 1e-10
	ereturn display
	estat vce
	lincom `c1'
	assert reldif(r(estimate), _b[`c1']) < 1e-12
	assert reldif(r(se), _se[`c1']) < 1e-12
	test `c1'
	assert reldif(r(chi2), (_b[`c1'] / _se[`c1'])^2) < 1e-10
	nlcom exp(_b[`c1'])
	if `k' >= 2 {
		local c2 : word 2 of `names'
		test `c1' `c2'
		assert r(df) == 2
		lincom `c1' - `c2'
	}
	estimates store xt_post
	// POLICY N1: nwrem has no replay (typing nwrem alone asks for an effect, r(198)), so estimates replay fails.
	// Not promised by the help file; none of the four model commands replays. Recorded, not counted.
	capture noisily estimates replay xt_post
	if _rc di as text "  NOTE N1: estimates replay gives r(`=_rc') (no replay in nwrem)"
	tempname b
	matrix `b' = e(b)
	ereturn clear
	estimates restore xt_post
	assert mreldif(e(b), `b') == 0
	assert "`e(cmd)'" == "nwrem"
	estimates drop xt_post
	di as text "  PASS: postestimation on (`names')"
end

* ---------------------------------------------------------------------------------------------------------------------
di as text "{hline 60}"
di as text "Block A: seed() makes the fit reproducible; set seed + no seed() is the same"
di as text "{hline 60}"
nwclear
xt_w40
nwset sender receiver, eventtime(t) directed name(w40)
nwload w40, xvars
gen double x = _n
nwrem w40, nodsnd nidrec frpsndsnd covsnd(x) seed(7)
matrix XA = e(b)
matrix XV = e(V)
scalar XL = e(ll)
nwrem w40, nodsnd nidrec frpsndsnd covsnd(x) seed(7)
assert mreldif(e(b), XA) == 0
assert mreldif(e(V), XV) == 0
assert e(ll) == scalar(XL)
set seed 7
nwrem w40, nodsnd nidrec frpsndsnd covsnd(x)
assert mreldif(e(b), XA) == 0
di as text "  PASS: identical results with the same seed"
* different seeds reach the same maximum (W40 nodsnd nidrec; relevent: 0.7303189, 0.9508733, ll -98.11630985)
forvalues s = 1/5 {
	quietly nwrem w40, nodsnd nidrec seed(`s')
	assert abs(_b[nodsnd] - 0.7303189) < 2e-3 * (1 + 0.7303189)
	assert abs(_b[nidrec] - 0.9508733) < 2e-3 * (1 + 0.9508733)
	assert reldif(e(ll), -98.11630985) < 1e-6
}
di as text "  PASS: seeds 1-5 reach the relevent maximum"

* ---------------------------------------------------------------------------------------------------------------------
di as text "{hline 60}"
di as text "Block B: documented stored results"
di as text "{hline 60}"
nwrem w40, nodsnd nidrec seed(1)
assert "`e(cmd)'" == "nwrem"
assert "`e(title)'" == "Relational event model (ordinal partial likelihood, MLE)"
assert "`e(depvar)'" == "w40"
assert "`e(unidentified)'" == ""
assert "`e(version)'" != ""
assert e(N) == 40
assert e(nodes) == 4
assert !missing(e(ll))
assert "`: colnames e(b)'" == "nodsnd nidrec"
local ev "`e(version)'"
nwrem version
assert "`r(version)'" == "`ev'"
assert "`r(reference)'" == "relevent 1.2-1"
assert "`r(license)'" == "GPL-3"
assert "`r(plugin)'" == "none (Mata only)"
* nwrem version is r-class and must leave e() alone
assert "`e(cmd)'" == "nwrem"
assert e(N) == 40
di as text "  PASS: e() as documented; nwrem version = e(version) and leaves e() intact"
* the current network is used when no netname is given
nwcurrent w40
nwrem, nodsnd nidrec seed(1)
assert "`e(depvar)'" == "w40"
matrix XC = e(b)
nwrem w40, nodsnd nidrec seed(1)
assert mreldif(e(b), XC) == 0
di as text "  PASS: nwrem without netname fits the current network"

* ---------------------------------------------------------------------------------------------------------------------
di as text "{hline 60}"
di as text "Block C: postestimation on every result shape"
di as text "{hline 60}"
nwrem w40, nidrec seed(1)
xt_post
nwrem w40, frpsndsnd frrecsnd rsndsnd seed(1)
xt_post
nwload w40, xvars
capture drop x
capture drop x2
gen double x = _n
gen double x2 = mod(_n, 2)
nwrem w40, covsnd(x) covint(x2) seed(1)
assert "`: colnames e(b)'" == "covsnd_x covint_x2"
xt_post
matrix XNX = (0,1,0,0 \ 0,0,1,0 \ 0,0,0,1 \ 1,0,0,0)
nwset, mat(XNX) directed name(nxt) nooutput
nwrem w40, covevent(nxt) seed(1)
xt_post

* ---------------------------------------------------------------------------------------------------------------------
di as text "{hline 60}"
di as text "Block D: the data in memory, the network and the helper objects are left as they were"
di as text "{hline 60}"
nwload w40, xvars
capture drop x
capture drop x2
gen double x = _n
tempfile pre
quietly save `pre'
nwrem w40, nodsnd covsnd(x) seed(1)
cf _all using `pre'
_nwsyntax w40, max(1)
mata: XEV0 = *(`netobj'->get_eventlist())
nwrem w40, nodsnd nidrec rsndsnd seed(1)
_nwsyntax w40, max(1)
mata: st_numscalar("XSAME", XEV0 == *(`netobj'->get_eventlist()))
assert scalar(XSAME) == 1
foreach o in __nwrem_b __nwrem_V {
	capture confirm matrix `o'
	assert _rc != 0
}
foreach o in __nwrem_ll __nwrem_nevents {
	capture confirm scalar `o'
	assert _rc != 0
}
di as text "  PASS: data, event list and helper objects unchanged"

di "ALL PASS"
