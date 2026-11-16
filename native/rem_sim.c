/*
 * Copyright (C) 2026 Thomas U. Grund
 * This file is part of nwrem, a Stata package derived from the R package 'relevent' (Carter T. Butts; GPL (>= 2)).
 * nwrem is free software: you can redistribute it and/or modify it under the terms of the GNU General
 * Public License, version 3, as published by the Free Software Foundation. It is distributed in the hope
 * that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
 * or FITNESS FOR A PARTICULAR PURPOSE. See the file LICENSE for the full text.
 */
/*
	rem_sim.c -- native (C) log likelihood, gradient and Hessian of the relational event model of nwrem (ordinal partial
	likelihood, Butts 2008) for all 14 effects.

	Every fit of nwrem runs here: Stata's Mata drives the outer loop (a damped Newton iteration on the exact Hessian, with
	optimize() as the fall-back) and calls this plugin once per evaluation at a given theta. The plugin carries no state between
	calls. The model (events, covariates) is written ONCE per fit as a block of numbers into the first variable of a frame (the
	"blob", layout below); each call passes the length of the blob, the parameter count and theta in the argument string and gets
	the result in the second variable.

	Argument string: "<code> <L> <todo> <P> <theta_1> ... <theta_P>"
	  code 20  evaluate (fast evaluator; when it gives up, the dense one)
	  code 21  evaluate with the dense evaluator only (tests)
	  code 22  evaluate with the fast evaluator only; log likelihood missing when it gives up (tests)
	  code 30  collinearity check: the static effects only (1-6, 9-12), theta = 0, Hessian and uncentred second moments
	  code 99  report the protocol number (row 1 of variable 2)
	Result (variable 2): row 1 = log likelihood (missing when no evaluator gives a finite value), rows 2..P+1 = gradient,
	then the P x P Hessian by rows (todo = 2), then P values E[X_p^2] summed over the events (used by code 30), then a flag
	(0 = fast evaluator, 1 = dense evaluator) in the last row of the result block: row 2 + P + P*P + P.

	Blob (doubles; L = total length):
	  [0] protocol  [1] n (actors)  [2] m (events)  [3..16] active flags of the 14 effects  [17..23] reserved
	  [24..] events: m rows of (sender, receiver), 1-based, sorted by time (the caller sorts; the order of events with equal
	  time is the order in which they are listed),
	  then covsnd (n), covrec (n), covint (n), then the n x n matrix of covevent (only when effect 12 is active).

	The effects, in this order (the order of theta is the order of the active ones):
	  1 nodsnd 2 nidrec 3 nidsnd 4 nodrec 5 ntdegsnd 6 ntdegrec 7 frpsndsnd 8 frrecsnd 9 covsnd 10 covrec 11 covint
	  12 covevent 13 rsndsnd 14 rrecsnd
	with the statistics of the Mata reference evaluators (cscripts/ref_rem_mata.do), which agree with relevent.

	The log rate of the dyad (j,k), j != k, at an event is the sum over the effects of theta_e X_e(j,k), and the probability that
	the event is (j,k) is its softmax over all dyads j != k. Every statistic is a sum X_e(j,k) = U_e[j] + W_e[k] + S_e(j,k) of a
	part of the sender, a part of the receiver and a sparse dyadic part S that is non-zero only for dyads in contact so far
	(frpsndsnd, frrecsnd, rsndsnd, rrecsnd) or for non-zero cells of covevent. The normaliser is then
	Z = (sum_j e^a_j)(sum_k e^b_k) minus the diagonal, plus a correction over the sparse dyads only: O(n + number of dyads in
	contact) per event instead of O(n^2). The sums that leave out the diagonal are formed from prefix and suffix sums (no
	cancellation). The fast evaluator gives up (and the dense O(n^2) evaluator with one global shift is used) when exp()
	overflows, a normaliser underflows, or the correction cancels more than six digits.
	Counts, the recency ranks of rsndsnd / rrecsnd (move-to-front lists) and the list of dyads in contact are updated after every
	event; none of it depends on theta.
*/

#include "stplugin.h"
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <stdint.h>

typedef int64_t nwint;

#ifndef REM_PROTOCOL
#define REM_PROTOCOL 1   /* raise together with REM_PROTOCOL_NEEDED() in unw_rem.do; the tests build a plugin with another number */
#endif
#define HDR 24
#define NEFF 14

typedef struct {
	nwint n, m;
	int act[NEFF];
	int P, eff[NEFF];            /* active effects (1-based codes) and their number */
	const double *ev;            /* m x 2 */
	const double *cs, *cr, *ci;  /* n each */
	const double *C;             /* n x n or NULL */
	double *blob;
} Spec;

typedef struct {
	nwint n;
	int has7, has8, has12, has13, has14;
	double *ocnt, *icnt;
	int32_t *cij, *rk13, *rk14, *outl, *inl, *outlen, *inlen;
	int32_t *pidx;               /* n*n: position of the dyad in the list of sparse dyads, -1 = not in it */
	int32_t *pj, *pk;
	double *sval, *sig;          /* per sparse dyad: NS statistics, sigma */
	nwint np, cap;
	int NS;
} State;

static void state_free(State *st) {
	free(st->ocnt); free(st->icnt); free(st->cij); free(st->rk13); free(st->rk14); free(st->outl); free(st->inl);
	free(st->outlen); free(st->inlen); free(st->pidx); free(st->pj); free(st->pk); free(st->sval); free(st->sig);
	memset(st, 0, sizeof(State));
}

static int has_e(const Spec *sp, int e) {
	int k;
	for (k = 0; k < sp->P; k++) if (sp->eff[k] == e) return 1;
	return 0;
}

static int part_A(int e) { return e == 1 || e == 3 || e == 5 || e == 7 || e == 8 || e == 9 || e == 11; }
static int part_B(int e) { return e == 2 || e == 4 || e == 6 || e == 10 || e == 11; }
static int part_S(int e) { return e == 7 || e == 8 || e == 12 || e == 13 || e == 14; }

static int state_reserve(State *st, nwint want) {
	if (want <= st->cap) return 0;
	{
		nwint nc = st->cap < 1024 ? 1024 : st->cap;
		int32_t *a, *b;
		double *c, *d;
		while (nc < want) nc *= 2;
		a = (int32_t *)realloc(st->pj, (size_t)nc * sizeof(int32_t)); if (!a) return 909; st->pj = a;
		b = (int32_t *)realloc(st->pk, (size_t)nc * sizeof(int32_t)); if (!b) return 909; st->pk = b;
		c = (double *)realloc(st->sig, (size_t)nc * sizeof(double)); if (!c) return 909; st->sig = c;
		if (st->NS > 0) { d = (double *)realloc(st->sval, (size_t)nc * (size_t)st->NS * sizeof(double)); if (!d) return 909; st->sval = d; }
		st->cap = nc;
	}
	return 0;
}

static int state_add(State *st, nwint j, nwint k) {
	int32_t *slot = &st->pidx[j * st->n + k];
	if (*slot >= 0) return 0;
	if (state_reserve(st, st->np + 1)) return 909;
	st->pj[st->np] = (int32_t)j;
	st->pk[st->np] = (int32_t)k;
	*slot = (int32_t)st->np;
	st->np++;
	return 0;
}

static int state_init(const Spec *sp, State *st, int NS) {
	nwint n = sp->n;
	size_t nn = (size_t)n * (size_t)n, un = (size_t)n;
	memset(st, 0, sizeof(State));
	st->n = n;
	st->NS = NS;
	st->has7 = has_e(sp, 7); st->has8 = has_e(sp, 8); st->has12 = has_e(sp, 12); st->has13 = has_e(sp, 13); st->has14 = has_e(sp, 14);
	st->ocnt = (double *)calloc(un, sizeof(double));
	st->icnt = (double *)calloc(un, sizeof(double));
	if (!st->ocnt || !st->icnt) return 909;
	if (st->has7 || st->has8) { st->cij = (int32_t *)calloc(nn, sizeof(int32_t)); if (!st->cij) return 909; }
	if (st->has13) {
		st->rk13 = (int32_t *)calloc(nn, sizeof(int32_t)); st->outl = (int32_t *)calloc(nn, sizeof(int32_t));
		st->outlen = (int32_t *)calloc(un, sizeof(int32_t));
		if (!st->rk13 || !st->outl || !st->outlen) return 909;
	}
	if (st->has14) {
		st->rk14 = (int32_t *)calloc(nn, sizeof(int32_t)); st->inl = (int32_t *)calloc(nn, sizeof(int32_t));
		st->inlen = (int32_t *)calloc(un, sizeof(int32_t));
		if (!st->rk14 || !st->inl || !st->inlen) return 909;
	}
	if (NS > 0) {
		size_t q;
		st->pidx = (int32_t *)malloc(nn * sizeof(int32_t));
		if (!st->pidx) return 909;
		for (q = 0; q < nn; q++) st->pidx[q] = -1;
		if (st->has12) {
			nwint j, k;
			for (j = 0; j < n; j++) for (k = 0; k < n; k++) {
				if (j != k && sp->C[j * n + k] != 0.0) { if (state_add(st, j, k)) return 909; }
			}
		}
	}
	return 0;
}

static void list_front(int32_t *list, int32_t *len, int32_t *rk, int32_t partner) {
	int32_t old = rk[partner], upto, p;
	if (old == 0) {
		memmove(list + 1, list, (size_t)(*len) * sizeof(int32_t));
		(*len)++;
		upto = *len - 1;
	} else {
		memmove(list + 1, list, (size_t)(old - 1) * sizeof(int32_t));
		upto = old - 1;
	}
	list[0] = partner;
	for (p = 0; p <= upto; p++) rk[list[p]] = p + 1;
}

/* state after the event (s,r) */
static int state_update(State *st, nwint s, nwint r) {
	nwint n = st->n;
	st->ocnt[s] += 1.0;
	st->icnt[r] += 1.0;
	if (st->cij) st->cij[s * n + r]++;
	if (st->has13) list_front(st->outl + s * n, &st->outlen[s], st->rk13 + s * n, (int32_t)r);
	if (st->has14) list_front(st->inl + r * n, &st->inlen[r], st->rk14 + r * n, (int32_t)s);
	if (st->NS > 0) {
		if (st->has7 || st->has13) if (state_add(st, s, r)) return 909;
		if (st->has8 || st->has14) if (state_add(st, r, s)) return 909;
	}
	return 0;
}

/* the sparse statistic e of the dyad (j,k) in the current state */
static double sval_one(const Spec *sp, const State *st, int e, nwint j, nwint k) {
	nwint n = st->n;
	switch (e) {
	case 7: return st->ocnt[j] > 0.0 ? (double)st->cij[j * n + k] / st->ocnt[j] : 0.0;
	case 8: return st->icnt[j] > 0.0 ? (double)st->cij[k * n + j] / st->icnt[j] : 0.0;
	case 12: return sp->C[j * n + k];
	case 13: return st->rk13[j * n + k] > 0 ? 1.0 / (double)st->rk13[j * n + k] : 0.0;
	case 14: return st->rk14[j * n + k] > 0 ? 1.0 / (double)st->rk14[j * n + k] : 0.0;
	}
	return 0.0;
}

/* out[j] = sum over k != j of x[k] (prefix and suffix sums, no subtraction) */
static void excl_sum(const double *x, double *out, nwint n) {
	nwint j;
	double run = 0.0;
	for (j = 0; j < n; j++) { out[j] = run; run += x[j]; }
	run = 0.0;
	for (j = n - 1; j >= 0; j--) { out[j] += run; run += x[j]; }
}

/* ------------------------------------------------------------------
   One evaluation. dense = 0: fast evaluator (returns 1 when it gives up), dense = 1: dense evaluator.
   ------------------------------------------------------------------ */
static int run(const Spec *sp, const double *theta, int todo, int dense, double *ll, double *g, double *H, double *Exx) {
	nwint n = sp->n, m = sp->m, i, j, k, pos;
	int P = sp->P, p, q, t, NS = 0, SE[NEFF], slot[NEFF], rc = 0;
	int hA[NEFF], hB[NEFF], hS[NEFF];
	State st;
	double *od, *idg, *td, *buf;
	const double **A, **B;
	double *a, *b, *ea, *eb, *XB1, *XA1, *tmp, *XBw, *ws = NULL;
	double *Esep, *Esup, *xs, *xp, *ys, *Ea, *gacc, *Esep2, *Hsup, *E2;
	double fb = 1.0 / (double)(n - 1), lltot = 0.0;
	int needshare;
	size_t unn = (size_t)n, uP = (size_t)P, wsn;

	for (p = 0; p < P; p++) {
		int e = sp->eff[p];
		hA[p] = part_A(e); hB[p] = part_B(e); hS[p] = part_S(e);
		slot[p] = -1;
		if (hS[p]) { slot[p] = NS; SE[NS++] = p; }
	}
	memset(&st, 0, sizeof(State));
	A = NULL; B = NULL;
	if (state_init(sp, &st, NS)) { state_free(&st); return 909; }
	needshare = 0;
	for (p = 0; p < P; p++) { int e = sp->eff[p]; if (e >= 1 && e <= 6) needshare = 1; }
	/* one workspace: 12 vectors of n (shares, fallback parts, a, b, ea, eb, XB1, XA1, tmp), P vectors XBw, small arrays */
	wsn = unn * 12 + unn * uP + uP * 8 + uP * uP * 3;
	ws = (double *)calloc(wsn, sizeof(double));
	A = (const double **)calloc(uP, sizeof(double *)); B = (const double **)calloc(uP, sizeof(double *));
	if (!ws || !A || !B) { rc = 909; free(ws); free(A); free(B); state_free(&st); return rc; }
	od = ws; idg = od + n; td = idg + n; buf = td + n;          /* buf: 2 vectors */
	a = buf + 2 * n; b = a + n; ea = b + n; eb = ea + n; XB1 = eb + n; XA1 = XB1 + n; tmp = XA1 + n;
	XBw = tmp + n;
	Esep = XBw + unn * uP; Esup = Esep + uP; xs = Esup + uP; xp = xs + uP; ys = xp + uP; Ea = ys + uP; gacc = Ea + uP;
	Esep2 = gacc + uP; Hsup = Esep2 + uP * uP; E2 = Hsup + uP * uP;
	{
		for (p = 0; p < P; p++) {
			int e = sp->eff[p];
			if (e == 9) A[p] = sp->cs;
			if (e == 10) B[p] = sp->cr;
			if (e == 11) { A[p] = sp->ci; B[p] = sp->ci; }
			if (e == 7) A[p] = buf;
			if (e == 8) A[p] = buf + n;
			if (e == 1 || e == 3 || e == 5) A[p] = (e == 1 ? od : (e == 3 ? idg : td));
			if (e == 2 || e == 4 || e == 6) B[p] = (e == 2 ? idg : (e == 4 ? od : td));
		}
		if (todo >= 2) for (p = 0; p < P * P; p++) H[p] = 0.0;
		if (Exx) for (p = 0; p < P; p++) Exx[p] = 0.0;
		for (i = 0; i < m; i++) {
			nwint s = (nwint)sp->ev[2 * i] - 1, r = (nwint)sp->ev[2 * i + 1] - 1;
			double Ma, Mb, Z0 = 0.0, Zc = 0.0, Zt, lr, lsr_sig = 0.0, logZ;
			nwint ja = 0, jb = 0;
			double prior = (double)i;

			if (needshare) {
				for (j = 0; j < n; j++) {
					if (i == 0) { od[j] = fb; idg[j] = fb; td[j] = fb; }
					else {
						od[j] = st.ocnt[j] / prior; idg[j] = st.icnt[j] / prior;
						td[j] = (st.ocnt[j] + st.icnt[j]) / (2.0 * prior);
					}
				}
			}
			for (p = 0; p < P; p++) {
				if (sp->eff[p] == 7) for (j = 0; j < n; j++) buf[j] = st.ocnt[j] == 0.0 ? fb : 0.0;
				if (sp->eff[p] == 8) for (j = 0; j < n; j++) buf[n + j] = st.icnt[j] == 0.0 ? fb : 0.0;
			}
			/* a_j and b_k */
			for (j = 0; j < n; j++) { a[j] = 0.0; b[j] = 0.0; }
			for (p = 0; p < P; p++) {
				if (hA[p]) { const double *u = A[p]; double th = theta[p]; for (j = 0; j < n; j++) a[j] += th * u[j]; }
				if (hB[p]) { const double *w = B[p]; double th = theta[p]; for (j = 0; j < n; j++) b[j] += th * w[j]; }
			}
			/* per sparse dyad: statistics and sigma */
			for (pos = 0; pos < st.np; pos++) {
				nwint pj = st.pj[pos], pk = st.pk[pos];
				double sg = 0.0;
				for (t = 0; t < NS; t++) {
					double v = sval_one(sp, &st, sp->eff[SE[t]], pj, pk);
					st.sval[pos * NS + t] = v;
					sg += theta[SE[t]] * v;
				}
				st.sig[pos] = sg;
			}
			/* the realised dyad */
			for (p = 0; p < P; p++) {
				double x = 0.0;
				if (hA[p]) x += A[p][s];
				if (hB[p]) x += B[p][r];
				if (hS[p]) { double v = sval_one(sp, &st, sp->eff[p], s, r); x += v; lsr_sig += theta[p] * v; }
				xs[p] = x;
			}
			lr = a[s] + b[r] + lsr_sig;
			for (p = 0; p < P; p++) { Ea[p] = 0.0; }
			for (p = 0; p < P * P; p++) { E2[p] = 0.0; }
			if (!dense) {
				Ma = a[0]; Mb = b[0];
				for (j = 1; j < n; j++) { if (a[j] > Ma) { Ma = a[j]; ja = j; } if (b[j] > Mb) { Mb = b[j]; jb = j; } }
				(void)ja; (void)jb;
				for (j = 0; j < n; j++) { ea[j] = exp(a[j] - Ma); eb[j] = exp(b[j] - Mb); }
				excl_sum(eb, XB1, n);
				excl_sum(ea, XA1, n);
				for (j = 0; j < n; j++) Z0 += ea[j] * XB1[j];
				if (!(Z0 > 1e-250) || !isfinite(Z0)) { rc = 1; goto done; }
				/* separable moments */
				for (p = 0; p < P; p++) {
					double s1 = 0.0;
					if (hA[p]) { const double *u = A[p]; for (j = 0; j < n; j++) s1 += ea[j] * u[j] * XB1[j]; }
					if (hB[p]) { const double *w = B[p]; for (j = 0; j < n; j++) s1 += eb[j] * w[j] * XA1[j]; }
					Esep[p] = s1;
				}
				if (todo >= 2 || Exx) {
					for (p = 0; p < P; p++) if (hB[p]) {
						const double *w = B[p];
						for (j = 0; j < n; j++) tmp[j] = eb[j] * w[j];
						excl_sum(tmp, XBw + (size_t)p * n, n);
					}
					for (p = 0; p < P; p++) for (q = p; q < P; q++) {
						double s2 = 0.0;
						if (hA[p] && hA[q]) { const double *u = A[p], *v = A[q]; for (j = 0; j < n; j++) s2 += ea[j] * u[j] * v[j] * XB1[j]; }
						if (hB[p] && hB[q]) { const double *u = B[p], *v = B[q]; for (j = 0; j < n; j++) s2 += eb[j] * u[j] * v[j] * XA1[j]; }
						if (hA[p] && hB[q]) { const double *u = A[p]; const double *xw = XBw + (size_t)q * n; for (j = 0; j < n; j++) s2 += ea[j] * u[j] * xw[j]; }
						if (hB[p] && hA[q]) { const double *u = A[q]; const double *xw = XBw + (size_t)p * n; for (j = 0; j < n; j++) s2 += ea[j] * u[j] * xw[j]; }
						Esep2[(size_t)p * P + q] = s2;
					}
				}
				/* the sparse correction */
				for (p = 0; p < P; p++) Esup[p] = 0.0;
				for (p = 0; p < P * P; p++) Hsup[p] = 0.0;
				for (pos = 0; pos < st.np; pos++) {
					nwint pj = st.pj[pos], pk = st.pk[pos];
					double mu = ea[pj] * eb[pk], sg = st.sig[pos], ex, e1, om;
					if (sg > 700.0) { rc = 1; goto done; }
					ex = exp(sg); e1 = expm1(sg); om = mu * ex;
					Zc += mu * e1;
					for (p = 0; p < P; p++) {
						double x = 0.0;
						if (hA[p]) x += A[p][pj];
						if (hB[p]) x += B[p][pk];
						xp[p] = x;
						ys[p] = x + (hS[p] ? st.sval[pos * NS + slot[p]] : 0.0);
						Esup[p] += om * ys[p] - mu * x;
					}
					if (todo >= 2 || Exx) {
						for (p = 0; p < P; p++) for (q = p; q < P; q++)
							Hsup[(size_t)p * P + q] += om * ys[p] * ys[q] - mu * xp[p] * xp[q];
					}
				}
				Zt = Z0 + Zc;
				if (!(Zt > 1e-6 * Z0) || !isfinite(Zt)) { rc = 1; goto done; }
				for (p = 0; p < P; p++) Ea[p] = (Esep[p] + Esup[p]) / Zt;
				if (todo >= 2 || Exx) for (p = 0; p < P; p++) for (q = p; q < P; q++) E2[(size_t)p * P + q] = (Esep2[(size_t)p * P + q] + Hsup[(size_t)p * P + q]) / Zt;
				logZ = Ma + Mb + log(Zt);
			}
			else {
				/* dense evaluator: all dyads j != k, one global shift */
				double mx = -1e308, Z = 0.0;
				for (j = 0; j < n; j++) for (k = 0; k < n; k++) {
					double v;
					int32_t ps;
					if (j == k) continue;
					v = a[j] + b[k];
					ps = st.pidx ? st.pidx[j * n + k] : -1;
					if (ps >= 0) v += st.sig[ps];
					if (v > mx) mx = v;
				}
				for (j = 0; j < n; j++) for (k = 0; k < n; k++) {
					double v, w;
					int32_t ps;
					if (j == k) continue;
					v = a[j] + b[k];
					ps = st.pidx ? st.pidx[j * n + k] : -1;
					if (ps >= 0) v += st.sig[ps];
					w = exp(v - mx);
					Z += w;
					if (todo >= 1) {
						for (p = 0; p < P; p++) {
							double x = 0.0;
							if (hA[p]) x += A[p][j];
							if (hB[p]) x += B[p][k];
							if (hS[p] && ps >= 0) x += st.sval[(size_t)ps * NS + slot[p]];
							ys[p] = x;
							Ea[p] += w * x;
						}
						if (todo >= 2 || Exx) for (p = 0; p < P; p++) for (q = p; q < P; q++) E2[(size_t)p * P + q] += w * ys[p] * ys[q];
					}
				}
				if (!(Z > 0.0) || !isfinite(Z)) { rc = 2; goto done; }
				for (p = 0; p < P; p++) Ea[p] /= Z;
				if (todo >= 2 || Exx) for (p = 0; p < P; p++) for (q = p; q < P; q++) E2[(size_t)p * P + q] /= Z;
				logZ = mx + log(Z);
			}
			lltot += lr - logZ;
			if (todo >= 1) for (p = 0; p < P; p++) gacc[p] += xs[p] - Ea[p];
			if (todo >= 2) for (p = 0; p < P; p++) for (q = p; q < P; q++) H[p * P + q] -= E2[(size_t)p * P + q] - Ea[p] * Ea[q];
			if (Exx) for (p = 0; p < P; p++) Exx[p] += E2[(size_t)p * P + p];
			if (state_update(&st, s, r)) { rc = 909; goto done; }
		}
		*ll = lltot;
		for (p = 0; p < P; p++) g[p] = gacc[p];
		if (todo >= 2) for (p = 0; p < P; p++) for (q = p + 1; q < P; q++) H[q * P + p] = H[p * P + q];
	}
done:
	free(ws); free(A); free(B);
	state_free(&st);
	return rc;
}

/* ------------------------------------------------------------------
   Blob reading
   ------------------------------------------------------------------ */
static int spec_read(Spec *sp, nwint L) {
	nwint i, pos;
	int k;
	memset(sp, 0, sizeof(Spec));
	sp->blob = (double *)malloc((size_t)L * sizeof(double));
	if (!sp->blob) return 909;
	for (i = 0; i < L; i++) {
		ST_double v;
		SF_vdata(1, (ST_int)(i + 1), &v);
		sp->blob[i] = v;
	}
	if (L < HDR || (int)sp->blob[0] != REM_PROTOCOL) return 198;
	sp->n = (nwint)sp->blob[1];
	sp->m = (nwint)sp->blob[2];
	for (k = 0; k < NEFF; k++) sp->act[k] = sp->blob[3 + k] != 0.0;
	if (sp->n < 3 || sp->m < 1) return 198;
	if (sp->n * sp->n > 2000000000LL) { SF_error("rem_sim: too many actors\n"); return 198; }
	pos = HDR;
	sp->ev = sp->blob + pos; pos += 2 * sp->m;
	sp->cs = sp->blob + pos; pos += sp->n;
	sp->cr = sp->blob + pos; pos += sp->n;
	sp->ci = sp->blob + pos; pos += sp->n;
	if (sp->act[11]) { sp->C = sp->blob + pos; pos += sp->n * sp->n; }
	if (pos != L) return 198;
	for (i = 0; i < sp->m; i++) {
		double a = sp->ev[2 * i], b = sp->ev[2 * i + 1];
		if (!(a >= 1.0 && a <= (double)sp->n && b >= 1.0 && b <= (double)sp->n) || a == b) {
			SF_error("rem_sim: an event has a sender or receiver outside 1..n, or sender == receiver\n");
			return 198;
		}
	}
	sp->P = 0;
	for (k = 0; k < NEFF; k++) if (sp->act[k]) sp->eff[sp->P++] = k + 1;
	return 0;
}

/* ------------------------------------------------------------------
   Plugin entry point
   ------------------------------------------------------------------ */
STDLL stata_call(int argc, char *argv[]) {
	char *argbuf, *tok;
	int code, todo, Pt, k, rc = 0, usedense = 0;
	nwint L;
	double *theta = NULL, *g = NULL, *H = NULL, *Exx = NULL, ll = 0.0;
	Spec sp;

	if (argc < 1) { SF_error("rem_sim: missing argument string\n"); return 198; }
	argbuf = (char *)malloc(strlen(argv[0]) + 1);
	if (!argbuf) return 909;
	strcpy(argbuf, argv[0]);
	tok = strtok(argbuf, " \t");
	code = tok ? (int)atof(tok) : 0;
	if (code == 99) {
		free(argbuf);
		SF_vstore(2, 1, (ST_double)REM_PROTOCOL);
		return 0;
	}
	if (code != 20 && code != 21 && code != 22 && code != 30) {
		free(argbuf);
		SF_error("rem_sim: unknown algorithm code (plugin and package versions do not match)\n");
		return 198;
	}
	{
		char *t1 = strtok(NULL, " \t"), *t2 = strtok(NULL, " \t"), *t3 = strtok(NULL, " \t");
		if (!t1 || !t2 || !t3) { free(argbuf); SF_error("rem_sim: short argument string\n"); return 198; }
		L = (nwint)atof(t1);
		todo = (int)atof(t2);
		Pt = (int)atof(t3);
	}
	if (Pt < 0 || Pt > NEFF) { free(argbuf); return 198; }
	theta = (double *)calloc((size_t)(Pt > 0 ? Pt : 1), sizeof(double));
	g = (double *)calloc((size_t)(Pt > 0 ? Pt : 1), sizeof(double));
	H = (double *)calloc((size_t)(Pt > 0 ? Pt : 1) * (size_t)(Pt > 0 ? Pt : 1), sizeof(double));
	Exx = (double *)calloc((size_t)(Pt > 0 ? Pt : 1), sizeof(double));
	if (!theta || !g || !H || !Exx) { free(argbuf); free(theta); free(g); free(H); free(Exx); return 909; }
	for (k = 0; k < Pt; k++) {
		char *t = strtok(NULL, " \t");
		if (!t) { free(argbuf); free(theta); free(g); free(H); free(Exx); return 198; }
		theta[k] = atof(t);
	}
	free(argbuf);

	rc = spec_read(&sp, L);
	if (rc == 0 && code == 30) {
		/* only the static effects, at theta = 0 */
		int e;
		sp.P = 0;
		for (e = 0; e < NEFF; e++) {
			if (sp.act[e] && !(e == 6 || e == 7 || e == 12 || e == 13)) sp.eff[sp.P++] = e + 1;
		}
		for (k = 0; k < Pt; k++) theta[k] = 0.0;
		todo = 2;
	}
	if (rc == 0 && sp.P != Pt) { SF_error("rem_sim: parameter count does not match the model\n"); rc = 198; }
	if (rc == 0) {
		if (code == 21) { usedense = 1; rc = run(&sp, theta, todo, 1, &ll, g, H, Exx); }
		else {
			rc = run(&sp, theta, todo, 0, &ll, g, H, Exx);
			if (rc == 1 && code != 22) { usedense = 1; rc = run(&sp, theta, todo, 1, &ll, g, H, Exx); }
		}
	}
	if (rc == 1 || rc == 2) {
		/* gave up (code 22) or no finite normaliser: a missing log likelihood */
		SF_vstore(2, 1, SV_missval);
		rc = 0;
	}
	else if (rc == 0) {
		int bad = !isfinite(ll);
		for (k = 0; k < Pt; k++) if (!isfinite(g[k])) bad = 1;
		if (todo >= 2) for (k = 0; k < Pt * Pt; k++) if (!isfinite(H[k])) bad = 1;
		SF_vstore(2, 1, bad ? SV_missval : ll);
		for (k = 0; k < Pt; k++) SF_vstore(2, (ST_int)(2 + k), bad ? SV_missval : g[k]);
		if (todo >= 2) for (k = 0; k < Pt * Pt; k++) SF_vstore(2, (ST_int)(2 + Pt + k), bad ? SV_missval : H[k]);
		for (k = 0; k < Pt; k++) SF_vstore(2, (ST_int)(2 + Pt + Pt * Pt + k), Exx[k]);
		SF_vstore(2, (ST_int)(2 + Pt + Pt * Pt + Pt), (ST_double)usedense);
	}
	free(sp.blob);
	free(theta); free(g); free(H); free(Exx);
	return rc;
}
