/*
 * Copyright (C) 2026 Thomas U. Grund
 * This file is part of nwrem, a Stata package derived from the R package 'relevent' (Carter T. Butts; GPL (>= 2)).
 * nwrem is free software: you can redistribute it and/or modify it under the terms of the GNU General
 * Public License, version 3, as published by the Free Software Foundation. It is distributed in the hope
 * that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
 * or FITNESS FOR A PARTICULAR PURPOSE. See the file LICENSE for the full text.
 */
/*
	ref_rem_mata.do -- REFERENCE evaluators of the nwrem test suite (not part of the package).

	The Mata evaluators of nwrem up to version 1.2.0: the dense likelihood and gradient (rem_loglik_grad_multi: an n x n softmax
	per event, the definition of the likelihood; agrees with R's relevent), the fast evaluator of 1.2.0 (rem_loglik_grad_fast,
	sums over senders and receivers), the check for exactly dependent effects (rem_dependent_effects) and the unit-1 fit
	(RemFitUnit1). nwrem itself fits every model in the compiled plugin native/rem_sim.c and has no Mata fall-back; the tests
	compare the plugin with these functions. Load after unw_rem.do:   do cscripts/ref_rem_mata.do
*/
capture mata: mata drop RemState()
capture mata: mata drop RemFitUnit1()
capture mata: mata drop rem_loglik_unit1()
capture mata: mata drop rem_eval_unit1()
capture mata: mata drop RemDyn()
capture mata: mata drop rem_fast_prep()
capture mata: mata drop rem_fast_deg()
capture mata: mata drop rem_fast_usable()
capture mata: mata drop rem_sumexcl()
capture mata: mata drop rem_loglik_grad_fast()
capture mata: mata drop rem_loglik_grad_auto()
capture mata: mata drop rem_dependent_effects()
capture mata: mata drop rem_rank_reciprocal()
capture mata: mata drop rem_loglik_grad_unit1()
capture mata: mata drop rem_loglik_grad_multi()
capture mata: mata drop rem_loglik_multi()

mata:
mata set matastrict off

class RemState {
	real matrix events     // nevents x 3: (sender, receiver, time), SORTED ascending by time
	real scalar n          // number of actors
	real scalar nevents
	real matrix cumindeg   // nevents x n
	real matrix cumoutdeg  // nevents x n
	real colvector ODs, ODr, IDs, IDr, TDs, TDr   // degree shares of the realized sender / receiver at every event (rem_fast_prep())
	real scalar chunkcells // events per block of the fast evaluator: about this many cells (missing: 1.5e6; the tests set small values)
	real scalar fast       // 1: rem_loglik_grad_auto() tries the fast evaluator first (set by RemFitMulti())

	void init()
	void build_degree_accumulators()
}

void RemState::init(real matrix rawevents, real scalar nn) {
	real colvector ord
	real scalar k

	// REM's risk set is defined over i!=j dyads by convention (matching
	// relevent's own "selfloops are not permitted" - see
	// the development notes) - reject rather than silently drop, since a
	// silently-dropped self-loop event would change nevents without
	// the caller necessarily noticing.
	for (k=1; k<=rows(rawevents); k++) {
		if (rawevents[k,1] == rawevents[k,2]) {
			// the message goes through errprintf(): _error() fails with r(3300) on texts longer than about 110 characters
			errprintf("{p 0 0 2}nwrem: event %s has sender == receiver (self-loop); relational event models are defined over i != j dyads only.{p_end}\n", strofreal(k))
			exit(3498)
		}
	}

	n = nn
	// get_eventlist() makes no ordering guarantee (confirmed by reading
	// unw_core.do's own nwattime_slice_event(), which scans unordered) -
	// the ordinal partial likelihood requires chronological order.
	// Events with the SAME time keep the order in which the network lists them: order() on the time column alone breaks
	// ties arbitrarily (it depends on the state of the random-number generator), so the same data gave different risk sets
	// and a different likelihood from run to run. The row number as second key makes the sort stable.
	ord = order((rawevents[.,3], (1::rows(rawevents))), (1, 2))
	events = rawevents[ord,.]
	nevents = rows(events)
}

void RemState::build_degree_accumulators() {
	real scalar i, s, r
	cumindeg = J(nevents, n, 0)
	cumoutdeg = J(nevents, n, 0)
	for (i=2; i<=nevents; i++) {
		cumindeg[i,.] = cumindeg[i-1,.]
		cumoutdeg[i,.] = cumoutdeg[i-1,.]
		s = events[i-1,1]
		r = events[i-1,2]
		cumoutdeg[i,s] = cumoutdeg[i,s] + 1
		cumindeg[i,r] = cumindeg[i,r] + 1
	}
}

/*
	Unit 1 ordinal partial log-likelihood: NODSnd (sender's normalized
	out-degree) + NIDRec (receiver's normalized in-degree). theta =
	(theta_nodsnd, theta_nidrec) -- NO intercept term: an intercept is
	constant across the entire risk set at every event and cancels out
	exactly in the softmax normalizer below, exactly like Cox
	proportional-hazards models have no identifiable baseline-hazard
	intercept in their own partial likelihood. Found empirically while
	testing this exact function (optimize() reported "flat region
	encountered" for an intercept parameter; direct likelihood
	evaluation confirmed zero sensitivity to it) - see
	the development notes section 1b for the full account, including why
	this also explains why none of relevent's own 24 named effects is a
	generic intercept.

	For event i with realized sender s, receiver r:
	  ll_i = lrm[s,r] - log( sum over all (j,k), j!=k, of exp(lrm[j,k]) )
	where lrm[j,k] = theta_nodsnd*NODSnd_j(i) + theta_nidrec*NIDRec_k(i)
	-- the standard Cox-style partial likelihood (see
	the development notes section 2), verified against relevent's own
	drem_n2llik_R() structure (read to confirm, not copied).

	First-event convention (i=1, no prior events): NODSnd/NIDRec both
	defined as 1/(n-1) for every actor, exactly matching relevent's own
	explicit fallback for this case (see the development notes section 3a
	- corrected there too after this project's own earlier reading of
	a partial source excerpt wrongly concluded this was left undefined).

	Analytic gradient (implemented alongside the likelihood, not
	deferred as originally planned in the development notes section 5 -
	brought forward after observing wide estimate-to-estimate variance
	under numerical-gradient BFGS during unit-1's own simulate-then-
	recover testing; the analytic score is the standard multinomial-
	logit/Cox-partial-likelihood form: for each event, the realized
	dyad's own effect value minus its expectation under the risk set's
	own softmax distribution P):

	  d ll_i / d theta_nodsnd = NODSnd_s(i) - sum_j NODSnd_j(i) * P(j sends)
	  d ll_i / d theta_nidrec = NIDRec_r(i) - sum_k NIDRec_k(i) * P(k receives)

	where P(j sends) = rowsum of P over receivers, P(k receives) =
	colsum of P over senders - P itself being lrm's own softmax
	(exactly the same normalization the log-likelihood already
	computes, so both are produced together in one pass over events
	rather than recomputed separately).
*/
void rem_loglik_grad_unit1(real rowvector theta, pointer(class RemState scalar) scalar pS,
		real scalar ll, real rowvector grad) {
	real scalar i, s, r, priorn, mx, lrsum, j, n
	real rowvector nodsnd_i, nidrec_i
	real matrix lrm, P

	n = (*pS).n
	ll = 0
	grad = J(1, 2, 0)
	for (i=1; i<=(*pS).nevents; i++) {
		s = (*pS).events[i,1]
		r = (*pS).events[i,2]
		priorn = i - 1

		if (priorn == 0) {
			// CORRECTION (found on closer reading of relevent's C
			// source while implementing units 2/5): relevent does NOT
			// leave the first event as undefined 0/0, as this
			// project's own earlier read of a partial excerpt of
			// lambda() wrongly concluded (the development notes section
			// 3a's original text) - the full switch case has an
			// explicit `if(it>0){...}else{dv[j]=1.0/(nv-1.0)}` branch.
			// Matched exactly here now that the correct formula is
			// known, rather than keeping a knowingly-divergent choice
			// that was only ever motivated by a mistaken belief that
			// relevent's own behavior was undefined.
			nodsnd_i = J(1, n, 1 :/ (n - 1))
			nidrec_i = J(1, n, 1 :/ (n - 1))
		}
		else {
			nodsnd_i = (*pS).cumoutdeg[i,.] :/ priorn
			nidrec_i = (*pS).cumindeg[i,.] :/ priorn
		}

		// Mata's :+ does NOT broadcast an n x 1 column against a 1 x n
		// row into an outer-sum n x n matrix (unlike NumPy/R) -
		// replicate explicitly via matrix multiplication by a
		// conformable ones-vector instead, which is always
		// well-defined regardless of broadcast semantics.
		lrm = (theta[1] :* nodsnd_i') * J(1, n, 1) :+ J(n, 1, 1) * (theta[2] :* nidrec_i)
		for (j=1; j<=n; j++) lrm[j,j] = -1e300   // exclude j==k from the risk set

		mx = max(lrm)
		P = exp(lrm :- mx)
		lrsum = mx + ln(sum(P))
		ll = ll + (lrm[s,r] - lrsum)

		P = P :/ sum(P)   // proper softmax probability matrix over the risk set
		grad[1] = grad[1] + (nodsnd_i[s] - sum(nodsnd_i :* rowsum(P)'))
		grad[2] = grad[2] + (nidrec_i[r] - sum(nidrec_i :* colsum(P)))
	}
}

/*
	Pure log-likelihood wrapper (no gradient) - used by certification
	tests/diagnostics that only need the ll value at a given theta.
*/
real scalar rem_loglik_unit1(real rowvector theta, pointer(class RemState scalar) scalar pS) {
	real scalar ll
	real rowvector grad
	rem_loglik_grad_unit1(theta, pS, ll, grad)
	return(ll)
}

void rem_eval_unit1(real scalar todo, real rowvector theta, pointer(class RemState scalar) scalar pS,
		real scalar y, real rowvector g, real matrix H) {
	real rowvector grad
	rem_loglik_grad_unit1(theta, pS, y, grad)
	if (todo >= 1) g = grad
}

/*
	RemFitUnit1() -- fits the unit-1 model (NODSnd + NIDRec, no
	intercept - see rem_loglik_unit1()'s own comment for why) via
	Mata's own built-in optimize() (BFGS, numerical gradient for
	this first unit - see the development notes section 5 for why an
	external optimizer dependency is unnecessary and why an analytic
	gradient is deferred). Returns coefficients + SEs into Stata via
	st_matrix()/st_numscalar(), consumed by nwrem.ado.
*/
void RemFitUnit1(real matrix eventmat, real scalar n, string scalar bname, string scalar vname, string scalar llname) {
	class RemState scalar S
	transmorphic S_opt
	real rowvector theta0, theta_hat
	real matrix V

	S = RemState()
	S.init(eventmat, n)
	S.build_degree_accumulators()

	// A starting value of exactly all-zero makes every off-diagonal
	// lrm cell numerically identical (flat), which can degenerate
	// optimize()'s finite-difference gradient probe at the very first
	// step ("flat region encountered") - a small nonzero perturbation
	// breaks the symmetry without biasing the result. Still not
	// bulletproof on its own: found via this project's own doc-example
	// testing that a genuinely tiny event count (e.g. 3 events on 3
	// actors, almost no degree variation to speak of) can still hit
	// the same "flat region" failure even with an analytic gradient
	// supplied. Rather than push a larger minimum-event-count
	// requirement onto every caller, retry with escalating starting
	// perturbations and, as a last resort, the derivative-free
	// Nelder-Mead technique (immune to this specific failure mode,
	// since it never evaluates a gradient) before giving up.
	// _optimize() (not optimize()) returns an error CODE instead of
	// throwing, via optimize_result_errorcode() - Mata has no
	// try/catch, this is the documented way to attempt something that
	// might fail and decide programmatically whether to retry.
	real scalar attempt, ok, errcode
	real matrix starts
	starts = (0.01,0.01 \ 0.3,-0.3 \ -0.3,0.3 \ 1,-1)
	ok = 0
	for (attempt=1; attempt<=rows(starts) & ok==0; attempt++) {
		theta0 = starts[attempt,.]
		S_opt = optimize_init()
		optimize_init_evaluator(S_opt, &rem_eval_unit1())
		optimize_init_evaluatortype(S_opt, "d1")
		optimize_init_params(S_opt, theta0)
		optimize_init_argument(S_opt, 1, &S)
		optimize_init_technique(S_opt, "bfgs")
		optimize_init_which(S_opt, "max")
		optimize_init_tracelevel(S_opt, "none")
		optimize_init_conv_warning(S_opt, "off")
		optimize_init_conv_maxiter(S_opt, 40)
		errcode = _optimize(S_opt)
		if (errcode == 0) {
			theta_hat = optimize_result_params(S_opt)
			ok = 1
		}
	}
	if (ok == 0) {
		// Last resort: Nelder-Mead never evaluates a gradient at all,
		// so it cannot hit this specific "flat region" failure mode -
		// slower to converge, only reached when every gradient-based
		// attempt above has already failed.
		S_opt = optimize_init()
		optimize_init_evaluator(S_opt, &rem_eval_unit1())
		optimize_init_evaluatortype(S_opt, "d1")
		optimize_init_params(S_opt, (0.01,0.01))
		optimize_init_argument(S_opt, 1, &S)
		optimize_init_technique(S_opt, "nm")
		optimize_init_which(S_opt, "max")
		optimize_init_tracelevel(S_opt, "none")
		optimize_init_conv_warning(S_opt, "off")
		theta_hat = optimize(S_opt)
	}
	V = optimize_result_V_oim(S_opt)

	st_matrix(bname, theta_hat)
	st_matrix(vname, V)
	st_numscalar(llname, optimize_result_value(S_opt))
}

/*
	Units 2 and 5, extended by unit 4's static covariate effects
	(CovSnd/CovRec/CovInt/CovEvent) and unit 3's recency-rank effects
	(RSndSnd/RRecSnd): a generalized multi-effect engine, replacing
	unit 1's hardcoded 2-parameter design now that a third effect
	FAMILY exists (inertia, unit 2) which is a genuine per-DYAD
	statistic, not decomposable into a sender-only + receiver-only
	marginal the way every unit-1/5 degree effect is. `active` selects
	which of 14 known effects (fixed order below) enter the model;
	theta has exactly sum(active) elements, in that same relative
	order. Every formula below was read from relevent's own C source
	(src/relevent.c's lambda()/logrm_rceff()/logrm_normint()/
	logrm_irr()/acl_adj()) to verify this project's own independent
	derivation - never copied into Mata (see the development notes).

	Fixed effect order:
	  1  NODSnd     row(sender)    = out-degree share
	  2  NIDRec     col(receiver)  = in-degree share
	  3  NIDSnd     row(sender)    = in-degree share
	  4  NODRec     col(receiver)  = out-degree share
	  5  NTDegSnd   row(sender)    = total-degree share
	  6  NTDegRec   col(receiver)  = total-degree share
	  7  FrPSndSnd  dyad(j,k)      = fraction of j's own past SENDS that went to k
	  8  FrRecSnd   dyad(j,k)      = fraction of j's own past RECEIVES that came from k
	  9  CovSnd     row(sender)    = user-supplied per-actor covariate (static, unit 4)
	  10 CovRec     col(receiver)  = user-supplied per-actor covariate (static, unit 4)
	  11 CovInt     row+col(both)  = user-supplied per-actor covariate, ego AND alter, summed (static, unit 4)
	  12 CovEvent   dyad(j,k)      = user-supplied n x n pairwise covariate matrix (static, unit 4)
	  13 RSndSnd    dyad(j,k)      = 1/(recency rank of k among j's own past SENDS), 0 if j never sent to k
	  14 RRecSnd    dyad(j,k)      = 1/(recency rank of k among j's own past RECEIPTS), 0 if j never received from k

	Effects 1-6 (degree family, unit 1 + unit 5) use the SAME 1/(n-1)
	first-event fallback as rem_loglik_grad_unit1() - see that
	function's own comment for why (matches relevent exactly, corrected
	from an earlier misreading). Effects 7-8 (inertia family, unit 2)
	use relevent's own fallback for a zero denominator: coef/(n-1),
	the same uniform "nothing known yet" contribution degree effects
	use at i=1, applied here whenever the relevant marginal degree is
	still zero (not only at i=1 - e.g. an actor who has never sent
	anything yet has cumoutdeg==0 for FrPSndSnd's own denominator at
	ANY event, not just the first).

	Effects 9-11 (unit 4a, static covariates only - v1 scope, matching
	relevent's own `ctimed=FALSE` case): each takes its OWN independent
	per-actor covariate vector (covsndvec/covrecvec/covintvec - NOT
	forced to share one, since a real model may want e.g. "seniority
	affects sending" and "department affects receiving" as genuinely
	different variables at once, exactly as relevent's own covar$CovSnd/
	CovRec/CovInt are independent arrays). Pass J(1,n,0) for whichever
	vector(s) correspond to inactive effects - never read when
	active[e]==0.

	Effect 12 (unit 4b, CovEvent): relevent's own dyadic/pair
	covariate, mode=4 "event-wise" in logrm_rceff() (relevent's C
	source, read to verify - see the development notes): unlike
	effects 9-11 (a per-actor value broadcast across rows or columns),
	CovEvent supplies an INDEPENDENT value for every ordered (j,k)
	dyad directly - `lrm[j,k] += theta*covevmat[j,k]`, no broadcasting
	at all. This is a genuinely different data shape (n x n, not
	1 x n), which is exactly why it was deferred out of unit 4a: it
	needed its own input path rather than reusing covsndvec's. Static
	only in v1 (matches relevent's own `ctimed=FALSE` case, same as
	effects 9-11) - pass J(n,n,0) when inactive, never read in that
	case.

	Effects 13-14 (unit 3, recency-rank): relevent's own
	`logrm_irr()`/`accum_rrl_R()` (read to verify, not copied) maintain,
	per actor, an ORDERED (most-recent-first) list of past contact
	partners and add `coef/rank` to the log-rate matrix for each -
	NOT a fraction like FrPSndSnd/FrRecSnd (effects 7-8, which use
	relative FREQUENCY of past contact) but a reciprocal RANK (only
	"how recently", never "how often"). Reimplemented here without
	relevent's own per-actor linked-list bookkeeping: an n x n
	`lastcontact` matrix (`lastcontact[j,k]` = the index of the most
	recent PRIOR event, if any, where j sent to k; 0 if never) is
	maintained incrementally (same "update AFTER using this event's
	own pre-event state" discipline as `cij`), and at each event the
	full per-effect matrix is built by RANKING each row (RSndSnd) or
	column (RRecSnd) of `lastcontact` via `rem_rank_reciprocal()`
	(below) - relevent's own `rrl$out`/`rrl$in` lists are exactly the
	same information (per-actor recency-ordered partner lists),
	reimplemented via a dense matrix + per-row/column sort since Mata
	has no convenient sparse ordered-list primitive to match relevent's
	own R-list-based approach. `lastcontact[j,k]` values are strictly
	increasing along a single actor's own real event history, so no
	value can tie with another for the SAME row/column, making rank a
	well-defined strict ordering; an actor never contacted (row/column
	entirely 0) contributes nothing to any candidate dyad - exactly
	relevent's own "empty list -> no lrm contribution" behavior at the
	very first event, generalized to every subsequent point where an
	actor still has no relevant history.

	theta-index mapping (which slot of the compacted theta/grad vector
	each active effect occupies) is computed ONCE before the event loop
	via idx[], not recomputed per (event, j, k) triple - correctness
	does not depend on this, but O(nevents*n^2) redundant colsum() calls
	would have been a real, easily-avoided cost.
*/
/*
	rem_rank_reciprocal() -- given a real colvector v (n x 1) of "last
	contact index" values (larger = more recent; 0 = never contacted),
	returns a real rowvector (1 x n) where entry k is 1/rank(v[k]) if
	v[k]>0 (rank 1 = the single largest/most-recent value among v's own
	nonzero entries), or 0 if v[k]==0. Shared by both RSndSnd (applied
	to a ROW of `lastcontact`) and RRecSnd (applied to a COLUMN) -
	same ranking logic either way, only which slice of `lastcontact` is
	passed in differs.
*/
real rowvector rem_rank_reciprocal(real colvector v) {
	real scalar nn, i, nz
	real colvector nzidx, ord
	real rowvector res

	nn = rows(v)
	res = J(1, nn, 0)
	nzidx = selectindex(v :> 0)
	nz = length(nzidx)
	if (nz > 0) {
		ord = order(v[nzidx], -1)   // descending: ord[1] indexes (within nzidx) the most recent contact
		for (i=1; i<=nz; i++) {
			res[nzidx[ord[i]]] = 1 :/ i
		}
	}
	return(res)
}
void rem_loglik_grad_multi(real rowvector theta, real rowvector active,
		real rowvector covsndvec, real rowvector covrecvec, real rowvector covintvec,
		real matrix covevmat,
		pointer(class RemState scalar) scalar pS, real scalar ll, real rowvector grad) {
	real scalar i, s, r, priorn, mx, lrsum, j, k, n, e, fallback
	real rowvector odeg_frac, ideg_frac, tdeg_frac, gradfull, idx
	real matrix lrm, P, cij, eff7mat, eff8mat, lastcontact, eff13mat, eff14mat

	n = (*pS).n
	ll = 0
	gradfull = J(1, 14, 0)
	cij = J(n, n, 0)   // cumulative i->j raw counts, strictly prior to event i (incremental)
	lastcontact = J(n, n, 0)   // lastcontact[j,k] = index of most recent PRIOR event where j sent to k (0 = never), incremental
	fallback = 1 :/ (n - 1)

	idx = J(1, 14, 0)
	j = 0
	for (e=1; e<=14; e++) {
		if (active[e]) {
			j = j + 1
			idx[e] = j
		}
	}

	for (i=1; i<=(*pS).nevents; i++) {
		s = (*pS).events[i,1]
		r = (*pS).events[i,2]
		priorn = i - 1

		if (priorn == 0) {
			odeg_frac = J(1, n, fallback)
			ideg_frac = J(1, n, fallback)
			tdeg_frac = J(1, n, fallback)
		}
		else {
			odeg_frac = (*pS).cumoutdeg[i,.] :/ priorn
			ideg_frac = (*pS).cumindeg[i,.] :/ priorn
			tdeg_frac = ((*pS).cumoutdeg[i,.] :+ (*pS).cumindeg[i,.]) :/ (2 * priorn)
		}

		// eff7mat[j,k] / eff8mat[j,k]: the inertia effect values for
		// EVERY candidate dyad at this event - built once per event
		// (not per j,k pair) since each row j only depends on j.
		if (active[7]) {
			eff7mat = J(n, n, fallback)
			for (j=1; j<=n; j++) {
				if ((*pS).cumoutdeg[i,j] != 0) eff7mat[j,.] = cij[j,.] :/ (*pS).cumoutdeg[i,j]
			}
		}
		if (active[8]) {
			eff8mat = J(n, n, fallback)
			for (j=1; j<=n; j++) {
				if ((*pS).cumindeg[i,j] != 0) eff8mat[j,.] = cij[.,j]' :/ (*pS).cumindeg[i,j]
			}
		}

		// eff13mat[j,k] (RSndSnd) / eff14mat[j,k] (RRecSnd): recency-rank
		// reciprocal effect matrices - RSndSnd ranks each ROW of
		// `lastcontact` (j's own past outgoing contacts); RRecSnd ranks
		// each COLUMN (j's own past incoming contacts, i.e. who has sent
		// TO j), same "rank a column, place into a row" pattern eff8mat
		// already uses for FrRecSnd above. No fallback for a never-
		// contacted actor (unlike effects 7-8's coef/(n-1)) - relevent's
		// own logrm_irr() contributes nothing at all for an empty
		// recency list, matched exactly via rem_rank_reciprocal()'s own
		// all-zero return in that case.
		if (active[13]) {
			eff13mat = J(n, n, 0)
			for (j=1; j<=n; j++) {
				eff13mat[j,.] = rem_rank_reciprocal(lastcontact[j,.]')
			}
		}
		if (active[14]) {
			eff14mat = J(n, n, 0)
			for (j=1; j<=n; j++) {
				eff14mat[j,.] = rem_rank_reciprocal(lastcontact[.,j])
			}
		}

		lrm = J(n, n, 0)
		if (active[1]) lrm = lrm :+ theta[idx[1]] :* odeg_frac' * J(1,n,1)
		if (active[2]) lrm = lrm :+ J(n,1,1) * (theta[idx[2]] :* ideg_frac)
		if (active[3]) lrm = lrm :+ theta[idx[3]] :* ideg_frac' * J(1,n,1)
		if (active[4]) lrm = lrm :+ J(n,1,1) * (theta[idx[4]] :* odeg_frac)
		if (active[5]) lrm = lrm :+ theta[idx[5]] :* tdeg_frac' * J(1,n,1)
		if (active[6]) lrm = lrm :+ J(n,1,1) * (theta[idx[6]] :* tdeg_frac)
		if (active[7]) lrm = lrm :+ theta[idx[7]] :* eff7mat
		if (active[8]) lrm = lrm :+ theta[idx[8]] :* eff8mat
		if (active[9]) lrm = lrm :+ theta[idx[9]] :* covsndvec' * J(1,n,1)
		if (active[10]) lrm = lrm :+ J(n,1,1) * (theta[idx[10]] :* covrecvec)
		if (active[11]) lrm = lrm :+ theta[idx[11]] :* (covintvec' * J(1,n,1) :+ J(n,1,1) * covintvec)
		if (active[12]) lrm = lrm :+ theta[idx[12]] :* covevmat
		if (active[13]) lrm = lrm :+ theta[idx[13]] :* eff13mat
		if (active[14]) lrm = lrm :+ theta[idx[14]] :* eff14mat
		for (j=1; j<=n; j++) lrm[j,j] = -1e300   // exclude j==k from the risk set

		mx = max(lrm)
		P = exp(lrm :- mx)
		lrsum = mx + ln(sum(P))
		ll = ll + (lrm[s,r] - lrsum)
		P = P :/ sum(P)

		// analytic gradient: realized effect value minus its
		// expectation under P, same structure as rem_loglik_grad_unit1
		if (active[1]) gradfull[1] = gradfull[1] + (odeg_frac[s] - sum(odeg_frac :* rowsum(P)'))
		if (active[2]) gradfull[2] = gradfull[2] + (ideg_frac[r] - sum(ideg_frac :* colsum(P)))
		if (active[3]) gradfull[3] = gradfull[3] + (ideg_frac[s] - sum(ideg_frac :* rowsum(P)'))
		if (active[4]) gradfull[4] = gradfull[4] + (odeg_frac[r] - sum(odeg_frac :* colsum(P)))
		if (active[5]) gradfull[5] = gradfull[5] + (tdeg_frac[s] - sum(tdeg_frac :* rowsum(P)'))
		if (active[6]) gradfull[6] = gradfull[6] + (tdeg_frac[r] - sum(tdeg_frac :* colsum(P)))
		if (active[7]) gradfull[7] = gradfull[7] + (eff7mat[s,r] - sum(eff7mat :* P))
		if (active[8]) gradfull[8] = gradfull[8] + (eff8mat[s,r] - sum(eff8mat :* P))
		if (active[9]) gradfull[9] = gradfull[9] + (covsndvec[s] - sum(covsndvec :* rowsum(P)'))
		if (active[10]) gradfull[10] = gradfull[10] + (covrecvec[r] - sum(covrecvec :* colsum(P)))
		if (active[11]) gradfull[11] = gradfull[11] + ((covintvec[s] + covintvec[r]) - sum((covintvec' * J(1,n,1) :+ J(n,1,1) * covintvec) :* P))
		if (active[12]) gradfull[12] = gradfull[12] + (covevmat[s,r] - sum(covevmat :* P))
		if (active[13]) gradfull[13] = gradfull[13] + (eff13mat[s,r] - sum(eff13mat :* P))
		if (active[14]) gradfull[14] = gradfull[14] + (eff14mat[s,r] - sum(eff14mat :* P))

		cij[s,r] = cij[s,r] + 1   // update AFTER using this event's own pre-event state
		lastcontact[s,r] = i     // update AFTER using this event's own pre-event state
	}

	grad = J(1, 0, 0)
	for (e=1; e<=14; e++) if (active[e]) grad = (grad, gradfull[e])
}

/*
	FAST EVALUATOR. rem_loglik_grad_multi() above builds a dense n x n risk-set matrix for every event: O(nevents n^2)
	work per likelihood evaluation, and an optimizer needs 30 to 500 evaluations. The log-rate matrix has the form
	lrm[j,k] = a_j + b_k + delta_jk (j != k): the degree and covariate effects (1-6, 9-11) put a term on the sender
	only (a) or on the receiver only (b); only the dyadic effects (7, 8, 12, 13, 14) make up delta. Without delta the
	normaliser of the event is Z = (sum_j e^a_j)(sum_k e^b_k) minus the diagonal, O(n) per event, and no event loop is
	needed: whole blocks of events are handled as matrices. The static dyadic effect (12) needs F = exp(theta delta)
	once per evaluation and Z for a block of events from one (events x n)(n x n) product. The state-dependent dyadic
	effects (7, 8, 13, 14) change only the rows of the sender and the receiver after every event, so F and
	the products D :* F are kept as n x n matrices and updated at those two rows (loop over events, O(n^2) per event
	but with matrix-vector products instead of an n x n softmax with a sort).
	The result is the same likelihood and gradient as rem_loglik_grad_multi() up to rounding (about 1e-12 relative).
	Safeguards: the shifts of a and b are taken separately (rowmax), so Z can underflow where the global shift of the
	dense evaluator does not; exp() overflow gives a missing value in Mata and sum() ignores missing values silently.
	The fast evaluator therefore checks every normaliser and every exponentiated matrix and returns 0 when anything is
	missing, non-positive or smaller than 1e-250; rem_loglik_grad_auto() then uses the dense evaluator for that
	evaluation. Z = (sum e^a)(sum e^b) minus the diagonal cancels badly when one actor carries almost all the mass:
	the sum excluding the maximum cell is recomputed exactly (rem_sumexcl()). Memory: events are processed in blocks
	of about 1.5 million cells, so 50,000 events and 170 actors stay far below one gigabyte.
*/

// the degree shares of the realized sender / receiver at every event (do not depend on theta)
void rem_fast_prep(class RemState scalar S)
{
	real scalar i, n, m, pn, fb, s, r
	n = S.n
	m = S.nevents
	fb = 1 / (n - 1)
	S.ODs = J(m, 1, fb); S.ODr = J(m, 1, fb); S.IDs = J(m, 1, fb); S.IDr = J(m, 1, fb); S.TDs = J(m, 1, fb); S.TDr = J(m, 1, fb)
	for (i = 2; i <= m; i++) {
		pn = i - 1
		s = S.events[i,1]
		r = S.events[i,2]
		S.ODs[i] = S.cumoutdeg[i,s] / pn
		S.ODr[i] = S.cumoutdeg[i,r] / pn
		S.IDs[i] = S.cumindeg[i,s] / pn
		S.IDr[i] = S.cumindeg[i,r] / pn
		S.TDs[i] = (S.cumoutdeg[i,s] + S.cumindeg[i,s]) / (2 * pn)
		S.TDr[i] = (S.cumoutdeg[i,r] + S.cumindeg[i,r]) / (2 * pn)
	}
}

// the shares of events i0..i1 (same values as odeg_frac, ideg_frac, tdeg_frac of rem_loglik_grad_multi()); only the
// matrices that an active effect needs are built
void rem_fast_deg(class RemState scalar S, real scalar i0, real scalar i1, real rowvector active,
		real matrix OD, real matrix ID, real matrix TD)
{
	real colvector den
	real matrix co, ci
	real scalar n
	n = S.n
	den = ((i0 - 1) :: (i1 - 1))
	if (i0 == 1) den[1] = 1
	OD = J(0, 0, .); ID = J(0, 0, .); TD = J(0, 0, .)
	if (active[1] | active[4] | active[5] | active[6]) co = S.cumoutdeg[|i0,1 \ i1,n|]
	if (active[2] | active[3] | active[5] | active[6]) ci = S.cumindeg[|i0,1 \ i1,n|]
	if (active[1] | active[4]) OD = co :/ den
	if (active[2] | active[3]) ID = ci :/ den
	if (active[5] | active[6]) TD = (co :+ ci) :/ (2 :* den)
	if (i0 == 1) {
		if (rows(OD)) OD[1,.] = J(1, n, 1 / (n - 1))
		if (rows(ID)) ID[1,.] = J(1, n, 1 / (n - 1))
		if (rows(TD)) TD[1,.] = J(1, n, 1 / (n - 1))
	}
}

// 1 when the fast evaluator is worth using and its matrices fit in memory
real scalar rem_fast_usable(real rowvector active, real scalar n)
{
	real scalar dyn
	dyn = active[7] | active[8] | active[13] | active[14]
	if (n < 3) return(0)
	if ((dyn | active[12]) & 12 * n * n > 4e7) return(0)   // about 320 MB of n x n matrices: use the dense evaluator
	return(1)
}

// for every row of E: the sum over all cells except the cell j, for every j (row sum minus the cell), with the cell
// that holds the row maximum recomputed without cancellation (ties: the other maximum cells are counted)
real matrix rem_sumexcl(real matrix E)
{
	real colvector mx
	real matrix M
	mx = rowmax(E)
	M = (E :== mx)
	return((rowsum(E) :- E) :* (1 :- M) :+ M :* (rowsum(E :* (1 :- M)) :+ (rowsum(M) :- 1) :* mx))
}

/*
	RemDyn -- the state of the dyadic effects 7, 8, 12, 13, 14 for the fast evaluator: the effect matrices D (n x n),
	the log-rate part delta, F = exp(delta) with a zero diagonal and the products G = D :* F, kept current by row():
	after an event only the rows of the sender (cij[s,.], lc[s,.]) and of the receiver (cij[.,r], lc[.,r]) change.
*/
class RemDyn {
	real scalar n, fb, t7, t8, t12, t13, t14, a7, a8, a12, a13, a14
	real matrix cij, lc, D7, D8, D13, D14, C, delta, F, G7, G8, G13, G14, G12

	void init()
	real scalar row()
}

void RemDyn::init(real rowvector theta, real rowvector active, real rowvector idx, real matrix Cin, real scalar nn)
{
	n = nn
	fb = 1 / (n - 1)
	a7 = active[7]; a8 = active[8]; a12 = active[12]; a13 = active[13]; a14 = active[14]
	t7 = a7 ? theta[idx[7]] : 0
	t8 = a8 ? theta[idx[8]] : 0
	t12 = a12 ? theta[idx[12]] : 0
	t13 = a13 ? theta[idx[13]] : 0
	t14 = a14 ? theta[idx[14]] : 0
	C = Cin
	cij = J(n, n, 0); lc = J(n, n, 0)
	D7 = J(n, n, 0); D8 = J(n, n, 0); D13 = J(n, n, 0); D14 = J(n, n, 0)
	G7 = J(n, n, 0); G8 = J(n, n, 0); G13 = J(n, n, 0); G14 = J(n, n, 0); G12 = J(n, n, 0)
	delta = J(n, n, 0); F = J(n, n, 0)
}

// recompute row j after a change; co / ci: out- and in-degree of actor j (counts) at the state now held. Returns 0 when exp() overflowed
real scalar RemDyn::row(real scalar j, real scalar co, real scalar ci)
{
	real rowvector d, f
	d = J(1, n, 0)
	if (a12) d = d :+ t12 :* C[j,.]
	if (a7) {
		if (co != 0) D7[j,.] = cij[j,.] :/ co
		else D7[j,.] = J(1, n, fb)
		d = d :+ t7 :* D7[j,.]
	}
	if (a8) {
		if (ci != 0) D8[j,.] = cij[.,j]' :/ ci
		else D8[j,.] = J(1, n, fb)
		d = d :+ t8 :* D8[j,.]
	}
	if (a13) {
		D13[j,.] = rem_rank_reciprocal(lc[j,.]')
		d = d :+ t13 :* D13[j,.]
	}
	if (a14) {
		D14[j,.] = rem_rank_reciprocal(lc[.,j])
		d = d :+ t14 :* D14[j,.]
	}
	delta[j,.] = d
	f = exp(d)
	f[j] = 0
	if (hasmissing(f)) return(0)
	F[j,.] = f
	if (a7) G7[j,.] = D7[j,.] :* f
	if (a8) G8[j,.] = D8[j,.] :* f
	if (a13) G13[j,.] = D13[j,.] :* f
	if (a14) G14[j,.] = D14[j,.] :* f
	if (a12) G12[j,.] = C[j,.] :* f
	return(1)
}

/*
	rem_loglik_grad_fast() -- same arguments as rem_loglik_grad_multi(); returns 1 when ll and grad are valid, 0 when the
	caller must use rem_loglik_grad_multi() instead (see the safeguards in the comment above). rem_fast_prep() must
	have run on the state.
*/
real scalar rem_loglik_grad_fast(real rowvector theta, real rowvector active,
		real rowvector covsndvec, real rowvector covrecvec, real rowvector covintvec,
		real matrix covevmat,
		pointer(class RemState scalar) scalar pS, real scalar ll, real rowvector grad) {
	real scalar n, m, e, j, i, ii, i0, i1, c, chunk, dyn, sh, th12, s, r, needrow, needcol
	real rowvector idx, gf, ea, eb
	real colvector sv, rv, rid, Ma, Mb, Z, lz, lsr, cvsr, ldy
	real matrix A, B, EA, EB, XA, XB, rowP, colP, T, F, FC, C, Q, OD, ID, TD
	class RemDyn scalar Y

	n = (*pS).n
	m = (*pS).nevents
	idx = J(1, 14, 0)
	j = 0
	for (e = 1; e <= 14; e++) {
		if (active[e]) {
			j = j + 1
			idx[e] = j
		}
	}
	dyn = active[7] | active[8] | active[13] | active[14]
	needrow = active[1] | active[3] | active[5] | active[9] | active[11]
	needcol = active[2] | active[4] | active[6] | active[10] | active[11]
	if (hasmissing(theta)) return(0)
	C = J(n, n, 0)
	if (active[12]) {
		// the diagonal is not part of the risk set; the covariate may carry anything there (a missing value, a loop): zero
		C = covevmat
		for (j = 1; j <= n; j++) C[j,j] = 0
		if (hasmissing(C)) return(0)
		th12 = theta[idx[12]]
		if (!dyn) {
			Q = th12 :* C
			for (j = 1; j <= n; j++) Q[j,j] = -1e300
			if (hasmissing(Q)) return(0)
			sh = max(Q)
			F = exp(Q :- sh)
			if (hasmissing(F)) return(0)
			FC = F :* C
		}
	}
	if (dyn) {
		Y = RemDyn()
		Y.init(theta, active, idx, C, n)
		for (j = 1; j <= n; j++) if (Y.row(j, 0, 0) == 0) return(0)
	}

	chunk = max((1, min((m, floor((missing((*pS).chunkcells) ? 1.5e6 : (*pS).chunkcells) / n)))))
	ll = 0
	gf = J(1, 14, 0)
	for (i0 = 1; i0 <= m; i0 = i0 + chunk) {
		i1 = min((m, i0 + chunk - 1))
		c = i1 - i0 + 1
		rid = (i0 :: i1)
		sv = (*pS).events[|i0,1 \ i1,1|]
		rv = (*pS).events[|i0,2 \ i1,2|]
		rem_fast_deg(*pS, i0, i1, active, OD, ID, TD)
		A = J(c, n, 0); B = J(c, n, 0)
		lsr = J(c, 1, 0)
		if (active[1]) {
			A = A :+ theta[idx[1]] :* OD
			lsr = lsr :+ theta[idx[1]] :* (*pS).ODs[rid]
		}
		if (active[2]) {
			B = B :+ theta[idx[2]] :* ID
			lsr = lsr :+ theta[idx[2]] :* (*pS).IDr[rid]
		}
		if (active[3]) {
			A = A :+ theta[idx[3]] :* ID
			lsr = lsr :+ theta[idx[3]] :* (*pS).IDs[rid]
		}
		if (active[4]) {
			B = B :+ theta[idx[4]] :* OD
			lsr = lsr :+ theta[idx[4]] :* (*pS).ODr[rid]
		}
		if (active[5]) {
			A = A :+ theta[idx[5]] :* TD
			lsr = lsr :+ theta[idx[5]] :* (*pS).TDs[rid]
		}
		if (active[6]) {
			B = B :+ theta[idx[6]] :* TD
			lsr = lsr :+ theta[idx[6]] :* (*pS).TDr[rid]
		}
		if (active[9]) {
			A = A :+ theta[idx[9]] :* covsndvec
			lsr = lsr :+ theta[idx[9]] :* covsndvec'[sv]
		}
		if (active[10]) {
			B = B :+ theta[idx[10]] :* covrecvec
			lsr = lsr :+ theta[idx[10]] :* covrecvec'[rv]
		}
		if (active[11]) {
			A = A :+ theta[idx[11]] :* covintvec
			B = B :+ theta[idx[11]] :* covintvec
			lsr = lsr :+ theta[idx[11]] :* (covintvec'[sv] :+ covintvec'[rv])
		}
		Ma = rowmax(A); Mb = rowmax(B)
		EA = exp(A :- Ma); EB = exp(B :- Mb)
		A = J(0, 0, .); B = J(0, 0, .)
		if (hasmissing(EA) | hasmissing(EB)) return(0)

		if (dyn) {
			Z = J(c, 1, 0)
			ldy = J(c, 1, 0)
			rowP = J(c, n, 0); colP = J(c, n, 0)
			for (ii = 1; ii <= c; ii++) {
				i = i0 + ii - 1
				s = sv[ii]; r = rv[ii]
				ea = EA[ii,.]; eb = EB[ii,.]
				T = (Y.F * eb')           // n x 1: sum_k F[j,k] eb[k]
				Z[ii] = ea * T
				if (Z[ii] < 1e-250 | missing(Z[ii])) return(0)
				ldy[ii] = Y.delta[s,r]
				rowP[ii,.] = (ea :* T') :/ Z[ii]
				colP[ii,.] = (eb :* (ea * Y.F)) :/ Z[ii]
				if (active[7]) gf[7] = gf[7] + Y.D7[s,r] - ((ea * Y.G7) * eb') / Z[ii]
				if (active[8]) gf[8] = gf[8] + Y.D8[s,r] - ((ea * Y.G8) * eb') / Z[ii]
				if (active[12]) gf[12] = gf[12] + C[s,r] - ((ea * Y.G12) * eb') / Z[ii]
				if (active[13]) gf[13] = gf[13] + Y.D13[s,r] - ((ea * Y.G13) * eb') / Z[ii]
				if (active[14]) gf[14] = gf[14] + Y.D14[s,r] - ((ea * Y.G14) * eb') / Z[ii]
				// update AFTER using this event's own pre-event state
				Y.cij[s,r] = Y.cij[s,r] + 1
				Y.lc[s,r] = i
				if (Y.row(s, (*pS).cumoutdeg[i,s] + 1, (*pS).cumindeg[i,s]) == 0) return(0)
				if (Y.row(r, (*pS).cumoutdeg[i,r], (*pS).cumindeg[i,r] + 1) == 0) return(0)
			}
			lz = Ma :+ Mb :+ ln(Z)
			lsr = lsr :+ ldy
		}
		else if (active[12]) {
			T = EA * F
			Z = rowsum(T :* EB)
			if (hasmissing(Z)) return(0)
			if (min(Z) < 1e-250) return(0)
			if (needrow) rowP = EA :* (EB * F') :/ Z
			if (needcol) colP = EB :* T :/ Z
			cvsr = J(c, 1, 0)
			for (ii = 1; ii <= c; ii++) cvsr[ii] = C[sv[ii],rv[ii]]
			lsr = lsr :+ th12 :* cvsr
			gf[12] = gf[12] + sum(cvsr) - sum(rowsum((EA * FC) :* EB) :/ Z)
			lz = Ma :+ Mb :+ sh :+ ln(Z)
		}
		else {
			XB = rem_sumexcl(EB)
			XA = rem_sumexcl(EA)
			Z = rowsum(EA :* XB)
			if (hasmissing(Z)) return(0)
			if (min(Z) < 1e-250) return(0)
			if (needrow) rowP = EA :* XB :/ Z
			if (needcol) colP = EB :* XA :/ Z
			lz = Ma :+ Mb :+ ln(Z)
		}
		ll = ll + sum(lsr :- lz)
		if (hasmissing(ll)) return(0)

		if (active[1]) gf[1] = gf[1] + sum((*pS).ODs[rid]) - sum(OD :* rowP)
		if (active[2]) gf[2] = gf[2] + sum((*pS).IDr[rid]) - sum(ID :* colP)
		if (active[3]) gf[3] = gf[3] + sum((*pS).IDs[rid]) - sum(ID :* rowP)
		if (active[4]) gf[4] = gf[4] + sum((*pS).ODr[rid]) - sum(OD :* colP)
		if (active[5]) gf[5] = gf[5] + sum((*pS).TDs[rid]) - sum(TD :* rowP)
		if (active[6]) gf[6] = gf[6] + sum((*pS).TDr[rid]) - sum(TD :* colP)
		if (active[9]) gf[9] = gf[9] + sum(covsndvec'[sv]) - sum(rowP * covsndvec')
		if (active[10]) gf[10] = gf[10] + sum(covrecvec'[rv]) - sum(colP * covrecvec')
		if (active[11]) gf[11] = gf[11] + sum(covintvec'[sv] :+ covintvec'[rv]) - sum((rowP :+ colP) * covintvec')
	}
	if (hasmissing(gf)) return(0)
	grad = J(1, 0, 0)
	for (e = 1; e <= 14; e++) if (active[e]) grad = (grad, gf[e])
	return(1)
}

// likelihood and gradient: the fast evaluator when the state allows it, the dense evaluator otherwise or when the fast one gives up
real scalar rem_loglik_grad_auto(real rowvector theta, real rowvector active,
		real rowvector covsndvec, real rowvector covrecvec, real rowvector covintvec,
		real matrix covevmat,
		pointer(class RemState scalar) scalar pS, real scalar ll, real rowvector grad) {
	if ((*pS).fast == 1) {
		if (rem_loglik_grad_fast(theta, active, covsndvec, covrecvec, covintvec, covevmat, pS, ll, grad)) return(1)
	}
	rem_loglik_grad_multi(theta, active, covsndvec, covrecvec, covintvec, covevmat, pS, ll, grad)
	return(0)
}

/*
	rem_dependent_effects() -- before the optimizer runs: which effects are an exact linear function of the effects
	before them (in the fixed effect order) plus a term that is constant over the risk set of every event? Such an
	effect cannot change the likelihood (the term cancels in the softmax) and the optimizer would only wander along the
	flat ridge (hundreds of evaluations). Returns a 1 x 14 0/1 vector. The test is the Gram matrix of the statistics
	centred within every risk set (j != k), accumulated over the events from sums over senders and receivers, so it costs
	O(nevents n) and covers the sender and receiver effects (1-6, 9-11) and the static dyadic effect (12); the
	state-dependent dyadic effects (7, 8, 13, 14) are not examined. An effect is dependent when what is left of its
	centred sum of squares after the effects before it is below 1e-12 of its uncentred one (rounding of exactly
	collinear statistics is about 1e-16).
*/
real rowvector rem_dependent_effects(real rowvector active, real rowvector covsndvec, real rowvector covrecvec,
		real rowvector covintvec, real matrix covevmat, class RemState scalar S)
{
	real scalar n, m, k, e, f, p, i0, i1, c, chunk, sumC, sumC2, N, r, tol
	real rowvector dropped, effs, ce, ACr, BCc
	real colvector rowC, colC, kept
	real matrix OD, ID, TD, Wa, Wb, Ra, Rb, AA, BB, AB, RaRb, Ssum, P, G, Ae, Be, C
	real matrix Rs

	dropped = J(1, 14, 0)
	effs = select((1, 2, 3, 4, 5, 6, 9, 10, 11, 12), active[(1, 2, 3, 4, 5, 6, 9, 10, 11, 12)])
	k = cols(effs)
	if (k == 0) return(dropped)
	n = S.n
	m = S.nevents
	N = n * (n - 1)
	C = J(n, n, 0)
	if (active[12]) {
		C = covevmat
		for (e = 1; e <= n; e++) C[e,e] = 0
		if (hasmissing(C)) return(dropped)
	}
	rowC = rowsum(C)
	colC = colsum(C)'
	sumC = sum(C)
	sumC2 = sum(C :* C)
	ce = (effs :== 12)
	AA = J(k, k, 0); BB = J(k, k, 0); AB = J(k, k, 0); RaRb = J(k, k, 0); Ssum = J(k, k, 0)
	ACr = J(1, k, 0); BCc = J(1, k, 0)
	chunk = max((1, min((m, floor((missing(S.chunkcells) ? 4e5 : S.chunkcells) / n)))))
	for (i0 = 1; i0 <= m; i0 = i0 + chunk) {
		i1 = min((m, i0 + chunk - 1))
		c = i1 - i0 + 1
		rem_fast_deg(S, i0, i1, active, OD, ID, TD)
		Wa = J(c * n, k, 0); Wb = J(c * n, k, 0)
		Ra = J(c, k, 0); Rb = J(c, k, 0)
		for (p = 1; p <= k; p++) {
			e = effs[p]
			Ae = J(c, n, 0); Be = J(c, n, 0)
			if (e == 1) Ae = OD
			else if (e == 2) Be = ID
			else if (e == 3) Ae = ID
			else if (e == 4) Be = OD
			else if (e == 5) Ae = TD
			else if (e == 6) Be = TD
			else if (e == 9) Ae = J(c, 1, covsndvec)
			else if (e == 10) Be = J(c, 1, covrecvec)
			else if (e == 11) {
				Ae = J(c, 1, covintvec)
				Be = Ae
			}
			Wa[.,p] = colshape(Ae, 1)
			Wb[.,p] = colshape(Be, 1)
			Ra[.,p] = rowsum(Ae)
			Rb[.,p] = rowsum(Be)
			ACr[p] = ACr[p] + sum(Ae * rowC)
			BCc[p] = BCc[p] + sum(Be * colC)
		}
		AA = AA + cross(Wa, Wa)
		BB = BB + cross(Wb, Wb)
		AB = AB + cross(Wa, Wb)
		RaRb = RaRb + cross(Ra, Rb)
		Rs = (n - 1) :* (Ra :+ Rb) :+ J(c, 1, ce :* sumC)
		Ssum = Ssum + cross(Rs, Rs)
	}
	// uncentred second moments summed over events and risk-set cells, and the centred Gram matrix
	P = (n - 1) :* (AA :+ BB) :+ (RaRb :- AB) :+ (RaRb :- AB)' :+ (ce' * ACr) :+ (ce' * ACr)' :+ (ce' * BCc) :+ (ce' * BCc)' :+ m * sumC2 :* (ce' * ce)
	G = P :- Ssum :/ N
	tol = 1e-12
	kept = J(0, 1, 0)
	for (p = 1; p <= k; p++) {
		if (rows(kept) == 0) r = G[p,p]
		else r = G[p,p] - G[p,kept'] * lusolve(G[kept,kept'], G[kept',p])
		if (hasmissing(r) | r <= tol * P[p,p]) dropped[effs[p]] = 1
		else kept = (kept \ p)
	}
	return(dropped)
}

/*
	Pure log-likelihood wrapper for the multi-effect engine (no
	gradient) - used by certification tests/diagnostics, same role as
	rem_loglik_unit1() for the unit-1-only engine.
*/
real scalar rem_loglik_multi(real rowvector theta, real rowvector active,
		real rowvector covsndvec, real rowvector covrecvec, real rowvector covintvec,
		real matrix covevmat,
		pointer(class RemState scalar) scalar pS) {
	real scalar ll
	real rowvector grad
	rem_loglik_grad_multi(theta, active, covsndvec, covrecvec, covintvec, covevmat, pS, ll, grad)
	return(ll)
}

end
