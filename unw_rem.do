/*
 * Copyright (C) 2026 Thomas U. Grund
 * This file is part of nwrem, a Stata package derived from the R package 'relevent' (Carter T. Butts; GPL (>= 2)).
 * nwrem is free software: you can redistribute it and/or modify it under the terms of the GNU General
 * Public License, version 3, as published by the Free Software Foundation. It is distributed in the hope
 * that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
 * or FITNESS FOR A PARTICULAR PURPOSE. See the file LICENSE for the full text.
 */
/*
	unw_rem.do -- the Mata glue of nwrem (relational event models; Butts, C.T. (2008). "A Relational Event Framework for
	Social Action." Sociological Methodology, 38(1), 155-200).

	Every fit runs in the compiled plugin native/rem_sim.c (the ordinal partial likelihood of all 14 effects with its gradient
	and exact Hessian). This file sorts the events, writes the model into the plugin's data frame (class RemNat), looks for
	effects that are exactly dependent on others (one plugin call at theta = 0), runs a damped Newton iteration on the exact
	Hessian (Mata's optimize() as the fall-back) and returns the estimates to nwrem.ado. There is no Mata fall-back for the
	likelihood: when the plugin is missing or too old the command stops (r(601), r(3495)).

	The Mata evaluators of the earlier versions (dense likelihood, fast evaluator, dependence check) are reference code of the
	test suite only: cscripts/ref_rem_mata.do. The plugin is tested against them.

	Sourced live during development (`do unw_rem.do`) and compiled into lib/lnwrem.mlib by lib/build.do (Stata 17).
*/

capture mata: mata drop rem_node_rows()
capture mata: mata drop RemNativePluginFilename()
capture mata: mata drop RemNativePluginSubdir()
capture mata: mata drop RemNativePluginPath()
capture mata: mata drop RemNativeAvailable()
capture mata: mata drop RemNat()
capture mata: mata drop REM_PROTOCOL_NEEDED()
capture mata: mata drop rem_sorted_events()
capture mata: mata drop rem_nat_eval()
capture mata: mata drop rem_nat_eval_d1()
capture mata: mata drop rem_newton()
capture mata: mata drop rem_nat_dependent()
capture mata: mata drop rem_nat_dependent_par()
capture mata: mata drop rem_nat_prior()
capture mata: mata drop rem_event_dt()
capture mata: mata drop RemFitX()
capture mata: mata drop rem_nat_optimize()
capture mata: mata drop RemFitMulti()

mata:
mata set matastrict off

/*
	rem_node_rows(): for every node name, its row in the label column lab of the data (0 when absent, -1 when the label
	occurs more than once). Used by nwrem.ado to match per-actor covariates to the actors by label.
*/
real colvector rem_node_rows(string rowvector names, string colvector lab)
{
	transmorphic A
	real colvector pos
	real scalar k

	A = asarray_create("string", 1)
	for (k = 1; k <= rows(lab); k++) {
		if (asarray_contains(A, lab[k])) asarray(A, lab[k], -1)
		else asarray(A, lab[k], k)
	}
	pos = J(cols(names), 1, 0)
	for (k = 1; k <= cols(names); k++) {
		if (asarray_contains(A, names[k])) pos[k] = asarray(A, names[k])
	}
	return(pos)
}

/*
	Plugin lookup. Two strategies, tried in order: (1) findfile() on the platform-specific file name alone, which is what finds
	the plugin after a real `net install` (net install flattens every file of a package into PLUS/<first letter>/); (2) the path
	lib/plugins/<os>/<name> relative to nwrem.ado, for a checkout of the repository on the adopath.
*/
string scalar RemNativePluginFilename()
{
	string scalar os

	os = st_global("c(os)")
	// console Stata on macOS reports c(os) = "Unix"; c(machine_type) still starts with "Mac"
	if (os == "Unix" & substr(st_global("c(machine_type)"), 1, 3) == "Mac") os = "MacOSX"
	if (os == "Windows") return("rem_sim_windows.plugin")
	if (os == "Unix") return("rem_sim_unix.plugin")
	return("rem_sim_macos.plugin")
}

string scalar RemNativePluginSubdir()
{
	string scalar os

	os = st_global("c(os)")
	// console Stata on macOS reports c(os) = "Unix"; c(machine_type) still starts with "Mac"
	if (os == "Unix" & substr(st_global("c(machine_type)"), 1, 3) == "Mac") os = "MacOSX"
	if (os == "Windows") return("windows")
	if (os == "Unix") return("unix")
	return("macos")
}

string scalar RemNativePluginPath()
{
	string scalar fname, found, full, dir, fn

	fname = RemNativePluginFilename()
	found = findfile(fname)
	if (found != "") return(found)

	full = findfile("nwrem.ado")
	if (full == "") return("")
	pathsplit(full, dir, fn)
	return(pathjoin(pathjoin(dir, "lib"), pathjoin("plugins", pathjoin(RemNativePluginSubdir(), fname))))
}

real scalar RemNativeAvailable()
{
	string scalar p

	p = RemNativePluginPath()
	if (p == "") return(0)
	return(fileexists(p))
}

real scalar REM_PROTOCOL_NEEDED() return(2)

/*
	The events sorted by time. Events with the SAME time keep the order in which the network lists them (the row number is the
	second sort key): the likelihood is ordinal, so the order within a tie is part of the data. Self-loops are refused:
	relational event models are defined over i != j dyads only.
*/
real matrix rem_sorted_events(real matrix rawevents)
{
	real colvector ord, bad
	real scalar k

	bad = selectindex(rawevents[., 1] :== rawevents[., 2])
	if (rows(bad) > 0) {
		k = bad[1]
		// the message goes through errprintf(): _error() fails with r(3300) on texts longer than about 110 characters
		errprintf("{p 0 0 2}nwrem: event %s has sender == receiver (self-loop); relational event models are defined over i != j dyads only.{p_end}\n", strofreal(k))
		exit(3498)
	}
	ord = order((rawevents[., 3], (1::rows(rawevents))), (1, 2))
	return(rawevents[ord, .])
}

/*
	NATIVE ENGINE. class RemNat writes the model (events, covariates, risk set) once per fit into the frame __nwrem_native
	(variable v1, the "blob"; layout in the header of native/rem_sim.c); rem_nat_eval() is the evaluator: one plugin call per
	evaluation, only theta travels (at full double precision), the result (log likelihood, gradient, Hessian) comes back in v2.
	The plugin must exist and speak the protocol of this package (RemNat::open() asks it with code 99):
	  r(601)  the plugin file for this platform is not installed
	  r(3495) the installed plugin is too old for this version of nwrem (or cannot be loaded)
*/
class RemNat {
	real scalar L        // length of the blob
	real scalar Pt       // number of parameters of the model now in the blob
	real scalar Pall     // number of parameters of the full model (before the dependent ones are dropped)
	real scalar isopen
	real scalar prior    // 1 = posterior mode: the t (or normal) prior of relevent is added to the log likelihood
	real scalar pmean, pscale, pdf
	real colvector blob0 // the blob without a drop mask
	real scalar cached   // 1 = the evaluation at theta = 0 of the dependence check is kept (cy, cg, cH, ckeep)
	real scalar cy
	real rowvector cg, ckeep
	real matrix cH
	string scalar origframe

	void open()
	void close()
	void setup()
	void setupx()
	void setdrop()
}

void RemNat::open()
{
	string scalar p, fname, q
	real scalar rc, junk, ver

	isopen = 0
	prior = 0
	cached = 0
	fname = RemNativePluginFilename()
	p = RemNativePluginPath()
	if (p == "" | !fileexists(p)) {
		errprintf("{p 0 0 2}nwrem: the compiled plugin {bf:%s} was not found. nwrem fits every model with this plugin and has no Mata fallback; reinstall the package with {bf:net install nwrem, replace}.{p_end}\n", fname)
		exit(601)
	}
	origframe = st_framecurrent()
	stata("capture frame drop __nwrem_native")
	stata("frame create __nwrem_native")
	st_framecurrent("__nwrem_native")
	isopen = 1
	st_addobs(4)
	junk = st_addvar("double", "v1")
	junk = st_addvar("double", "v2")
	q = char(34)
	stata("capture program drop remnative")
	stata("capture program remnative, plugin using(" + q + p + q + ")")
	rc = _stata("plugin call remnative v1 v2, " + q + "99 0 0 0 0 0 0" + q, 1)
	ver = .
	if (rc == 0) ver = st_data(1, 2)
	if (rc != 0 | ver != REM_PROTOCOL_NEEDED()) {
		close()
		errprintf("{p 0 0 2}nwrem: the installed plugin {bf:%s} is too old for this version of nwrem (or it cannot be loaded). Reinstall the package with {bf:net install nwrem, replace}.{p_end}\n", fname)
		exit(3495)
	}
}

void RemNat::close()
{
	if (isopen) {
		st_framecurrent(origframe)
		stata("capture frame drop __nwrem_native")
		isopen = 0
	}
}

/*
	setupx(): ev = sorted events (sender, receiver, time since the previous event), n actors, active = 1 x 27 flags (the
	flags of the covariate effects 9 to 12 must agree with the number of columns of CS, CR, CI, CE), mode 0 = ordinal
	likelihood, 1 = interval likelihood, ncond = number of conditioned events, dtc = length of the final (censored) interval,
	CS, CR, CI = one covariate per row (n columns), CE = n x (n * number of covariate networks) (the diagonal is not part of
	the risk set and is set to 0), mask = n x n 0/1 matrix of the dyads that can occur (J(0,0,.) = all), win = 2 x n first
	and last event number at which an actor is in the risk set (J(0,0,.) = always).
*/
void RemNat::setupx(real matrix ev, real scalar n, real rowvector active, real scalar mode, real scalar ncond,
		real scalar dtc, real matrix CS, real matrix CR, real matrix CI, real matrix CE, real matrix mask, real matrix win)
{
	real scalar nev, k, ncs, ncr, nci, nce, c, need
	real rowvector hdr
	real matrix Cz

	nev = rows(ev)
	ncs = rows(CS)
	ncr = rows(CR)
	nci = rows(CI)
	nce = (rows(CE) == n ? cols(CE) / n : 0)
	hdr = J(1, 48, 0)
	hdr[1] = REM_PROTOCOL_NEEDED()
	hdr[2] = n
	hdr[3] = nev
	hdr[4] = mode
	hdr[5] = ncond
	hdr[6] = dtc
	hdr[7] = ncs
	hdr[8] = ncr
	hdr[9] = nci
	hdr[10] = nce
	hdr[11] = (rows(mask) > 0)
	hdr[12] = (rows(win) > 0)
	hdr[13] = 0
	hdr[17..43] = active
	blob0 = hdr' \ vec(ev[., (1, 2, 3)]')
	if (ncs > 0) blob0 = blob0 \ vec(CS')
	if (ncr > 0) blob0 = blob0 \ vec(CR')
	if (nci > 0) blob0 = blob0 \ vec(CI')
	for (c = 1; c <= nce; c++) {
		Cz = CE[., ((c - 1) * n + 1)..(c * n)]
		for (k = 1; k <= n; k++) Cz[k, k] = 0
		if (hasmissing(Cz)) {
			close()
			errprintf("{p 0 0 2}nwrem: covevent() has missing values.{p_end}\n")
			exit(416)
		}
		blob0 = blob0 \ vec(Cz')
	}
	if (rows(mask) > 0) blob0 = blob0 \ vec(mask')
	if (rows(win) > 0) blob0 = blob0 \ vec(win')
	blob = blob0
	L = rows(blob)
	Pall = sum(active[1..8]) + ncs * active[9] + ncr * active[10] + nci * active[11] + nce * active[12] + sum(active[13..18]) + (n - 1) * sum(active[19..21]) + sum(active[22..27])
	Pt = Pall
	need = max((L, 4 + 2 * Pall + Pall * Pall, 230))
	if (need > st_nobs()) st_addobs(need - st_nobs())
	st_store((1::L), 1, blob)
}

// the model of nwrem 1.3 (14 effects, one covariate per effect, ordinal likelihood, complete risk set)
void RemNat::setup(real matrix ev, real scalar n, real rowvector active, real rowvector cs, real rowvector cr,
		real rowvector ci, real matrix C)
{
	real matrix CS, CR, CI, CE
	real rowvector act27

	act27 = (active, J(1, 13, 0))
	CS = (active[9] ? cs : J(0, n, .))
	CR = (active[10] ? cr : J(0, n, .))
	CI = (active[11] ? ci : J(0, n, .))
	CE = (active[12] ? C : J(n, 0, .))
	setupx((ev[., (1, 2)], J(rows(ev), 1, 0)), n, act27, 0, 0, 0, CS, CR, CI, CE, J(0, 0, .), J(0, 0, .))
}

// leave the parameters with dropflag = 1 (a 1 x Pall vector) out of the model
void RemNat::setdrop(real rowvector dropall)
{
	real colvector b2

	ckeep = selectindex(dropall :== 0)
	b2 = blob0
	b2[13] = 1
	b2 = b2 \ dropall'
	L = rows(b2)
	Pt = Pall - sum(dropall)
	if (L > st_nobs()) st_addobs(L - st_nobs())
	st_store((1::L), 1, b2)
}

/*
	The prior of posterior-mode estimation (relevent's fit.method = "BPM"): independent t distributions with df degrees of
	freedom (a normal distribution when df is missing), location mean and scale scale for every coefficient. Returns the log
	density summed over theta and adds its gradient and Hessian (diagonal) to g and H.
*/
real scalar rem_nat_prior(pointer(class RemNat scalar) scalar pN, real rowvector theta, real scalar todo,
		real rowvector g, real matrix H)
{
	real rowvector z
	real scalar nu, sc, v, k

	nu = (*pN).pdf
	sc = (*pN).pscale
	z = (theta :- (*pN).pmean) :/ sc
	k = cols(theta)
	if (missing(nu)) {
		v = -0.5 * k * ln(2 * pi()) - 0.5 * sum(z :^ 2) - k * ln(sc)
		if (todo >= 1) g = g - z / sc
		if (todo >= 2) H = H - I(k) / sc^2
	}
	else {
		v = k * (lngamma((nu + 1) / 2) - lngamma(nu / 2) - 0.5 * ln(nu * pi()) - ln(sc)) - (nu + 1) / 2 * sum(ln(1 :+ z :^ 2 / nu))
		if (todo >= 1) g = g - ((nu + 1) :* z :/ (nu :+ z :^ 2)) / sc
		if (todo >= 2) H = H - diag(((nu + 1) :* (nu :- z :^ 2) :/ (nu :+ z :^ 2) :^ 2) / sc^2)
	}
	return(v)
}

void rem_nat_eval(real scalar todo, real rowvector theta, pointer(class RemNat scalar) scalar pN,
		real scalar y, real rowvector g, real matrix H)
{
	real scalar k, pt
	string scalar argstr
	real colvector res

	pt = (*pN).Pt
	argstr = "20 " + strofreal((*pN).L, "%18.0f") + " " + strofreal(min((todo, 2))) + " " + strofreal(pt)
	for (k = 1; k <= pt; k++) argstr = argstr + " " + strofreal(theta[k], "%25.17g")
	stata("plugin call remnative v1 v2, " + char(34) + argstr + char(34))
	res = st_data((1::(1 + pt + (todo >= 2 ? pt * pt : 0))), 2)
	y = res[1]
	if (missing(y)) {
		if (todo >= 1) g = J(1, pt, .)
		if (todo >= 2) H = J(pt, pt, .)
		return
	}
	if (todo >= 1) g = res[2::(1 + pt)]'
	if (todo >= 2) H = rowshape(res[(2 + pt)::(1 + pt + pt * pt)], pt)
	if ((*pN).prior) y = y + rem_nat_prior(pN, theta, todo, g, H)
}

void rem_nat_eval_d1(real scalar todo, real rowvector theta, pointer(class RemNat scalar) scalar pN,
		real scalar y, real rowvector g, real matrix H)
{
	rem_nat_eval(min((todo, 1)), theta, pN, y, g, H)
}

/*
	Newton-Raphson on the concave log likelihood (the statistics do not depend on theta, so the partial log likelihood is a sum
	of log-sum-exp functions of a linear form) with the plugin's exact gradient and Hessian. optimize()'s own "nr" technique
	meets its tolerances only a few digits before the maximum and then keeps backing up at round-off level, which cost up to a
	thousand evaluations on dense data. Damped Newton steps (a full step, halved until the log likelihood does not fall), judged
	by the Newton decrement g' (-H)^-1 g, bring the gradient to round-off level. ok = 1 when a result was found; theta_hat, V
	(the inverse of minus the Hessian: the observed information) and ll are then set.
*/
void rem_newton(pointer(class RemNat scalar) scalar pN, real rowvector theta0,
		real rowvector theta_hat, real matrix V, real scalar ll, real scalar ok)
{
	real rowvector t, tn, g, gn, d
	real matrix H, Hn, Hi
	real scalar y, yn, it, k, step, dec, good, polish

	ok = 0
	polish = 1
	t = theta0
	if ((*pN).cached & !any(theta0)) {
		// the evaluation at theta = 0 was done by the dependence check
		y = (*pN).cy
		g = (*pN).cg[(*pN).ckeep]
		H = (*pN).cH[(*pN).ckeep, (*pN).ckeep]
		if ((*pN).prior) y = y + rem_nat_prior(pN, t, 2, g, H)
	}
	else rem_nat_eval(2, t, pN, y, g, H)
	if (missing(y) | missing(g) | missing(H)) return
	good = 0
	for (it = 1; it <= 100; it++) {
		Hi = invsym(-H)
		if (min(diagonal(Hi)) <= 0) return
		d = g * Hi
		dec = d * g'
		if (dec < max((1e-12, 1e-13 * abs(y)))) {
			good = 1
			polish = (dec > 1e-10)
			break
		}
		step = 1
		for (k = 1; k <= 30; k++) {
			tn = t + step * d
			rem_nat_eval(2, tn, pN, yn, gn, Hn)
			if (!missing(yn) & !missing(gn) & !missing(Hn)) {
				if (yn >= y) break
			}
			step = step / 2
		}
		if (k > 30) {
			// no step raises the log likelihood: only round-off is left when the decrement is already tiny
			good = (dec < 1e-8)
			break
		}
		t = tn
		y = yn
		g = gn
		H = Hn
	}
	if (!good) return
	// bring the gradient to round-off level: steps are taken while they reduce its norm (not needed when the Newton
	// decrement is already at round-off level)
	for (it = 1; it <= 5 & polish; it++) {
		tn = t + g * invsym(-H)
		rem_nat_eval(2, tn, pN, yn, gn, Hn)
		if (missing(yn) | missing(gn) | missing(Hn)) break
		if (sqrt(gn * gn') >= sqrt(g * g')) break
		t = tn
		y = yn
		g = gn
		H = Hn
	}
	V = invsym(-H)
	if (min(diagonal(V)) <= 0) return
	theta_hat = t
	ll = y
	ok = 1
}

/*
	Which parameters are an exact linear function of the parameters before them (in the fixed parameter order) plus a term that
	is constant over the risk set of every event? Such a parameter cannot change the likelihood (the term cancels in the
	softmax) and the optimizer would only wander along the flat ridge. Returns a 1 x Pall 0/1 vector. The plugin (code 30)
	evaluates every parameter at theta = 0: minus its Hessian is the Gram matrix of the statistics centred within every risk
	set, summed over the events (for the interval likelihood: the uncentred second moments), and it also returns the uncentred
	second moments of the ordinal likelihood. A parameter is dependent when what is left of its centred sum of squares after
	the parameters before it is below 1e-12 of its uncentred one (rounding of exactly collinear statistics is about 1e-16).
	This holds for the state-dependent dyadic effects as well: a combination whose Gram quadratic form is zero is constant over
	the risk set at every event.
*/
real rowvector rem_nat_dependent_par(pointer(class RemNat scalar) scalar pN, real scalar interval)
{
	real rowvector dropped
	real colvector kept, res
	real matrix G
	real scalar k, p, r, tol, off, ref
	string scalar argstr

	k = (*pN).Pall
	dropped = J(1, k, 0)
	if (k == 0) return(dropped)
	argstr = "30 " + strofreal((*pN).L, "%18.0f") + " 2 " + strofreal(k) + " " + invtokens(J(1, k, "0"))
	stata("plugin call remnative v1 v2, " + char(34) + argstr + char(34))
	res = st_data((1::(2 + k + k * k + k)), 2)
	if (missing(res[1])) return(dropped)
	G = -rowshape(res[(2 + k)::(1 + k + k * k)], k)
	if (hasmissing(G)) return(dropped)
	// the evaluation at theta = 0 (likelihood, gradient, Hessian) is the first Newton step and the null model of the ordinal likelihood
	(*pN).cy = res[1]
	(*pN).cg = res[2::(1 + k)]'
	(*pN).cH = -G
	(*pN).cached = 1
	off = 1 + k + k * k          // the uncentred second moments follow the Hessian
	tol = 1e-12
	kept = J(0, 1, 0)
	for (p = 1; p <= k; p++) {
		if (rows(kept) == 0) r = G[p, p]
		else r = G[p, p] - G[p, kept'] * lusolve(G[kept, kept'], G[kept', p])
		ref = (interval ? G[p, p] : res[off + p])
		if (hasmissing(r) | r <= tol * ref) dropped[p] = 1
		else kept = (kept \ p)
	}
	return(dropped)
}

// the check for the model of nwrem 1.3 (one parameter per effect): a 1 x 14 vector
real rowvector rem_nat_dependent(pointer(class RemNat scalar) scalar pN, real rowvector active)
{
	real rowvector dropped, dp

	dropped = J(1, 14, 0)
	if (sum(active) == 0) return(dropped)
	dp = rem_nat_dependent_par(pN, 0)
	dropped[selectindex(active)] = dp
	return(dropped)
}

/*
	Maximisation on the native evaluator: Newton-Raphson from 0; when it is not accepted (no maximum, effects that are not
	identified) up to 8 starts of BFGS with the analytic Hessian (the first converged start wins, then Newton polishes it),
	Nelder-Mead as the last resort. Fills theta_hat, V, ll; returns 0 when nothing worked.
*/
real scalar rem_nat_optimize(pointer(class RemNat scalar) scalar pN, real rowvector theta_hat, real matrix V, real scalar ll)
{
	transmorphic S_opt
	real rowvector theta0, th2
	real matrix starts, V2
	real scalar nparams, nstarts, attempt, ok, errcode, nrok, ll2

	nparams = (*pN).Pt
	nstarts = 8
	rem_newton(pN, J(1, nparams, 0), theta_hat, V, ll, nrok)
	if (nrok) return(1)
	starts = J(nstarts, nparams, 0)
	for (attempt = 1; attempt <= nstarts; attempt++) {
		starts[attempt, .] = (runiform(1, nparams) :- 0.5) :* (0.15 * (mod(attempt - 1, nstarts) + 1))
	}
	// the first start is fixed, so that a fit without seed() is reproducible
	starts[1, .] = J(1, nparams, 0.01)
	ok = 0
	for (attempt = 1; attempt <= nstarts & ok == 0; attempt++) {
		theta0 = starts[attempt, .]
		S_opt = optimize_init()
		optimize_init_evaluator(S_opt, &rem_nat_eval())
		optimize_init_evaluatortype(S_opt, "d2")
		optimize_init_params(S_opt, theta0)
		optimize_init_argument(S_opt, 1, pN)
		optimize_init_technique(S_opt, "bfgs")
		optimize_init_which(S_opt, "max")
		optimize_init_tracelevel(S_opt, "none")
		optimize_init_conv_warning(S_opt, "off")
		optimize_init_conv_maxiter(S_opt, 60)
		errcode = _optimize(S_opt)
		if (errcode == 0) {
			theta_hat = optimize_result_params(S_opt)
			V = optimize_result_V_oim(S_opt)
			ll = optimize_result_value(S_opt)
			ok = 1
		}
	}
	if (ok) {
		// Newton-Raphson on the analytic Hessian from the BFGS result brings the gradient to round-off level (BFGS stops at
		// its default tolerances); the BFGS result stays when Newton does not accept
		rem_newton(pN, theta_hat, th2, V2, ll2, nrok)
		if (nrok) {
			theta_hat = th2
			V = V2
			ll = ll2
		}
		return(1)
	}
	S_opt = optimize_init()
	optimize_init_evaluator(S_opt, &rem_nat_eval_d1())
	optimize_init_evaluatortype(S_opt, "d1")
	optimize_init_params(S_opt, J(1, nparams, 0.01))
	optimize_init_argument(S_opt, 1, pN)
	optimize_init_technique(S_opt, "nm")
	optimize_init_which(S_opt, "max")
	optimize_init_tracelevel(S_opt, "none")
	optimize_init_conv_warning(S_opt, "off")
	optimize_init_conv_maxiter(S_opt, 300)
	errcode = _optimize(S_opt)
	theta_hat = optimize_result_params(S_opt)
	if (errcode != 0 & errcode != 430) return(0)
	if (missing(theta_hat)) return(0)
	V = optimize_result_V_oim(S_opt)
	ll = optimize_result_value(S_opt)
	return(1)
}

// the time since the previous event of every event of the sorted event matrix (the first: since the start of the observation)
real colvector rem_event_dt(real matrix ev, real scalar start)
{
	if (rows(ev) == 1) return(ev[1, 3] - start)
	return(ev[., 3] :- (start \ ev[|1, 3 \ rows(ev) - 1, 3|]))
}

/*
	RemFitX() -- fit of nwrem 1.4. eventmat = (sender, receiver, time) rows, n actors, active = 27 0/1 flags in the order of the
	effects (nodsnd nidrec nidsnd nodrec ntdegsnd ntdegrec frpsndsnd frrecsnd covsnd covrec covint covevent rsndsnd rrecsnd
	otpsnd itpsnd ospsnd ispsnd fesnd ferec feint psabba psabby psabxa psabxb psabxy psabay); CS, CR, CI = one covariate per
	row (n columns; J(0, n, .) for none), CE = n x (n * networks) pairwise covariates; mask = n x n 0/1 matrix of the dyads in
	the risk set (J(0, 0, .) = all), entry, exit = n x 1 times at which an actor enters and leaves the risk set (J(0, 1, .) =
	always; a missing value = no limit); opts = (interval, conditioned events, start of the observation, end of the
	observation (missing: the last event), posterior mode, prior mean, prior scale, prior degrees of freedom).
	Results go to the Stata matrices pfx+"b", pfx+"V" (Pall columns) and the scalars pfx+"ll", pfx+"ll0" (the log likelihood
	of the null model; missing when not defined), pfx+"df" (parameters in the model). Parameters that are exactly dependent on
	others (see rem_nat_dependent_par()) get coefficient 0 and variance 0; the likelihood is that of the model without them.
*/
void RemFitX(real matrix eventmat, real scalar n, real rowvector active,
		real matrix CS, real matrix CR, real matrix CI, real matrix CE, real matrix mask,
		real colvector entry, real colvector exit, real rowvector opts, string scalar pfx)
{
	class RemNat scalar NT
	real matrix ev, V, win, Vfull
	real rowvector dropped, bfull, theta_hat
	real colvector kp, tt, lo, hi, idx
	real scalar nparams, nev, ok, ll, ll0, interval, ncond, start, endt, dtc, k, c, y0, ntot
	real rowvector g0
	real matrix H0

	interval = opts[1]
	ncond = opts[2]
	start = opts[3]
	endt = opts[4]
	if (sum(active) == 0) _error("nwrem: at least one effect must be selected.")
	ev = rem_sorted_events(eventmat)
	nev = rows(ev)
	if (ncond < 0 | ncond >= nev | ncond != floor(ncond)) {
		errprintf("{p 0 0 2}nwrem: condition(%s) must be an integer between 0 and the number of events minus one (%s).{p_end}\n", strofreal(ncond), strofreal(nev - 1))
		exit(198)
	}
	tt = ev[., 3]
	dtc = 0
	if (interval) {
		if (nev > 1) if (min(tt[|2 \ nev|] :- tt[|1 \ nev - 1|]) <= 0) {
			errprintf("{p 0 0 2}nwrem: the interval likelihood needs strictly increasing event times; events %s have equal times.{p_end}\n", "at the same time")
			exit(459)
		}
		if (start > tt[1]) {
			errprintf("{p 0 0 2}nwrem: starttime(%s) is later than the first event (%s).{p_end}\n", strofreal(start), strofreal(tt[1]))
			exit(459)
		}
		if (missing(endt)) endt = tt[nev]
		if (endt < tt[nev]) {
			errprintf("{p 0 0 2}nwrem: endtime(%s) is earlier than the last event (%s).{p_end}\n", strofreal(endt), strofreal(tt[nev]))
			exit(459)
		}
		dtc = endt - tt[nev]
		ev = (ev[., (1, 2)], rem_event_dt(ev, start))
	}
	else ev = (ev[., (1, 2)], J(nev, 1, 0))
	// the risk set: actor windows (first and last event number at which an actor is in the risk set) and dyad mask
	win = J(0, 0, .)
	if (rows(entry) > 0) {
		lo = J(n, 1, 1)
		hi = J(n, 1, nev + 1)
		for (k = 1; k <= n; k++) {
			if (!missing(entry[k])) {
				lo[k] = 1 + sum(tt :< entry[k])
				if (interval & dtc > 0 & entry[k] > endt) lo[k] = nev + 2
			}
			if (!missing(exit[k])) {
				hi[k] = sum(tt :<= exit[k])
				if (interval & dtc > 0 & exit[k] >= endt) hi[k] = nev + 1
			}
		}
		win = (lo, hi)'
		for (c = 1; c <= nev; c++) {
			if (c < lo[ev[c, 1]] | c > hi[ev[c, 1]] | c < lo[ev[c, 2]] | c > hi[ev[c, 2]]) {
				errprintf("{p 0 0 2}nwrem: event %s of the sorted event sequence involves an actor outside its entry() / exit() window.{p_end}\n", strofreal(c))
				exit(459)
			}
		}
	}
	if (rows(mask) > 0) {
		for (c = 1; c <= nev; c++) {
			if (mask[ev[c, 1], ev[c, 2]] == 0) {
				errprintf("{p 0 0 2}nwrem: event %s of the sorted event sequence is a dyad that is not in the risk set given by riskset().{p_end}\n", strofreal(c))
				exit(459)
			}
		}
	}
	NT = RemNat()
	NT.open()
	NT.setupx(ev, n, active, interval, ncond, dtc, CS, CR, CI, CE, mask, win)
	NT.prior = opts[5]
	NT.pmean = opts[6]
	NT.pscale = opts[7]
	NT.pdf = opts[8]
	// the log likelihood of the null model: the ordinal likelihood at theta = 0 (the same probability for every dyad of
	// the risk set); the interval likelihood of relevent's constant-rate model for the complete risk set
	ll0 = .
	dropped = rem_nat_dependent_par(&NT, interval)
	if (!interval) {
		if (NT.cached) ll0 = NT.cy
		else {
			NT.prior = 0
			rem_nat_eval(0, J(1, NT.Pall, 0), &NT, y0, g0, H0)
			NT.prior = opts[5]
			ll0 = y0
		}
	}
	else if (rows(mask) == 0 & rows(entry) == 0) {
		ntot = nev
		ll0 = ln(ntot / (endt - start) / (n * (n - 1))) * (ntot - ncond) - ntot / (endt - start) * (ncond == 0 ? endt - start : endt - tt[ncond])
	}
	nparams = NT.Pall - sum(dropped)
	if (nparams == 0) {
		// no parameter with an influence on the likelihood: every dyad of every risk set has the same rate
		NT.close()
		st_matrix(pfx + "b", J(1, NT.Pall, 0))
		st_matrix(pfx + "V", J(NT.Pall, NT.Pall, 0))
		st_numscalar(pfx + "ll", ll0)
		st_numscalar(pfx + "ll0", ll0)
		st_numscalar(pfx + "df", 0)
		return
	}
	kp = selectindex(dropped :== 0)
	NT.setdrop(dropped)
	ok = rem_nat_optimize(&NT, theta_hat, V, ll)
	if (ok & NT.prior) {
		// the log likelihood at the posterior mode, without the prior
		NT.prior = 0
		rem_nat_eval(0, theta_hat, &NT, y0, g0, H0)
		ll = y0
	}
	NT.close()
	if (ok == 0) {
		errprintf("{p 0 0 2}nwrem: the optimization did not find a maximum of the likelihood.{p_end}\n")
		exit(430)
	}
	bfull = J(1, NT.Pall, 0)
	Vfull = J(NT.Pall, NT.Pall, 0)
	bfull[kp] = theta_hat
	Vfull[kp, kp] = V
	st_matrix(pfx + "b", bfull)
	st_matrix(pfx + "V", Vfull)
	st_numscalar(pfx + "ll", ll)
	st_numscalar(pfx + "ll0", ll0)
	st_numscalar(pfx + "df", nparams)
}

/*
	RemFitMulti() -- fit of nwrem 1.3 for any subset of the first 14 effects (the old interface; development scripts use it):
	eventmat = (sender, receiver, time) rows, n actors, activevec = 14 0/1 flags in the fixed effect order, covsndvec, covrecvec,
	covintvec = 1 x n per-actor covariates (J(1,n,0) for those not needed) and covevmat the n x n covevent matrix (J(n,n,0)
	when not needed). Coefficients, variance matrix and log likelihood are returned in the Stata matrices / scalar named bname,
	vname, llname.
*/
void RemFitMulti(real matrix eventmat, real scalar n, real rowvector activevec,
		real rowvector covsndvec, real rowvector covrecvec, real rowvector covintvec,
		real matrix covevmat,
		string scalar bname, string scalar vname, string scalar llname)
{
	RemFitX(eventmat, n, (activevec, J(1, 13, 0)),
		(activevec[9] ? covsndvec : J(0, n, .)), (activevec[10] ? covrecvec : J(0, n, .)), (activevec[11] ? covintvec : J(0, n, .)),
		(activevec[12] ? covevmat : J(n, 0, .)), J(0, 0, .), J(0, 1, .), J(0, 1, .), (0, 0, 0, ., 0, 0, 100, 4), "__nwrem_t_")
	st_matrix(bname, st_matrix("__nwrem_t_b"))
	st_matrix(vname, st_matrix("__nwrem_t_V"))
	st_numscalar(llname, st_numscalar("__nwrem_t_ll"))
	st_matrix("__nwrem_t_b", J(0, 0, .))
	st_matrix("__nwrem_t_V", J(0, 0, .))
	stata("capture matrix drop __nwrem_t_b")
	stata("capture matrix drop __nwrem_t_V")
	stata("capture scalar drop __nwrem_t_ll")
	stata("capture scalar drop __nwrem_t_ll0")
	stata("capture scalar drop __nwrem_t_df")
}

end
