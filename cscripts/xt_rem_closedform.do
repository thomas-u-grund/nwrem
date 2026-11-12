cscript

* xt_rem_closedform.do -- DRAFT, not yet run.
* nwrem against numbers derived by hand (closed-form maximum likelihood, scores at theta = 0) and against R relevent
* 1.2-1 on the W40 toy sequence (xt_NOTES.md lists the events and the R code).
*
* Closed form used below: when an effect splits the risk set into dyads with statistic 1 (k of them) and 0 (M - k)
* at every event, and a events fall on 1-dyads and b on 0-dyads (N = a + b), the ordinal likelihood is binomial:
*   exp(theta) = a (M - k) / (b k),  ll = a ln(a / (N k)) + b ln(b / (N (M - k))),  se = sqrt(N / (a b)).
* covsnd(x) with binary x: k = n1 (n - 1) of M = n (n - 1) dyads (sender has x = 1); covrec(x) likewise by receiver;
* covevent(C) with binary C: k = number of ones off the diagonal. All values were also checked by numerical
* maximisation in R (xt_NOTES.md).
* Expected runtime: about 20 seconds (Stata 17 BE).
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
	quietly gen long row = _n
end

capture program drop xt_cf
program xt_cf
	* xt_cf "label" ll b1 se1 [b2 se2 ...]: closed-form / R reference values; tolerances: b 1e-4 (closed form is exact,
	* the optimizer stops near it), ll 1e-8 relative, se 1e-3 relative
	gettoken label 0 : 0
	gettoken ll 0 : 0
	local k = colsof(e(b))
	forvalues j = 1/`k' {
		gettoken b 0 : 0
		gettoken se 0 : 0
		assert abs(el(e(b), 1, `j') - (`b')) < 1e-4 * (1 + abs(`b'))
		assert reldif(sqrt(el(e(V), `j', `j')), `se') < 1e-3
	}
	assert reldif(e(ll), `ll') < 1e-8
	assert "`e(unidentified)'" == ""
	di as text "  PASS: `label' (b " %10.6f el(e(b),1,1) ", ll " %12.6f e(ll) ")"
end

capture program drop xt_rref
program xt_rref
	* xt_rref "label" ll b1 se1 [b2 se2 ...]: R relevent reference; relevent and nwrem stop at their own tolerance
	gettoken label 0 : 0
	gettoken ll 0 : 0
	local k = colsof(e(b))
	forvalues j = 1/`k' {
		gettoken b 0 : 0
		gettoken se 0 : 0
		assert abs(el(e(b), 1, `j') - (`b')) < 2e-3 * (1 + abs(`b'))
		assert reldif(sqrt(el(e(V), `j', `j')), `se') < 1e-2
	}
	assert reldif(e(ll), `ll') < 1e-6
	di as text "  PASS: `label' = relevent (ll " %12.6f e(ll) ")"
end

capture program drop xt_cov
program xt_cov
	* covariate dataset of network `1': one row per actor, in actor order; checks the node labels n1..nk
	args net
	nwload `net', xvars
	capture assert _nwnode == "n" + string(_n)
	if _rc di as text "  note: actor labels are not n1..n" _N " - check the actor order used below"
end

* ---------------------------------------------------------------------------------------------------------------------
di as text "{hline 60}"
di as text "Block A: scores at theta = 0 on a 3-event sequence, every effect (hand-derived)"
di as text "{hline 60}"
* events 1->2, 1->3, 2->1; covariate (0.7, -1.2, 0.4); pairwise covariate C below. At theta = 0 the risk set is uniform
* over the 6 ordered pairs, so each score is (statistic of the realised pair) - (mean over the 6 pairs), summed over
* the events. Hand values (also brute-forced in R, xt_NOTES.md):
*   nodsnd 1/3, nidrec -2/3, nidsnd -1/6, nodrec 1/3, ntdegsnd 1/12, ntdegrec -1/6, frpsndsnd -1/2, frrecsnd 1/2,
*   covsnd 0.3, covrec 0, covint 0.3, covevent 0.4, rsndsnd -5/12, rrecsnd 1/2;  ll(0) = -3 ln 6.
mata:
XS = RemState()
XS.init((1,2,1 \ 1,3,2 \ 2,1,3), 3)
XS.build_degree_accumulators()
xc = (0.7, -1.2, 0.4)
xC = (0, 1.1, -0.6 \ 0.9, 0, 0.3 \ -0.4, 0.7, 0)
xll = .
xg = .
rem_loglik_grad_multi(J(1,14,0), J(1,14,1), xc, xc, xc, xC, &XS, xll, xg)
xhand = (1/3, -2/3, -1/6, 1/3, 1/12, -1/6, -1/2, 1/2, 0.3, 0, 0.3, 0.4, -5/12, 1/2)
assert(cols(xg) == 14)
assert(max(abs(xg :- xhand)) < 1e-12)
assert(abs(xll - (-3*ln(6))) < 1e-12)
// one effect at a time: the 1 x 1 theta / gradient path
for (e=1; e<=14; e++) {
	xa = J(1,14,0)
	xa[e] = 1
	rem_loglik_grad_multi((0), xa, xc, xc, xc, xC, &XS, xll, xg)
	assert(cols(xg) == 1)
	assert(abs(xg - xhand[e]) < 1e-12)
}
// unit-1 engine, same sequence
rem_loglik_grad_unit1((0,0), &XS, xll, xg)
assert(max(abs(xg :- (1/3, -2/3))) < 1e-12)
end
di as text "  PASS: 14 scores and ll(0) at theta = 0 equal the hand values"

* ---------------------------------------------------------------------------------------------------------------------
di as text "{hline 60}"
di as text "Block B: closed-form MLE, covsnd / covrec / covevent on W40"
di as text "{hline 60}"
nwclear
xt_w40
nwset sender receiver, eventtime(t) directed name(w40)
xt_cov w40
assert _N == 4
gen double x01 = (_n >= 3)
* senders 3 or 4: a = 17 of N = 40 events; receivers 3 or 4: a = 21
nwrem w40, covsnd(x01) seed(1)
xt_cf "covsnd(x01)" -98.9445631184 -0.302280871873 0.319846510504
assert "`: colnames e(b)'" == "covsnd_x01"
nwrem w40, covrec(x01) seed(1)
xt_cf "covrec(x01)" -99.3462451373 0.100083458557 0.316623793431
assert "`: colnames e(b)'" == "covrec_x01"
* covevent: C[i, next(i)] = 1 with next = (2,3,4,1); k = 4 of M = 12 pairs; a = 6 events on those pairs
matrix XNX = (0,1,0,0 \ 0,0,1,0 \ 0,0,0,1 \ 1,0,0,0)
nwset, mat(XNX) directed name(nxt) nooutput
nwrem w40, covevent(nxt) seed(1)
xt_cf "covevent(nxt)" -95.9271420961 -1.04145387483 0.44280744277
assert "`: colnames e(b)'" == "covevent_nxt"

* ---------------------------------------------------------------------------------------------------------------------
di as text "{hline 60}"
di as text "Block C: R relevent references on W40 (other effect families)"
di as text "{hline 60}"
nwrem w40, frpsndsnd frrecsnd seed(1)
xt_rref "frpsndsnd frrecsnd" -90.69633794 1.1904497 .5667823 0.9799925 .5263519
nwrem w40, rsndsnd rrecsnd seed(1)
xt_rref "rsndsnd rrecsnd" -94.45007925 0.8723779 .42498 0.7414476 .4206878
xt_cov w40
gen double xr = cond(_n==1, 0.5, cond(_n==2, -1, cond(_n==3, 2, 0)))
nwrem w40, covsnd(xr) seed(1)
xt_rref "covsnd(xr)" -99.17756849 -0.09789638 .1490603
nwrem w40, nodrec covint(xr) seed(1)
xt_rref "nodrec covint(xr)" -99.17186102 -0.647783046 1.013836 -0.008277574 .1272633
matrix XCE = (0,1,0,2 \ 1,0,3,0 \ 0,3,0,1 \ 2,0,1,0)
nwset, mat(XCE) directed name(ce) nooutput
nwrem w40, covevent(ce) seed(1)
xt_rref "covevent(ce)" -90.14109494 -0.7880309 .2123185
* relevent 1.2-1 references (rem.dyad, ordinal=TRUE, hessian=TRUE; relevent names NIDSnd, NTDegSnd, NTDegRec, NODRec)
nwrem w40, nidsnd seed(1)
xt_rref "nidsnd" -98.73601876 -1.173541 1.121908
nwrem w40, ntdegsnd seed(1)
xt_rref "ntdegsnd" -99.39578613 0.05213994 1.683404
nwrem w40, ntdegrec seed(1)
xt_rref "ntdegrec" -99.10655895 1.307258 1.754899
nwrem w40, nidsnd nodrec seed(1)
xt_rref "nidsnd nodrec" -98.61137981 -1.0986151 1.128497 -0.4804567 0.9953229

* ---------------------------------------------------------------------------------------------------------------------
di as text "{hline 60}"
di as text "Block D: the smallest data - two events, two actors"
di as text "{hline 60}"
* 3 actors, 2 events (1->2, 2->3), covevent with C[1,2] = 1 only: k = 1, M = 6, a = b = 1 -> theta = ln 5
nwclear
clear
input long sender long receiver double t
1 2 1
2 3 2
end
nwset sender receiver, eventtime(t) directed name(two)
matrix XC3 = (0,1,0 \ 0,0,0 \ 0,0,0)
nwset, mat(XC3) directed name(c3) nooutput
nwrem two, covevent(c3) seed(1)
assert e(N) == 2
assert e(nodes) == 3
xt_cf "2 events, 3 actors, covevent" -2.99573227355 1.60943791243 1.41421356237
* 2 actors (risk set of 2 ordered pairs), 3 events 1->2, 2->1, 1->2, C[1,2] = 1: k = 1, M = 2, a = 2, b = 1 -> ln 2
nwclear
clear
input long sender long receiver double t
1 2 1
2 1 2
1 2 3
end
nwset sender receiver, eventtime(t) directed name(pair)
matrix XC2 = (0,1 \ 0,0)
nwset, mat(XC2) directed name(c2) nooutput
nwrem pair, covevent(c2) seed(1)
assert e(nodes) == 2
xt_cf "3 events, 2 actors, covevent" -1.90954250488 0.69314718056 1.22474487139

* ---------------------------------------------------------------------------------------------------------------------
di as text "{hline 60}"
di as text "Block E: many actors, few events (60 actors, 30 events, every actor in exactly one event)"
di as text "{hline 60}"
* event i: i -> i + 30 at time i. Actors 1..30 send once and never receive, 31..60 receive once and never send.
* covsnd(x) with x = 1 for actors 1..10: n1 = 10, n0 = 50, a = 10, b = 20 -> exp(theta) = 10*50/(20*10) = 2.5
nwclear
clear
quietly set obs 30
gen long sender = _n
gen long receiver = _n + 30
gen double t = _n
nwset sender receiver, eventtime(t) directed name(big)
xt_cov big
assert _N == 60
gen double xb = (_n <= 10)
nwrem big, covsnd(xb) seed(1)
assert e(N) == 30
assert e(nodes) == 60
xt_cf "60 actors, covsnd" -242.687859405 0.916290731874 0.387298334621

di "ALL PASS"
