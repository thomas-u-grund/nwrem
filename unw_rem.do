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
	if (os == "Windows") return("rem_sim_windows.plugin")
	if (os == "Unix") return("rem_sim_unix.plugin")
	return("rem_sim_macos.plugin")
}

string scalar RemNativePluginSubdir()
{
	string scalar os

	os = st_global("c(os)")
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

real scalar REM_PROTOCOL_NEEDED() return(1)

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
	NATIVE ENGINE. class RemNat writes the model (events, covariates) once per fit into the frame __nwrem_native (variable v1,
	the "blob"; layout in the header of native/rem_sim.c); rem_nat_eval() is the evaluator: one plugin call per evaluation,
	only theta travels (at full double precision), the result (log likelihood, gradient, Hessian) comes back in v2.
	The plugin must exist and speak the protocol of this package (RemNat::open() asks it with code 99):
	  r(601)  the plugin file for this platform is not installed
	  r(3495) the installed plugin is too old for this version of nwrem (or cannot be loaded)
*/
class RemNat {
	real scalar L        // length of the blob
	real scalar Pt       // number of parameters of the model now in the blob
	real scalar isopen
	string scalar origframe

	void open()
	void close()
	void setup()
	void setactive()
}

void RemNat::open()
{
	string scalar p, fname, q
	real scalar rc, junk, ver

	isopen = 0
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
	setup(): ev = sorted events (sender, receiver, ...), n actors, active = 1 x 14 flags, covariates (1 x n each) and the
	n x n matrix of covevent (the diagonal is not part of the risk set and is set to 0).
*/
void RemNat::setup(real matrix ev, real scalar n, real rowvector active, real rowvector cs, real rowvector cr,
		real rowvector ci, real matrix C)
{
	real scalar nev, k
	real colvector blob
	real rowvector hdr
	real matrix Cz

	nev = rows(ev)
	hdr = (REM_PROTOCOL_NEEDED(), n, nev, active, J(1, 7, 0))
	blob = hdr' \ vec(ev[., (1, 2)]') \ cs' \ cr' \ ci'
	if (active[12]) {
		Cz = C
		for (k = 1; k <= n; k++) Cz[k, k] = 0
		if (hasmissing(Cz)) {
			close()
			errprintf("{p 0 0 2}nwrem: covevent() has missing values.{p_end}\n")
			exit(416)
		}
		blob = blob \ vec(Cz')
	}
	L = rows(blob)
	Pt = sum(active)
	if (max((L, 230)) > st_nobs()) st_addobs(max((L, 230)) - st_nobs())
	st_store((1::L), 1, blob)
}

// the active flags of the model (header cells 4 to 17 of the blob)
void RemNat::setactive(real rowvector active)
{
	st_store((4::17), 1, active')
	Pt = sum(active)
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
	real scalar y, yn, it, k, step, dec, good

	ok = 0
	t = theta0
	rem_nat_eval(2, t, pN, y, g, H)
	if (missing(y) | missing(g) | missing(H)) return
	good = 0
	for (it = 1; it <= 100; it++) {
		Hi = invsym(-H)
		if (min(diagonal(Hi)) <= 0) return
		d = g * Hi
		dec = d * g'
		if (dec < max((1e-12, 1e-13 * abs(y)))) {
			good = 1
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
	// bring the gradient to round-off level: steps are taken while they reduce its norm
	for (it = 1; it <= 5; it++) {
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
	Which effects are an exact linear function of the effects before them (in the fixed effect order) plus a term that is
	constant over the risk set of every event? Such an effect cannot change the likelihood (the term cancels in the softmax)
	and the optimizer would only wander along the flat ridge. Returns a 1 x 14 0/1 vector. The plugin (code 30) evaluates the
	static effects (1-6, 9-12) at theta = 0: minus its Hessian is the Gram matrix of the statistics centred within every risk
	set, summed over the events, and it also returns the uncentred second moments. An effect is dependent when what is left of
	its centred sum of squares after the effects before it is below 1e-12 of its uncentred one (rounding of exactly collinear
	statistics is about 1e-16). The state-dependent dyadic effects (7, 8, 13, 14) are not examined.
*/
real rowvector rem_nat_dependent(pointer(class RemNat scalar) scalar pN, real rowvector active)
{
	real rowvector dropped, effs
	real colvector kept, res
	real matrix G
	real scalar k, p, r, tol, off
	string scalar argstr

	dropped = J(1, 14, 0)
	effs = select((1, 2, 3, 4, 5, 6, 9, 10, 11, 12), active[(1, 2, 3, 4, 5, 6, 9, 10, 11, 12)])
	k = cols(effs)
	if (k == 0) return(dropped)
	argstr = "30 " + strofreal((*pN).L, "%18.0f") + " 2 " + strofreal(k) + " " + invtokens(J(1, k, "0"))
	stata("plugin call remnative v1 v2, " + char(34) + argstr + char(34))
	res = st_data((1::(2 + k + k * k + k)), 2)
	if (missing(res)) return(dropped)
	G = -rowshape(res[(2 + k)::(1 + k + k * k)], k)
	off = 1 + k + k * k          // the uncentred second moments follow the Hessian
	tol = 1e-12
	kept = J(0, 1, 0)
	for (p = 1; p <= k; p++) {
		if (rows(kept) == 0) r = G[p, p]
		else r = G[p, p] - G[p, kept'] * lusolve(G[kept, kept'], G[kept', p])
		if (hasmissing(r) | r <= tol * res[off + p]) dropped[effs[p]] = 1
		else kept = (kept \ p)
	}
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

/*
	RemFitMulti() -- fit for any subset of the 14 effects. eventmat = (sender, receiver, time) rows, n actors, activevec = 14
	0/1 flags in the fixed effect order (nodsnd nidrec nidsnd nodrec ntdegsnd ntdegrec frpsndsnd frrecsnd covsnd covrec covint
	covevent rsndsnd rrecsnd); covsndvec, covrecvec, covintvec = 1 x n per-actor covariates (J(1,n,0) for those not needed) and
	covevmat the n x n covevent matrix (J(n,n,0) when not needed). Coefficients, variance matrix and log likelihood are
	returned in the Stata matrices / scalar named bname, vname, llname. Effects that are exactly dependent on others (see
	rem_nat_dependent()) get coefficient 0 and variance 0; the likelihood is that of the model without them.
*/
void RemFitMulti(real matrix eventmat, real scalar n, real rowvector activevec,
		real rowvector covsndvec, real rowvector covrecvec, real rowvector covintvec,
		real matrix covevmat,
		string scalar bname, string scalar vname, string scalar llname)
{
	class RemNat scalar NT
	real matrix ev, V
	real rowvector dropped, actred, bfull, theta_hat
	real colvector kp
	real matrix Vfull
	real scalar nparams, nfull, nev, ok, ll

	nfull = sum(activevec)
	if (nfull == 0) _error("nwrem: at least one effect must be selected.")
	ev = rem_sorted_events(eventmat)
	nev = rows(ev)

	NT = RemNat()
	NT.open()
	NT.setup(ev, n, activevec, covsndvec, covrecvec, covintvec, covevmat)
	dropped = rem_nat_dependent(&NT, activevec)
	actred = activevec :* (1 :- dropped)
	nparams = sum(actred)
	kp = selectindex(dropped[selectindex(activevec)] :== 0)
	if (nparams == 0) {
		// no effect with an influence on the likelihood: every dyad of every risk set has the same rate
		NT.close()
		st_matrix(bname, J(1, nfull, 0))
		st_matrix(vname, J(nfull, nfull, 0))
		st_numscalar(llname, -nev * ln(n * (n - 1)))
		return
	}
	NT.setactive(actred)
	ok = rem_nat_optimize(&NT, theta_hat, V, ll)
	NT.close()
	if (ok == 0) {
		errprintf("{p 0 0 2}nwrem: the optimization did not find a maximum of the likelihood.{p_end}\n")
		exit(430)
	}
	bfull = J(1, nfull, 0)
	Vfull = J(nfull, nfull, 0)
	bfull[kp] = theta_hat
	Vfull[kp, kp] = V
	st_matrix(bname, bfull)
	st_matrix(vname, Vfull)
	st_numscalar(llname, ll)
}

end
