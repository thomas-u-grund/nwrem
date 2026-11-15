cscript

* The core package nwcommands is found through the environment variable NWCORE (path of the core checkout).
local nwcore : env NWCORE
if `"`nwcore'"' == "" {
	di as error "set the environment variable NWCORE to the directory of the nwcommands (core) package"
	exit 198
}
adopath ++ `"`nwcore'"'
capture confirm file `"`nwcore'/lib/lnwcommands.mlib"'
if !_rc adopath ++ `"`nwcore'/lib"'
adopath ++ `"`c(pwd)'"'
quietly do `"`nwcore'/unw_core.do"'
do unw_rem.do

* The fast evaluator of unw_rem.do (rem_loglik_grad_fast(): likelihood and gradient from sums over senders and
* receivers instead of an n x n softmax per event) against the dense evaluator rem_loglik_grad_multi(), which is the
* definition of the likelihood:
*   1. every effect alone, every pair, random subsets and the full set, with ties between event times, repeated dyads,
*      a dyadic covariate with a missing or a non-zero diagonal and valued entries, in one block and in many small
*      blocks of events;
*   2. every one of the 2^14 effect subsets on a small system;
*   3. extreme coefficients: the fast evaluator gives up (returns 0: missing or underflowing normaliser) and
*      rem_loglik_grad_auto() returns the dense result; large coefficients of both signs;
*   4. rem_dependent_effects(): exactly dependent effects are found, independent ones are not;
*   5. fits of the manufacturing e-mails (core data) against values that the dense evaluator gave: t < 5 (631 events)
*      and t < 14 (2,738 events, finishing in seconds instead of 20); collinear effects are found before the optimizer.

mata:
mata set matastrict off

// simulated event stream: m events among n actors, groups of three share a time, rows in random order, repeated dyads
real matrix fx_events(real scalar n, real scalar m)
{
	real colvector s, r, t, p
	s = ceil(runiform(m, 1) :* n)
	r = ceil(runiform(m, 1) :* (n - 1))
	r = r :+ (r :>= s)
	t = ceil((1::m) :/ 3)
	p = order(runiform(m, 1), 1)
	return((s, r, t)[p,.])
}

// largest relative difference of log likelihood and gradient between the fast and the dense evaluator; . when the fast one gave up
real scalar fx_diff(real rowvector th, real rowvector act, real rowvector cs, real rowvector cr, real rowvector ci,
		real matrix cv, class RemState scalar S, real scalar cells)
{
	real scalar ll1, ll2, ok
	real rowvector g1, g2
	S.chunkcells = cells
	rem_loglik_grad_multi(th, act, cs, cr, ci, cv, &S, ll1, g1)
	ok = rem_loglik_grad_fast(th, act, cs, cr, ci, cv, &S, ll2, g2)
	if (!ok) return(.)
	return(max((abs(ll1 - ll2) / (1 + abs(ll1)), max(abs(g1 :- g2) :/ (1 :+ abs(g1))))))
}

// compare at one effect set; the covariates are passed only to the effects that read them
void fx_run(real rowvector act, real rowvector theta, real rowvector cs, real rowvector cr, real rowvector ci, real matrix cv,
		class RemState scalar S, real scalar cells, real scalar tol, string scalar label)
{
	real rowvector a, b, c, z
	real matrix v
	real scalar d
	external real scalar fx_worst, fx_count
	z = J(1, S.n, 0)
	a = z; b = z; c = z; v = J(S.n, S.n, 0)
	if (act[9]) a = cs
	if (act[10]) b = cr
	if (act[11]) c = ci
	if (act[12]) v = cv
	d = fx_diff(theta, act, a, b, c, v, S, cells)
	if (missing(d)) {
		errprintf("%s: the fast evaluator gave up at a moderate coefficient\n", label)
		exit(498)
	}
	if (d > tol) {
		errprintf("%s: fast and dense evaluator differ by %g\n", label, d)
		exit(498)
	}
	fx_worst = max((fx_worst, d))
	fx_count = fx_count + 1
}

void fx_reset()
{
	external real scalar fx_worst, fx_count
	fx_worst = 0
	fx_count = 0
}

void fx_report(string scalar what)
{
	external real scalar fx_worst, fx_count
	printf("{txt}  %g %s, largest relative difference %g\n", fx_count, what, fx_worst)
}

// random subset (each effect with probability p, at least one) of the 14 effects
real rowvector fx_subset(real scalar p)
{
	real rowvector act
	act = (runiform(1, 14) :< p)
	if (sum(act) == 0) act[ceil(runiform(1, 1) * 14)] = 1
	return(act)
}
end

* ---------------------------------------------------------------------------------------------------------------------
di as text "{hline 60}"
di as text "Test 1: fast against dense evaluator: single effects, pairs, random subsets, the full set"
di as text "{hline 60}"

mata:
rseed(20261115)
fx_reset()
n = 11
S1 = RemState()
S1.init(fx_events(n, 90), n)
S1.build_degree_accumulators()
rem_fast_prep(S1)
cs = runiform(1, n) :* 3
cr = runiform(1, n) :- .5
ci = rnormal(1, n, 0, 2)
// dyadic covariate: valued entries (negative, zero, large), missing diagonal
CV = round(rnormal(n, n, 0, 2))
for (j = 1; j <= n; j++) CV[j,j] = .
// the same with a non-zero diagonal: the diagonal is not part of the risk set, whatever it holds
CV2 = CV
for (j = 1; j <= n; j++) CV2[j,j] = 7
sets = J(0, 14, 0)
for (e = 1; e <= 14; e++) {
	a = J(1, 14, 0)
	a[e] = 1
	sets = sets \ a
}
for (e = 1; e < 14; e++) {
	for (f = e + 1; f <= 14; f++) {
		a = J(1, 14, 0)
		a[e] = 1
		a[f] = 1
		sets = sets \ a
	}
}
for (k = 1; k <= 120; k++) sets = sets \ fx_subset(.5)
sets = sets \ J(1, 14, 1)
for (k = 1; k <= rows(sets); k++) {
	act = sets[k,.]
	theta = (runiform(1, sum(act)) :- .5) :* 3
	fx_run(act, theta, cs, cr, ci, CV, S1, ., 1e-10, "set " + strofreal(k))
	fx_run(act, theta, cs, cr, ci, CV2, S1, 40, 1e-10, "set " + strofreal(k) + " (small blocks, loop diagonal)")
}
fx_report("evaluations")
end
di as text "  PASS: fast evaluator equals the dense evaluator (single effects, pairs, random subsets, full set; one block and small blocks)"

* ---------------------------------------------------------------------------------------------------------------------
di as text "{hline 60}"
di as text "Test 2: all 2^14 effect subsets on a small system"
di as text "{hline 60}"

mata:
n = 6
S2 = RemState()
S2.init(fx_events(n, 24), n)
S2.build_degree_accumulators()
rem_fast_prep(S2)
cs = runiform(1, n) :* 3
cr = runiform(1, n) :- .5
ci = rnormal(1, n, 0, 2)
CV = round(rnormal(n, n, 0, 2))
for (j = 1; j <= n; j++) CV[j,j] = .
fx_reset()
for (code = 1; code < 2^14; code++) {
	act = J(1, 14, 0)
	for (e = 1; e <= 14; e++) act[e] = mod(floor(code / 2^(e - 1)), 2)
	theta = (runiform(1, sum(act)) :- .5) :* 2
	fx_run(act, theta, cs, cr, ci, CV, S2, 7 * n, 1e-10, "subset code " + strofreal(code))
}
fx_report("subsets")
end
di as text "  PASS: all 16,383 effect subsets agree"

* ---------------------------------------------------------------------------------------------------------------------
di as text "{hline 60}"
di as text "Test 3: extreme coefficients, fall back to the dense evaluator"
di as text "{hline 60}"

mata:
// actor 1 sends to everybody and never receives: after the first events it has the largest out-degree share and the
// smallest in-degree share, so with a large positive nodsnd and a large negative nidrec both shifts sit at actor 1 and the
// normaliser (sum e^a)(sum e^b) minus the diagonal underflows to 0
ev = (1,2,1 \ 1,3,2 \ 1,4,3 \ 1,2,4 \ 1,3,5 \ 1,4,6 \ 2,3,7 \ 1,2,8 \ 3,4,9 \ 1,3,10 \ 4,2,11 \ 1,4,12)
S3 = RemState()
S3.init(ev, 4)
S3.build_degree_accumulators()
rem_fast_prep(S3)
z = J(1, 4, 0); z0 = J(4, 4, 0)
act = (1,1,0,0,0,0,0,0,0,0,0,0,0,0)
th = (1e4, -1e4)
llf = 0; gf = J(1, 0, 0); lla = 0; ga = J(1, 0, 0); lld = 0; gd = J(1, 0, 0)
ok = rem_loglik_grad_fast(th, act, z, z, z, z0, &S3, llf, gf)
if (ok != 0) {
	errprintf("the fast evaluator did not give up at nodsnd = 1e4, nidrec = -1e4\n")
	exit(498)
}
S3.fast = 1
ok = rem_loglik_grad_auto(th, act, z, z, z, z0, &S3, lla, ga)
rem_loglik_grad_multi(th, act, z, z, z, z0, &S3, lld, gd)
if (ok != 0 | lla != lld | max(abs(ga :- gd)) > 0 | missing(lla)) {
	errprintf("the automatic evaluator did not return the dense result after the fast one gave up\n")
	exit(498)
}
printf("{txt}  underflowing normaliser: fast gives up, automatic evaluator returns the dense value %g\n", lla)

// overflow of exp(): a state-dependent dyadic effect with a huge coefficient
for (e = 7; e <= 14; e++) {
	if (e >= 9 & e <= 12) continue
	act = J(1, 14, 0)
	act[e] = 1
	ok = rem_loglik_grad_fast((900), act, z, z, z, z0, &S3, llf, gf)
	if (ok != 0) {
		errprintf("the fast evaluator did not give up at a coefficient of 900 for effect %g\n", e)
		exit(498)
	}
	ok = rem_loglik_grad_auto((900), act, z, z, z, z0, &S3, lla, ga)
	rem_loglik_grad_multi((900), act, z, z, z, z0, &S3, lld, gd)
	if (ok != 0 | lla != lld | max(abs(ga :- gd)) > 0) {
		errprintf("the automatic evaluator did not return the dense result for effect %g at 900\n", e)
		exit(498)
	}
}
// the static dyadic effect: the exponentiated matrix is shifted by its maximum, so a huge coefficient needs no fall back
CVs = (0,1,2,0 \ 1,0,3,1 \ 0,2,0,1 \ 2,0,1,0)
act = J(1, 14, 0)
act[12] = 1
act[1] = 1
d = fx_diff((.5, 600), act, z, z, z, CVs, S3, .)
if (missing(d)) d = 0
if (d > 1e-9) {
	errprintf("covevent at a coefficient of 600 differs by %g\n", d)
	exit(498)
}
// a missing coefficient
ok = rem_loglik_grad_fast((., 1), (1,1,0,0,0,0,0,0,0,0,0,0,0,0), z, z, z, z0, &S3, llf, gf)
if (ok != 0) {
	errprintf("the fast evaluator accepted a missing coefficient\n")
	exit(498)
}

// large coefficients of both signs: compare whichever evaluator the automatic one uses
rseed(7)
n = 30
S4 = RemState()
S4.init(fx_events(n, 400), n)
S4.build_degree_accumulators()
rem_fast_prep(S4)
S4.fast = 1
z = J(1, n, 0); z0 = J(n, n, 0)
worst = 0
thetas = (400, -270 \ 30, 20 \ -50, 80 \ 120, 0 \ 0, -150 \ 400, 270 \ 10, 10)
for (k = 1; k <= rows(thetas); k++) {
	act = (1,1,0,0,0,0,0,0,0,0,0,0,0,0)
	rem_loglik_grad_auto(thetas[k,.], act, z, z, z, z0, &S4, lla, ga)
	rem_loglik_grad_multi(thetas[k,.], act, z, z, z, z0, &S4, lld, gd)
	worst = max((worst, abs(lla - lld) / (1 + abs(lld)), max(abs(ga :- gd) :/ (1 :+ abs(gd)))))
}
printf("{txt}  coefficients up to (400, -270): largest relative difference %g\n", worst)
if (worst > 1e-9) {
	errprintf("large coefficients: automatic and dense evaluator differ by %g\n", worst)
	exit(498)
}
printf("{txt}  fall-back checks done\n")
end
di as text "  PASS: extreme coefficients fall back to the dense evaluator; large coefficients agree"

* ---------------------------------------------------------------------------------------------------------------------
di as text "{hline 60}"
di as text "Test 4: effects that are exactly dependent on others are found before the optimizer"
di as text "{hline 60}"

mata:
rseed(11)
n = 12
S5 = RemState()
S5.init(fx_events(n, 150), n)
S5.build_degree_accumulators()
z = J(1, n, 0); z0 = J(n, n, 0)
u = rnormal(1, n, 0, 1)
v = rnormal(1, n, 0, 1)
CVr = rnormal(n, n, 0, 1)
for (j = 1; j <= n; j++) CVr[j,j] = .
CVs = u' * J(1, n, 1) :+ J(n, 1, 1) * v       // u_j + v_k: exactly the sum of a covsnd and a covrec effect
// 1. ntdegsnd = (nodsnd + nidsnd) / 2 and ntdegrec = (nidrec + nodrec) / 2
d = rem_dependent_effects((1,1,1,1,1,1,0,0,0,0,0,0,0,0), z, z, z, z0, S5)
if (d != (0,0,0,0,1,1,0,0,0,0,0,0,0,0)) {
	errprintf("degree shares: wrong dependent effects %s\n", invtokens(strofreal(d)))
	exit(498)
}
// 2. independent effects: none
d = rem_dependent_effects((1,1,1,1,0,0,0,0,1,1,0,1,0,0), u, v, z, CVr, S5)
if (d != J(1, 14, 0)) {
	errprintf("independent effects: found dependent %s\n", invtokens(strofreal(d)))
	exit(498)
}
// 3. covint = covsnd + covrec of the same variable; a constant covariate; a dyadic covariate u_j + v_k
d = rem_dependent_effects((0,0,0,0,0,0,0,0,1,1,1,0,0,0), u, u, u, z0, S5)
if (d != (0,0,0,0,0,0,0,0,0,0,1,0,0,0)) {
	errprintf("covsnd covrec covint of one variable: wrong dependent effects %s\n", invtokens(strofreal(d)))
	exit(498)
}
d = rem_dependent_effects((1,0,0,0,0,0,0,0,1,1,0,0,0,0), J(1, n, 3), J(1, n, 3), z, z0, S5)
if (d != (0,0,0,0,0,0,0,0,1,1,0,0,0,0)) {
	errprintf("constant covariates: wrong dependent effects %s\n", invtokens(strofreal(d)))
	exit(498)
}
d = rem_dependent_effects((0,0,0,0,0,0,0,0,1,1,0,1,0,0), u, v, z, CVs, S5)
if (d != (0,0,0,0,0,0,0,0,0,0,0,1,0,0)) {
	errprintf("dyadic covariate u_j + v_k: wrong dependent effects %s\n", invtokens(strofreal(d)))
	exit(498)
}
// 4. a dyadic covariate that is constant (all ones off the diagonal, missing diagonal) does not change the likelihood
CVo = J(n, n, 1)
for (j = 1; j <= n; j++) CVo[j,j] = .
d = rem_dependent_effects((1,0,0,0,0,0,0,0,0,0,0,1,0,0), z, z, z, CVo, S5)
if (d != (0,0,0,0,0,0,0,0,0,0,0,1,0,0)) {
	errprintf("constant dyadic covariate: wrong dependent effects %s\n", invtokens(strofreal(d)))
	exit(498)
}
// 5. state-dependent dyadic effects are not examined
d = rem_dependent_effects((0,0,0,0,0,0,1,1,0,0,0,0,1,1), z, z, z, z0, S5)
if (d != J(1, 14, 0)) {
	errprintf("state-dependent effects were examined: %s\n", invtokens(strofreal(d)))
	exit(498)
}
// 6. the same answer in small blocks of events
S5.chunkcells = 5 * n
d = rem_dependent_effects((1,1,1,1,1,1,0,0,0,0,0,0,0,0), z, z, z, z0, S5)
if (d != (0,0,0,0,1,1,0,0,0,0,0,0,0,0)) {
	errprintf("degree shares in small blocks: wrong dependent effects %s\n", invtokens(strofreal(d)))
	exit(498)
}
printf("{txt}  dependence checks done\n")
end
di as text "  PASS: dependent effects found (degree shares, covint = covsnd + covrec, constant covariates, u_j + v_k); independent ones kept"

* ---------------------------------------------------------------------------------------------------------------------
di as text "{hline 60}"
di as text "Test 5: fits of the manufacturing e-mails against the values of the dense evaluator"
di as text "{hline 60}"

global nwwebpath `"`nwcore'/data"'
capture program drop fx_check
* fx_check b1 se1 b2 se2 ... ll : coefficients and standard errors in the order of e(b), then the log likelihood
program fx_check
	local k = colsof(e(b))
	assert `: word count `0'' == 2 * `k' + 1
	forvalues j = 1/`k' {
		local b : word `=2 * `j' - 1' of `0'
		local se : word `=2 * `j'' of `0'
		assert reldif(el(e(b), 1, `j'), `b') < 1e-8
		assert reldif(sqrt(el(e(V), `j', `j')), `se') < 1e-6
	}
	assert reldif(e(ll), `: word `=2 * `k' + 1' of `0'') < 1e-10
end

nwclear
nwwebuse manufacturing, nwclear
keep if t < 5
nwset sender receiver, eventtime(t) name(mail)
nwload mail, xvars
rename _nwnode label
merge 1:1 label using `"`nwcore'/data/manufacturing_nodes.dta"', keep(master match) nogen
nwexpand supervisor, name(samesup) replace

* reference values: the dense evaluator (nwrem 1.1.2), seed(1)
nwrem mail, nodsnd nidrec seed(1)
assert e(N) == 631
fx_check 10.64882306124531 1.31731033712525 20.73028624148009 1.11369268043664 -5645.075307669897
di as text "  PASS: nodsnd nidrec, t < 5"
nwrem mail, nodsnd nidrec frpsndsnd seed(1)
fx_check 10.30295972562383 1.51210053679934 13.15074665803199 1.27184441305766 3.79098865926030 0.13830188555596 -5425.429175266350
di as text "  PASS: + frpsndsnd, t < 5"
nwrem mail, nodsnd nidrec rsndsnd seed(1)
fx_check 7.10578989093174 1.36388956447462 10.33988522392113 1.26359423934455 3.65589437989141 0.10421383098377 -5252.617684989861
di as text "  PASS: + rsndsnd, t < 5"
nwrem mail, nodsnd nidrec covevent(samesup) seed(1)
fx_check 10.58507173891137 1.30253315152242 20.83310084586524 1.10922834273615 1.18022703180076 0.12312834738686 -5610.832551451944
di as text "  PASS: + covevent, t < 5"
nwrem mail, nodsnd nidrec frrecsnd rrecsnd seed(1)
fx_check 9.46998111817661 1.22568790937882 20.38789405029889 1.19352716176800 -0.40491274841219 0.21013347268920 4.51218646262584 0.14461893337039 -5044.169981016455
di as text "  PASS: + frrecsnd rrecsnd, t < 5"
nwrem mail, nidsnd nodrec ntdegrec frpsndsnd covevent(samesup) rsndsnd seed(1)
fx_check 7.50347041242392 1.38273846419740 -4.81899841616153 1.43910344771914 24.16805171703267 2.26366065823397 -0.28780248137577 0.23438452560943 0.71341274078179 0.12581291340925 3.72988657978465 0.15922683507044 -5231.713149577919
di as text "  PASS: six effects (state-dependent and static dyadic together), t < 5"

* collinear effects: found before the optimizer; the likelihood is the one of the model without the dependent effect
timer clear 1
timer on 1
nwrem mail, nodsnd nidsnd ntdegsnd seed(1)
timer off 1
quietly timer list 1
assert "`e(unidentified)'" == "ntdegsnd"
assert reldif(e(ll), -5778.042686824900) < 1e-9
assert el(e(b), 1, 3) == 0 & el(e(V), 3, 3) == 0
* the estimable combinations, nodsnd + ntdegsnd / 2 and nidsnd + ntdegsnd / 2, of the dense fit (its three coefficients are
* arbitrary along the flat ridge, and it stops before the ridge is explored: agreement to about 1e-4 only)
assert reldif(el(e(b), 1, 1), 7.64797196875559 + 6.29515027664899 / 2) < 1e-3
assert reldif(el(e(b), 1, 2), 4.84750666544571 + 6.29515027664899 / 2) < 1e-3
assert r(t1) < 30
di as text "  PASS: nodsnd nidsnd ntdegsnd: ntdegsnd unidentified, same log likelihood as the dense evaluator (" as result %5.2f r(t1) as text " s)"

* the whole t < 14 window (2,738 events, 129 actors): the dense evaluator needed 20 s for this fit
nwclear
nwwebuse manufacturing, nwclear
keep if t < 14
nwset sender receiver, eventtime(t) name(mail14)
timer clear 2
timer on 2
nwrem mail14, nodsnd nidrec seed(1)
timer off 2
quietly timer list 2
assert e(N) == 2738
fx_check 36.99530642404960 1.47878890471070 35.10519198237711 0.68826037436318 -25292.5437341
assert r(t2) < 60
di as text "  PASS: nodsnd nidrec, t < 14 (2,738 events) in " as result %5.2f r(t2) as text " s"

di as result "ALL TESTS PASSED"
