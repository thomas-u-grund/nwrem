cscript

* xt_rem_options.do -- DRAFT, not yet run.
* Option combinations: all 14 effects at once (fixed column order, collinear degree shares reported in
* e(unidentified)), option order irrelevant, the same covariate in covsnd/covrec/covint (covint = covsnd + covrec is
* exactly collinear), statistics that are constant over the risk set (not identified; ll equals the null ll
* -N ln(n(n-1)), derived by hand), seed() boundary values.
* Expected runtime: about 40 seconds (Stata 17 BE).
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

nwclear
xt_w40
nwset sender receiver, eventtime(t) directed name(w40)
matrix XCE = (0,1,0,2 \ 1,0,3,0 \ 0,3,0,1 \ 2,0,1,0)
nwset, mat(XCE) directed name(ce) nooutput
matrix XONE = (0,1,1,1 \ 1,0,1,1 \ 1,1,0,1 \ 1,1,1,0)
nwset, mat(XONE) directed name(ones) nooutput
nwload w40, xvars
assert _N == 4
gen double x = cond(_n==1, 0.5, cond(_n==2, -1, cond(_n==3, 2, 0)))
gen double y = mod(_n, 2)
gen double z = _n^2
gen double k = 3

* ---------------------------------------------------------------------------------------------------------------------
di as text "{hline 60}"
di as text "Block A: all 14 effects in one call"
di as text "{hline 60}"
nwrem w40, rrecsnd rsndsnd covevent(ce) covint(z) covrec(y) covsnd(x) frrecsnd frpsndsnd ntdegrec ntdegsnd nodrec nidsnd nidrec nodsnd seed(1)
assert colsof(e(b)) == 14
assert "`: colnames e(b)'" == "nodsnd nidrec nidsnd nodrec ntdegsnd ntdegrec frpsndsnd frrecsnd covsnd_x covrec_y covint_z covevent_ce rsndsnd rrecsnd"
* the six degree shares span a space of dimension 4 (ntdegsnd = (nodsnd + nidsnd)/2, ntdegrec = (nidrec + nodrec)/2):
* at least two of them have no usable standard error
local nu : word count `e(unidentified)'
assert `nu' >= 2
local deg "nodsnd nidrec nidsnd nodrec ntdegsnd ntdegrec"
local nd 0
foreach u of local deg {
	if strpos(" `e(unidentified)' ", " `u' ") local ++nd
}
assert `nd' >= 2
di as text "  PASS: 14 effects, fixed order, unidentified: `e(unidentified)'"

* ---------------------------------------------------------------------------------------------------------------------
di as text "{hline 60}"
di as text "Block B: the order of the options does not matter"
di as text "{hline 60}"
nwrem w40, nodsnd rrecsnd covsnd(x) seed(3)
matrix XB = e(b)
scalar XLL = e(ll)
nwrem w40, covsnd(x) rrecsnd nodsnd seed(3)
assert "`: colnames e(b)'" == "nodsnd covsnd_x rrecsnd"
assert mreldif(e(b), XB) == 0
assert e(ll) == scalar(XLL)
di as text "  PASS: option order"

* ---------------------------------------------------------------------------------------------------------------------
di as text "{hline 60}"
di as text "Block C: one variable in covsnd, covrec and covint (covint = covsnd + covrec exactly)"
di as text "{hline 60}"
nwrem w40, covsnd(x) covrec(x) covint(x) seed(1)
assert "`: colnames e(b)'" == "covsnd_x covrec_x covint_x"
assert "`e(unidentified)'" != ""
di as text "  PASS: collinear covariate trio reported: `e(unidentified)'"
* two different variables: identified
nwrem w40, covsnd(x) covrec(y) seed(1)
assert "`e(unidentified)'" == ""
di as text "  PASS: covsnd(x) covrec(y) identified"

* ---------------------------------------------------------------------------------------------------------------------
di as text "{hline 60}"
di as text "Block D: statistics constant over the risk set are not identified (ll = -40 ln 12 = -99.3962659915)"
di as text "{hline 60}"
* covsnd(k) with k = 3 for every actor and covevent(ones) are constant at every event: the likelihood does not depend
* on the coefficient. Expected: either a clean refusal or a fit with ll = null ll and the effect in e(unidentified).
foreach spec in "covsnd(k)" "covevent(ones)" "covrec(k)" "covint(k)" {
	capture noisily nwrem w40, `spec' seed(1)
	local rc = _rc
	if `rc' == 0 {
		assert reldif(e(ll), -99.3962659915) < 1e-10
		assert "`e(unidentified)'" != ""
		di as text "  PASS: `spec' fitted, ll = null ll, unidentified: `e(unidentified)'"
	}
	else {
		assert `rc' < 3000 | `rc' > 3999
		di as text "  PASS: `spec' refused with r(`rc') (no raw Mata error)"
	}
}

* ---------------------------------------------------------------------------------------------------------------------
di as text "{hline 60}"
di as text "Block E: seed() boundary values"
di as text "{hline 60}"
nwrem w40, nodsnd nidrec seed(0)
matrix XS0 = e(b)
nwrem w40, nodsnd nidrec seed(0)
assert mreldif(e(b), XS0) == 0
nwrem w40, nodsnd nidrec seed(2147483647)
assert abs(_b[nodsnd] - 0.7303189) < 2e-3 * (1 + 0.7303189)
di as text "  PASS: seed(0) reproducible, seed(2147483647) accepted"

* ---------------------------------------------------------------------------------------------------------------------
di as text "{hline 60}"
di as text "Block F: covariates with extreme scale (1e6) and negative values"
di as text "{hline 60}"
* covsnd(x01 * c) has coefficient theta / c: scaling the covariate by c = 1000 divides the coefficient by 1000
* (closed form of xt_rem_closedform.do: theta = -0.302280871873 for x01 = (0,0,1,1))
nwload w40, xvars
gen double x01 = (_n >= 3)
gen double x01k = 1000 * x01
gen double x01n = -x01
nwrem w40, covsnd(x01k) seed(1)
assert abs(_b[covsnd_x01k] * 1000 - (-0.302280871873)) < 1e-3 * 1.302280871873
nwrem w40, covsnd(x01n) seed(1)
assert abs(_b[covsnd_x01n] - 0.302280871873) < 1e-4
assert reldif(e(ll), -98.9445631184) < 1e-8
di as text "  PASS: covariate rescaling and sign change"

di "ALL PASS"
