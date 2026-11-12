cscript

* xt_rem_errors.do -- DRAFT, not yet run.
* Error paths with the exact return code from the code (nwrem.ado line numbers as of 1.0.13; core codes from
* unw_defs.ado: 482 network not found, 6088 two-mode not supported). After every error: e() of the previous fit, the
* data in memory and the network are unchanged.
*   198  no effect (nwrem.ado:66-69); not an event network (22-25); two-mode event network (36-39); covariate
*        dataset with _N != nodes (89-93); covevent() network with another actor count (110-113); unknown option
*   109  covsnd() names a string variable (syntax varname numeric)
*   111  covsnd() names a variable that does not exist (syntax)
*   103  covsnd() with two variables (syntax varname)
*   416  covevent() network with missing tie values (115-118)
*   482  network or covevent() network not found (_nwsyntax); also two networks given (max(1))
*   2001 fewer than 2 events (139-142)
*   3498 self-loop event (Mata _error in RemState::init, unw_rem.do:78-82)
*   6088 covevent() names a two-mode network (_nw2guard)
* Expected runtime: about 15 seconds (Stata 17 BE).
* Run from the repository root; the test runner sets the adopath. No sysdir/adopath here.

capture program drop nwinstall
local nwcore : env NWCORE
if `"`nwcore'"' != "" quietly do `"`nwcore'/unw_core.do"'
quietly do unw_rem.do

mata: XT_W40 = (1,3 \ 1,3 \ 1,3 \ 1,3 \ 2,1 \ 4,2 \ 2,4 \ 2,4 \ 1,3 \ 4,3 \ 3,1 \ 4,2 \ 3,2 \ 4,2 \ 1,3 \ 1,3 \ 2,4 \ 4,2 \ 2,4 \ 2,4 \ 3,1 \ 3,1 \ 1,2 \ 1,3 \ 3,4 \ 4,1 \ 1,3 \ 3,1 \ 1,2 \ 1,3 \ 4,2 \ 2,1 \ 4,2 \ 4,2 \ 3,2 \ 2,3 \ 1,3 \ 2,4 \ 4,2 \ 2,3)

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

* ---------------------------------------------------------------------------------------------------------------------
* networks used below
nwclear
clear
quietly set obs 40
gen long sender = .
gen long receiver = .
mata: st_store(., ("sender", "receiver"), XT_W40)
gen double t = _n
nwset sender receiver, eventtime(t) directed name(w40)
nwrandom 4, prob(.5) name(static)
matrix XB5 = J(5, 5, 0)
matrix XB5[1,2] = 1
nwset, mat(XB5) directed name(five) nooutput
matrix XMS = (0,1,.,0 \ 1,0,0,0 \ 0,0,0,1 \ 0,1,0,0)
nwset, mat(XMS) directed name(miss) nooutput
matrix XBP = (1,0 \ 0,1)
nwset, mat(XBP) bipartite name(bip) nooutput
_nwsyntax bip, max(1)
assert `nodes' == 4 & "`is2mode'" == "true"
* two-mode event network: persons 1..3 send to organisations 1..2 (nwset offsets the organisation ids)
clear
input long p long o double t
1 1 1
2 1 2
3 2 3
1 2 4
2 2 5
end
nwset p o, twomode eventtime(t) name(tm)
_nwsyntax tm, max(1)
assert "`is2mode'" == "true" & "`temporaltype'" == "event"
* one event
clear
input long sender long receiver double t
1 2 1
end
nwset sender receiver, eventtime(t) directed name(one)
* a self-loop among ordinary events
clear
input long sender long receiver double t
1 2 1
2 3 2
3 3 3
3 1 4
end
nwset sender receiver, eventtime(t) directed name(loop)

* a valid fit whose e() must survive every error below; covariate dataset of w40 in memory
nwload w40, xvars
gen double x = _n
gen str1 sx = "a"
gen double x2 = 1
nwrem w40, nodsnd covsnd(x) seed(1)

* ---------------------------------------------------------------------------------------------------------------------
di as text "{hline 60}"
di as text "Block A: options and network arguments"
di as text "{hline 60}"
xt_err 198 nwrem w40
xt_err 198 nwrem w40, seed(1)
xt_err 198 nwrem w40, nodsnd seed(-1)
xt_err 198 nwrem w40, nodsnd seed(1.5)
xt_err 198 nwrem w40, nodsnd foo
xt_err 198 nwrem w40, nod
xt_err 198 nwrem static, nodsnd
xt_err 198 nwrem tm, nodsnd
xt_err 482 nwrem nosuchnet, nodsnd
xt_err 482 nwrem w40 static, nodsnd

* ---------------------------------------------------------------------------------------------------------------------
di as text "{hline 60}"
di as text "Block B: covariates"
di as text "{hline 60}"
xt_err 109 nwrem w40, covsnd(sx)
xt_err 109 nwrem w40, covrec(sx)
xt_err 109 nwrem w40, covint(sx)
xt_err 111 nwrem w40, covsnd(nosuchvar)
xt_err 103 nwrem w40, covsnd(x x2)
preserve
quietly drop in 4
xt_err 198 nwrem w40, covsnd(x)
xt_err 198 nwrem w40, nodsnd covrec(x)
quietly expand 2
xt_err 198 nwrem w40, covint(x)
restore
xt_err 198 nwrem w40, covevent(five)
xt_err 482 nwrem w40, covevent(nosuchnet)
xt_err 416 nwrem w40, covevent(miss)
xt_err 6088 nwrem w40, covevent(bip)

* ---------------------------------------------------------------------------------------------------------------------
di as text "{hline 60}"
di as text "Block C: event data"
di as text "{hline 60}"
xt_err 2001 nwrem one, nodsnd
xt_err 2001 nwrem one, rsndsnd
* (covevent(five) on the one-event network stops with 198 first: the covariate checks run before the event count)
xt_err 198 nwrem one, covevent(five)
// N2 (fixed): the self-loop refusal gives r(3498) with its message (it used to be lost: Mata _error() fails with
// r(3300) on long texts).
local xt_known ""
foreach o in "nodsnd" "frpsndsnd rsndsnd" {
	capture noisily nwrem loop, `o'
	if _rc == 3498 di as text "  PASS: r(3498): nwrem loop, `o'"
	else {
		local xt_known "`xt_known' N2(r(`=_rc'))"
		di as error "  FAIL N2: nwrem loop, `o' gives r(`=_rc'), not r(3498) with the self-loop message"
	}
	assert "`e(cmd)'" == "nwrem"
}
if "`xt_known'" != "" {
	di as error "failed:`xt_known'"
	exit 9
}

di "ALL PASS"
