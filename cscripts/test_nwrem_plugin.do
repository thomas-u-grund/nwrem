cscript

* The nwrem plugin (native/rem_sim.c) against the Mata reference evaluators (cscripts/ref_rem_mata.do), which agree with R's relevent:
*   1. every effect alone, every pair, random subsets and the full set, on random small event sequences with ties between event
*      times, repeated dyads, a valued dyadic covariate (negative, zero, large; missing or non-zero diagonal);
*   2. every one of the 2^14 effect subsets on a small system;
*   3. the fast and the dense evaluator of the plugin (codes 22 and 21) against each other and the automatic one (code 20);
*   4. extreme coefficients: the fast evaluator gives up (code 22: missing) and the plugin's dense evaluator gives the reference value;
*   5. the check for exactly dependent effects (plugin, code 30) against rem_dependent_effects();
*   6. the exact Hessian against the numerical derivative of the reference gradient.
* Log likelihood and gradient must agree to 1e-9 (relative), the Hessian with the numerical derivative to 1e-5.
local nwcore : env NWCORE
if `"`nwcore'"' == "" {
	di as error "set the environment variable NWCORE to the directory of the nwcommands (core) package"
	exit 198
}
quietly do `"`nwcore'/unw_core.do"'
do unw_rem.do
do cscripts/ref_rem_mata.do

mata:
mata set matastrict off

// simulated event stream: m events among n actors, groups of three share a time, rows in random order, repeated dyads
real matrix pl_events(real scalar n, real scalar m, real scalar tiesize)
{
	real colvector s, r, t, p
	s = ceil(runiform(m, 1) :* n)
	r = ceil(runiform(m, 1) :* (n - 1))
	r = r :+ (r :>= s)
	t = ceil((1::m) :/ tiesize)
	p = order(runiform(m, 1), 1)
	return((s, r, t)[p,.])
}

real rowvector pl_subset(real scalar p)
{
	real rowvector act
	act = (runiform(1, 14) :< p)
	if (sum(act) == 0) act[ceil(runiform(1, 1) * 14)] = 1
	return(act)
}

// result of one plugin call: code, theta (compact), todo; ll, g, H, Exx, flag
void pl_call(class RemNat scalar NT, real scalar code, real rowvector theta, real scalar todo,
		real scalar ll, real rowvector g, real matrix H, real rowvector exx, real scalar flag)
{
	real scalar k, pt
	string scalar argstr
	real colvector res
	pt = NT.Pt
	argstr = strofreal(code) + " " + strofreal(NT.L, "%18.0f") + " " + strofreal(todo) + " " + strofreal(pt)
	for (k = 1; k <= pt; k++) argstr = argstr + " " + strofreal(theta[k], "%25.17g")
	stata("plugin call remnative v1 v2, " + char(34) + argstr + char(34))
	res = st_data((1::(2 + 2 * pt + pt * pt)), 2)
	ll = res[1]
	g = res[2::(1 + pt)]'
	H = rowshape(res[(2 + pt)::(1 + pt + pt * pt)], pt)
	exx = res[(2 + pt + pt * pt)::(1 + 2 * pt + pt * pt)]'
	flag = res[2 + 2 * pt + pt * pt]
}

// reference log likelihood and gradient, ll first
real rowvector pl_ref(real rowvector theta, real rowvector act, real rowvector cs, real rowvector cr, real rowvector ci, real matrix CV,
		class RemState scalar S)
{
	real scalar ll
	real rowvector g
	ll = 0; g = J(1, 0, 0)
	rem_loglik_grad_multi(theta, act, cs, cr, ci, CV, &S, ll, g)
	return((ll, g))
}

real scalar pl_reldiff(real matrix a, real matrix b)
{
	return(max(abs(a :- b) :/ (1 :+ abs(b))))
}

void pl_fail(string scalar msg, real scalar d)
{
	errprintf("%s (difference %g)\n", msg, d)
	exit(498)
}

// compare the plugin at theta with the reference for one model; returns the largest relative differences
void pl_compare(real matrix evraw, real scalar n, real rowvector act, real rowvector theta, real rowvector cs, real rowvector cr,
		real rowvector ci, real matrix CV, real scalar htest, string scalar label, real scalar worst, real scalar worsth)
{
	class RemState scalar S
	class RemNat scalar NT
	real scalar ll0, ll1, ll2, ll3, f1, f2, f3, d, k, h, nact
	real rowvector g0, g1, g2, g3, ex, th, tp, tm, gp, gm
	real matrix H1, H2, H3, hn, ev
	real colvector idx

	S = RemState(); S.init(evraw, n); S.build_degree_accumulators()
	ev = rem_sorted_events(evraw)
	NT = RemNat(); NT.open()
	NT.setup(ev, n, act, cs, cr, ci, CV)
	nact = sum(act)
	rem_loglik_grad_multi(theta, act, cs, cr, ci, CV, &S, ll0, g0)
	pl_call(NT, 20, theta, 2, ll1, g1, H1, ex, f1)
	pl_call(NT, 21, theta, 2, ll2, g2, H2, ex, f2)
	pl_call(NT, 22, theta, 2, ll3, g3, H3, ex, f3)
	NT.close()
	if (f2 != 1) pl_fail(label + ": code 21 did not use the dense evaluator", f2)
	d = max((abs(ll1 - ll0) / (1 + abs(ll0)), pl_reldiff(g1, g0)))
	if (d > 1e-9) pl_fail(label + ": plugin (20) and reference differ", d)
	worst = max((worst, d))
	d = max((abs(ll2 - ll0) / (1 + abs(ll0)), pl_reldiff(g2, g0)))
	if (d > 1e-9) pl_fail(label + ": plugin dense (21) and reference differ", d)
	worst = max((worst, d))
	if (!missing(ll3)) {
		d = max((abs(ll3 - ll0) / (1 + abs(ll0)), pl_reldiff(g3, g0), pl_reldiff(H3, H2)))
		if (d > 1e-8) pl_fail(label + ": plugin fast (22) and dense (21) differ", d)
		worst = max((worst, d))
	}
	d = pl_reldiff(H1, H2)
	if (d > 1e-8) pl_fail(label + ": Hessian of the automatic and the dense evaluator differ", d)
	if (htest) {
		h = 1e-5
		hn = J(nact, nact, 0)
		for (k = 1; k <= nact; k++) {
			tp = theta; tm = theta
			tp[k] = tp[k] + h; tm[k] = tm[k] - h
			rem_loglik_grad_multi(tp, act, cs, cr, ci, CV, &S, ll0, gp)
			rem_loglik_grad_multi(tm, act, cs, cr, ci, CV, &S, ll0, gm)
			hn[k,.] = (gp - gm) :/ (2 * h)
		}
		d = pl_reldiff(H1, hn)
		if (d > 1e-5) pl_fail(label + ": Hessian differs from the numerical derivative of the reference gradient", d)
		worsth = max((worsth, d))
	}
}
end

di as text "{hline 60}"
di as text "Test 1: plugin against the reference: single effects, pairs, random subsets, the full set"
di as text "{hline 60}"
mata:
rseed(20261116)
worst = 0; worsth = 0; cnt = 0
n = 9
cs = runiform(1, n) :* 3
cr = runiform(1, n) :- .5
ci = rnormal(1, n, 0, 2)
CV = round(rnormal(n, n, 0, 2))
for (j = 1; j <= n; j++) CV[j,j] = .
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
for (k = 1; k <= 120; k++) sets = sets \ pl_subset(.5)
sets = sets \ J(1, 14, 1)
for (k = 1; k <= rows(sets); k++) {
	act = sets[k,.]
	ev = pl_events(n, 70, 1 + mod(k, 4))
	theta = (runiform(1, sum(act)) :- .5) :* 3
	pl_compare(ev, n, act, theta, cs, cr, ci, (mod(k,2) ? CV : CV2), mod(k, 7) == 0, "set " + strofreal(k), worst, worsth)
	cnt++
}
printf("{txt}  %g models, largest relative difference %g, Hessian against the numerical derivative %g\n", cnt, worst, worsth)
end
di as text "  PASS: plugin equals the reference (single effects, pairs, random subsets, full set; ties, repeated dyads, valued covevent)"

di as text "{hline 60}"
di as text "Test 2: all 2^14 effect subsets on a small system"
di as text "{hline 60}"
mata:
rseed(11)
n = 6
ev = pl_events(n, 24, 3)
cs = runiform(1, n) :* 3
cr = runiform(1, n) :- .5
ci = rnormal(1, n, 0, 2)
CV = round(rnormal(n, n, 0, 2))
for (j = 1; j <= n; j++) CV[j,j] = .
worst = 0; worsth = 0
for (code = 1; code < 2^14; code++) {
	act = J(1, 14, 0)
	for (e = 1; e <= 14; e++) act[e] = mod(floor(code / 2^(e - 1)), 2)
	theta = (runiform(1, sum(act)) :- .5) :* 2
	pl_compare(ev, n, act, theta, cs, cr, ci, CV, 0, "subset code " + strofreal(code), worst, worsth)
}
printf("{txt}  16,383 subsets, largest relative difference %g\n", worst)
end
di as text "  PASS: all 16,383 effect subsets agree"

di as text "{hline 60}"
di as text "Test 3: sizes (two actors apart from the dyad, large n), single event, all events one actor pair"
di as text "{hline 60}"
mata:
rseed(5)
worst = 0; worsth = 0
// n = 3, the smallest model; many ties (every event the same time)
n = 3
cs = runiform(1, n); cr = runiform(1, n); ci = runiform(1, n); CV = runiform(n, n)
for (k = 1; k <= 20; k++) {
	act = pl_subset(.5)
	theta = (runiform(1, sum(act)) :- .5)
	ev = pl_events(n, 15, 15)
	pl_compare(ev, n, act, theta, cs, cr, ci, CV, 1, "n=3 " + strofreal(k), worst, worsth)
}
// one dyad repeated
n = 5
cs = runiform(1, n); cr = runiform(1, n); ci = runiform(1, n); CV = runiform(n, n)
ev = (J(30, 1, 2), J(30, 1, 4), (1::30))
for (k = 1; k <= 20; k++) {
	act = pl_subset(.6)
	theta = (runiform(1, sum(act)) :- .5)
	pl_compare(ev, n, act, theta, cs, cr, ci, CV, 1, "repeated dyad " + strofreal(k), worst, worsth)
}
// larger n
n = 40
cs = runiform(1, n); cr = runiform(1, n); ci = runiform(1, n); CV = round(runiform(n, n) :* 1.5)
for (k = 1; k <= 8; k++) {
	act = pl_subset(.5)
	theta = (runiform(1, sum(act)) :- .5)
	ev = pl_events(n, 300, 2)
	pl_compare(ev, n, act, theta, cs, cr, ci, CV, 0, "n=40 " + strofreal(k), worst, worsth)
}
printf("{txt}  largest relative difference %g\n", worst)
end
di as text "  PASS: n = 3, a repeated dyad, all events tied, n = 40"

di as text "{hline 60}"
di as text "Test 4: extreme coefficients: the fast evaluator gives up, the dense one gives the reference value"
di as text "{hline 60}"
mata:
// plugin result of one call on a fresh model: (ll, g, flag) in a row
real rowvector pl_one(real matrix evraw, real scalar n, real rowvector act, real rowvector theta, real rowvector cs, real rowvector cr,
		real rowvector ci, real matrix CV, real scalar code)
{
	class RemNat scalar NT
	real scalar ll, flag
	real rowvector g, ex
	real matrix H
	ll = 0; g = 0; H = 0; ex = 0; flag = 0
	NT = RemNat(); NT.open()
	NT.setup(rem_sorted_events(evraw), n, act, cs, cr, ci, CV)
	pl_call(NT, code, theta, 2, ll, g, H, ex, flag)
	NT.close()
	return((ll, flag, g))
}

// one model: the plugin (code 20) against the reference at theta; the fast evaluator (22) must have given up when wantgiveup
void pl_extreme(real matrix evraw, real scalar n, real rowvector act, real rowvector theta, real rowvector cs, real rowvector cr,
		real rowvector ci, real matrix CV, real scalar wantgiveup, string scalar label, real scalar worst)
{
	class RemState scalar S
	real rowvector r20, r22, r0
	real scalar d
	S = RemState(); S.init(evraw, n); S.build_degree_accumulators()
	r20 = pl_one(evraw, n, act, theta, cs, cr, ci, CV, 20)
	r22 = pl_one(evraw, n, act, theta, cs, cr, ci, CV, 22)
	r0 = pl_ref(theta, act, cs, cr, ci, CV, S)
	if (wantgiveup & !missing(r22[1])) pl_fail(label + ": the fast evaluator did not give up", r22[1])
	if (missing(r20[1])) pl_fail(label + ": the plugin gave no result", 0)
	if (wantgiveup & r20[2] != 1) pl_fail(label + ": code 20 did not fall back to the dense evaluator", r20[2])
	d = max((abs(r20[1] - r0[1]) / (1 + abs(r0[1])), max(abs(r20[3..cols(r20)] :- r0[2..cols(r0)]) :/ (1 :+ abs(r0[2..cols(r0)])))))
	if (d > 1e-8) pl_fail(label + ": plugin and reference differ", d)
	worst = max((worst, d))
}

rseed(7)
worst = 0
ev = (1,2,1 \ 1,3,2 \ 1,4,3 \ 1,2,4 \ 1,3,5 \ 1,4,6 \ 2,3,7 \ 1,2,8 \ 3,4,9 \ 1,3,10 \ 4,2,11 \ 1,4,12)
n = 4
z = J(1, n, 0); z0 = J(n, n, 0)
// actor 1 sends to everybody and never receives: with a large positive nodsnd and a large negative nidrec both shifts sit at actor 1
// and the product form of the normaliser underflows
pl_extreme(ev, n, (1,1,0,0,0,0,0,0,0,0,0,0,0,0), (1e4, -1e4), z, z, z, z0, 1, "nodsnd 1e4 nidrec -1e4", worst)
// huge coefficient of a state-dependent dyadic effect (exp() overflows): the fast evaluator gives up
for (e = 7; e <= 14; e++) {
	if (e >= 9 & e <= 12) continue
	act = J(1, 14, 0)
	act[e] = 1
	pl_extreme(ev, n, act, (900), z, z, z, z0, 1, "effect " + strofreal(e) + " at 900", worst)
	// a large negative coefficient: the sparse correction cancels the normaliser
	pl_extreme(ev, n, act, (-60), z, z, z, z0, 0, "effect " + strofreal(e) + " at -60", worst)
	pl_extreme(ev, n, act, (-700), z, z, z, z0, 0, "effect " + strofreal(e) + " at -700", worst)
}
// large coefficients of both signs on a larger system
n = 30
ev = pl_events(n, 400, 3)
z = J(1, n, 0); z0 = J(n, n, 0)
thetas = (400, -270 \ 30, 20 \ -50, 80 \ 120, 0 \ 0, -150 \ 400, 270 \ 10, 10)
for (k = 1; k <= rows(thetas); k++) {
	pl_extreme(ev, n, (1,1,0,0,0,0,0,0,0,0,0,0,0,0), thetas[k,.], z, z, z, z0, 0, "theta row " + strofreal(k), worst)
}
printf("{txt}  largest relative difference %g\n", worst)
end
di as text "  PASS: extreme coefficients: the dense evaluator takes over and agrees with the reference"

di as text "{hline 60}"
di as text "Test 5: effects that are exactly dependent on others (plugin, code 30) against rem_dependent_effects()"
di as text "{hline 60}"
mata:
void pl_expect(real rowvector got, real rowvector want, string scalar msg)
{
	if (got != want) {
		errprintf("%s: found %s, expected %s\n", msg, invtokens(strofreal(got)), invtokens(strofreal(want)))
		exit(498)
	}
}

real rowvector pl_dep(real rowvector act, real rowvector cs, real rowvector cr, real rowvector ci, real matrix CV, real matrix evraw, real scalar n)
{
	class RemNat scalar NT
	class RemState scalar S
	real rowvector dnat, dref
	S = RemState(); S.init(evraw, n); S.build_degree_accumulators()
	NT = RemNat(); NT.open()
	NT.setup(rem_sorted_events(evraw), n, act, cs, cr, ci, CV)
	dnat = rem_nat_dependent(&NT, act)
	NT.close()
	dref = rem_dependent_effects(act, cs, cr, ci, CV, S)
	if (dnat != dref) {
		errprintf("dependent effects: plugin %s, reference %s\n", invtokens(strofreal(dnat)), invtokens(strofreal(dref)))
		exit(498)
	}
	return(dnat)
}
rseed(11)
n = 12
evraw = pl_events(n, 150, 3)
z = J(1, n, 0); z0 = J(n, n, 0)
u = rnormal(1, n, 0, 1); v = rnormal(1, n, 0, 1)
CVr = rnormal(n, n, 0, 1)
for (j = 1; j <= n; j++) CVr[j,j] = .
CVs = u' * J(1, n, 1) :+ J(n, 1, 1) * v
d = pl_dep((1,1,1,1,1,1,0,0,0,0,0,0,0,0), z, z, z, z0, evraw, n)
pl_expect(d, (0,0,0,0,1,1,0,0,0,0,0,0,0,0), "degree shares: wrong dependent effects")
d = pl_dep((1,1,1,1,0,0,0,0,1,1,0,1,0,0), u, v, z, CVr, evraw, n)
pl_expect(d, J(1, 14, 0), "independent effects: found dependent")
d = pl_dep((0,0,0,0,0,0,0,0,1,1,1,0,0,0), u, u, u, z0, evraw, n)
pl_expect(d, (0,0,0,0,0,0,0,0,0,0,1,0,0,0), "covint = covsnd + covrec: wrong")
d = pl_dep((1,0,0,0,0,0,0,0,1,1,0,0,0,0), J(1, n, 3), J(1, n, 3), z, z0, evraw, n)
pl_expect(d, (0,0,0,0,0,0,0,0,1,1,0,0,0,0), "constant covariates: wrong")
d = pl_dep((0,0,0,0,0,0,0,0,1,1,0,1,0,0), u, v, z, CVs, evraw, n)
pl_expect(d, (0,0,0,0,0,0,0,0,0,0,0,1,0,0), "u_j + v_k dyadic covariate: wrong")
CVo = J(n, n, 1)
for (j = 1; j <= n; j++) CVo[j,j] = .
d = pl_dep((1,0,0,0,0,0,0,0,0,0,0,1,0,0), z, z, z, CVo, evraw, n)
pl_expect(d, (0,0,0,0,0,0,0,0,0,0,0,1,0,0), "constant dyadic covariate: wrong")
d = pl_dep((0,0,0,0,0,0,1,1,0,0,0,0,1,1), z, z, z, z0, evraw, n)
pl_expect(d, J(1, 14, 0), "state-dependent effects were examined")
for (k = 1; k <= 40; k++) {
	act = pl_subset(.5)
	act[(7, 8, 13, 14)] = J(1, 4, 0)
	if (sum(act) == 0) continue
	CVk = round(rnormal(n, n, 0, 2))
	for (j = 1; j <= n; j++) CVk[j,j] = .
	(void) pl_dep(act, u, v, u :+ v, CVk, evraw, n)
}
end
di as text "  PASS: dependent effects found as by the reference (degree shares, covint = covsnd + covrec, constants, u_j + v_k); independent ones kept"
di "test_nwrem_plugin: ALL OK"
