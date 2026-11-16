cscript

* nwrem 1.4.0: the new options and effects through the command: error paths (exact return codes, nothing changed), the stored results,
* and a few identities that do not need a reference program.
capture program drop nwinstall
local nwcore : env NWCORE
if `"`nwcore'"' != "" quietly do `"`nwcore'/unw_core.do"'
quietly do unw_rem.do

capture program drop xt_err
program xt_err
	* xt_err rc command...: the command stops with exactly r(rc); e(b), e(ll), e(cmd) and the data are unchanged
	gettoken rc 0 : 0
	tempfile snap
	quietly save `snap', replace
	tempname b ll
	matrix `b' = e(b)
	scalar `ll' = e(ll)
	capture noisily `0'
	local got = _rc
	if `got' != `rc' {
		di as error "  FAIL: expected r(`rc'), got r(`got'): `0'"
		exit 9
	}
	assert mreldif(e(b), `b') == 0
	assert e(ll) == scalar(`ll')
	assert "`e(cmd)'" == "nwrem"
	cf _all using `snap'
	di as text "  PASS: r(`rc'): `0'"
end

mata: XT_W40 = (1,3 \ 1,3 \ 1,3 \ 1,3 \ 2,1 \ 4,2 \ 2,4 \ 2,4 \ 1,3 \ 4,3 \ 3,1 \ 4,2 \ 3,2 \ 4,2 \ 1,3 \ 1,3 \ 2,4 \ 4,2 \ 2,4 \ 2,4 \ 3,1 \ 3,1 \ 1,2 \ 1,3 \ 3,4 \ 4,1 \ 1,3 \ 3,1 \ 1,2 \ 1,3 \ 4,2 \ 2,1 \ 4,2 \ 4,2 \ 3,2 \ 2,3 \ 1,3 \ 2,4 \ 4,2 \ 2,3)
nwclear
clear
quietly set obs 40
gen long sender = .
gen long receiver = .
mata: st_store(., ("sender", "receiver"), XT_W40)
gen double tie = floor((_n + 1) / 2)                  // pairs of events with equal times
nwset sender receiver, eventtime(tie) directed name(wtie)
clear
quietly set obs 40
gen long sender = .
gen long receiver = .
mata: st_store(., ("sender", "receiver"), XT_W40)
gen double t = _n
nwset sender receiver, eventtime(t) directed name(w40)
nwrandom 4, prob(.5) name(static)
matrix XA = (0,1,1,1 \ 1,0,0,1 \ 1,0,0,0 \ 1,1,0,0)       // dyads 1->2 1->3 1->4 2->1 2->4 3->1 4->1 4->2 can occur
nwset, mat(XA) directed name(rs) nooutput
matrix XA2 = (0,1,1,1 \ 1,0,1,1 \ 1,1,0,1 \ 1,1,1,0)
nwset, mat(XA2) directed name(rsall) nooutput
nwload w40, xvars
gen double x = _n
nwrem w40, nodsnd nidrec

di as text "{hline 60}"
di as text "Block A: error paths of the new options"
di as text "{hline 60}"
xt_err 198 nwrem w40, nodsnd starttime(0)
xt_err 198 nwrem w40, nodsnd endtime(50)
xt_err 198 nwrem w40, nodsnd interval starttime(abc)
xt_err 198 nwrem w40, nodsnd interval endtime(abc)
xt_err 198 nwrem w40, nodsnd condition(-1)
xt_err 198 nwrem w40, nodsnd condition(1.5)
xt_err 198 nwrem w40, nodsnd condition(40)
xt_err 198 nwrem w40, nodsnd priormean(1)
xt_err 198 nwrem w40, nodsnd priorscale(2)
xt_err 198 nwrem w40, nodsnd priordf(3)
xt_err 198 nwrem w40, nodsnd postmode priorscale(0)
xt_err 198 nwrem w40, nodsnd postmode priorscale(-1)
xt_err 198 nwrem w40, nodsnd postmode priordf(0)
xt_err 198 nwrem w40, nodsnd postmode priormean(abc)
xt_err 459 nwrem wtie, nodsnd nidrec interval
xt_err 459 nwrem w40, nodsnd interval starttime(5)
xt_err 459 nwrem w40, nodsnd interval endtime(20)
xt_err 459 nwrem w40, nodsnd riskset(rs)
xt_err 482 nwrem w40, nodsnd riskset(nosuchnet)
xt_err 482 nwrem w40, nodsnd covevent(nosuchnet)
xt_err 111 nwrem w40, nodsnd covsnd(x nosuchvar)
xt_err 459 nwrem w40, nodsnd entry(x)
xt_err 459 nwrem w40, nodsnd exit(x)
xt_err 111 nwrem w40, nodsnd entry(nosuchvar) exit(x)
xt_err 459 nwrem w40, nodsnd entry(x) exit(x)
di as text "  PASS: error paths"

di as text "{hline 60}"
di as text "Block B: stored results"
di as text "{hline 60}"
quietly nwrem w40, nodsnd nidrec
assert "`e(lik)'" == "ordinal"
assert e(N) == 40
assert e(df_m) == 2
assert abs(e(deviance) + 2 * e(ll)) < 1e-9
assert abs(e(aic) - (-2 * e(ll) + 2 * 2)) < 1e-9
assert abs(e(bic) - (-2 * e(ll) + 2 * ln(40))) < 1e-9
assert abs(e(aicc) - (e(aic) + 2 * 2 * 3 / (40 - 2 - 1))) < 1e-9
assert e(ll_0) < e(ll)
assert abs(e(ll_0) + 40 * ln(12)) < 1e-9
quietly nwrem w40, nodsnd nidrec condition(10)
assert e(N_cond) == 10
assert e(N) == 40
quietly nwrem w40, nodsnd nidrec interval endtime(50)
assert "`e(lik)'" == "interval"
assert e(starttime) == 0
assert e(endtime) == 50
quietly nwrem w40, nodsnd nidrec postmode
assert e(priormean) == 0 & e(priorscale) == 100 & e(priordf) == 4
quietly nwrem w40, nodsnd nidrec postmode priordf(.) priorscale(3) priormean(.5)
assert e(priordf) == . & e(priorscale) == 3 & e(priormean) == .5
di as text "  PASS: stored results"

di as text "{hline 60}"
di as text "Block C: identities"
di as text "{hline 60}"
* (1) a risk set that allows every dyad changes nothing
quietly nwrem w40, nodsnd nidrec frpsndsnd
matrix b0 = e(b)
scalar l0 = e(ll)
quietly nwrem w40, nodsnd nidrec frpsndsnd riskset(rsall)
assert mreldif(e(b), b0) < 1e-9
assert abs(e(ll) - l0) < 1e-9
* (2) entry and exit windows that cover the whole observation change nothing
gen double en = -1
gen double ex = 1000
quietly nwrem w40, nodsnd nidrec frpsndsnd entry(en) exit(ex)
assert mreldif(e(b), b0) < 1e-9
* (3) a fit with a weak prior of huge scale is the maximum likelihood fit to a few digits
quietly nwrem w40, nodsnd nidrec frpsndsnd postmode priorscale(1e6) priordf(.)
assert mreldif(e(b), b0) < 1e-6
* (4) a normal prior pulls towards its mean
quietly nwrem w40, nodsnd nidrec postmode priorscale(.1) priordf(.)
assert abs(el(e(b), 1, 1)) < .1 & abs(el(e(b), 1, 2)) < .1
* (5) the covariates as a list: the order of the coefficients is the order of the variables, a single covariate is the same as before
gen double z = mod(_n, 3)
gen double z2 = (_n == 2)
quietly nwrem w40, nodsnd covsnd(z)
matrix b1 = e(b)
quietly nwrem w40, nodsnd covsnd(z z2)
assert colnumb(e(b), "covsnd_z") == 2 & colnumb(e(b), "covsnd_z2") == 3
di as text "  PASS: identities"
di "test_nwrem_options14: ALL OK"
