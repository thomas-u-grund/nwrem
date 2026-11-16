/*
 * Copyright (C) 2026 Thomas U. Grund
 * This file is part of nwrem, a Stata package derived from the R package 'relevent' (Carter T. Butts; GPL (>= 2)).
 * nwrem is free software: you can redistribute it and/or modify it under the terms of the GNU General
 * Public License, version 3, as published by the Free Software Foundation. It is distributed in the hope
 * that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
 * or FITNESS FOR A PARTICULAR PURPOSE. See the file LICENSE for the full text.
 */
/*
	rem_sim.c -- native (C) log likelihood, gradient and Hessian of the relational event model of nwrem (Butts 2008): the
	ordinal partial likelihood and the waiting-time (interval) likelihood, for the effects listed below.

	Every fit of nwrem runs here: Stata's Mata drives the outer loop (a damped Newton iteration on the exact Hessian, with
	optimize() as the fall-back) and calls this plugin once per evaluation at a given theta. The plugin carries no state between
	calls. The model (events, covariates, risk set) is written ONCE per fit as a block of numbers into the first variable of a
	frame (the "blob", layout below); each call passes the length of the blob, the parameter count and theta in the argument
	string and gets the result in the second variable.

	Argument string: "<code> <L> <todo> <P> <theta_1> ... <theta_P>"
	  code 20  evaluate (fast evaluator; when it gives up, the dense one)
	  code 21  evaluate with the dense evaluator only (tests)
	  code 22  evaluate with the fast evaluator only; log likelihood missing when it gives up (tests)
	  code 30  collinearity check: all parameters of the model (the drop mask of the blob is ignored), theta = 0, Hessian and
	           uncentred second moments
	  code 99  report the protocol number (row 1 of variable 2)
	Result (variable 2): row 1 = log likelihood (missing when no evaluator gives a finite value), rows 2..P+1 = gradient,
	then the P x P Hessian by rows (todo = 2), then P values E[X_p^2] summed over the events (used by code 30), then a flag
	(0 = fast evaluator, 1 = dense evaluator) in the last row of the result block: row 2 + P + P*P + P.

	Blob (doubles; L = total length):
	  [0] protocol  [1] n (actors)  [2] m (events)  [3] likelihood (0 ordinal, 1 interval)  [4] conditioned events k  [5] length
	  of the final (censored) interval  [6..9] number of columns of covsnd, covrec, covint, covevent  [10] a risk set mask
	  follows  [11] actor windows follow  [12] a drop mask follows  [13..15] reserved  [16..16+NEFF) active flags of the effects
	  (HDR = 48 numbers),
	  then the events: m rows of (sender, receiver, time since the previous event), 1-based actors, sorted by time (the caller
	  sorts; the order of events with equal time is the order in which they are listed; the third column is used by the interval
	  likelihood only),
	  then covsnd, covrec, covint (n values per column) and covevent (an n x n matrix per column), then (when flagged) the risk
	  set mask (n x n, 0 = the dyad cannot occur), the actor windows (first and last event number, 1-based, at which an actor
	  is in the risk set; event number m+1 is the end of the observation) and the drop mask (one flag per parameter of the
	  full model: 1 = the parameter is left out of the model).

	The effects, in this order (this is also the order of theta; the covariate effects 9 to 12 and the fixed effects 19 to 21
	have several parameters, in the order of their columns / of the actors 2..n):
	   1 nodsnd 2 nidrec 3 nidsnd 4 nodrec 5 ntdegsnd 6 ntdegrec 7 frpsndsnd 8 frrecsnd 9 covsnd 10 covrec 11 covint
	  12 covevent 13 rsndsnd 14 rrecsnd 15 otpsnd 16 itpsnd 17 ospsnd 18 ispsnd 19 fesnd 20 ferec 21 feint
	  22 psabba 23 psabby 24 psabxa 25 psabxb 26 psabxy 27 psabay
	with the statistics of R's relevent (cscripts/ref_rem_mata.do holds the Mata reference of effects 1 to 14, the tests of the
	others compare with relevent itself). The one exception is ospsnd: relevent (1.2-1) adds the shared out-partners of a pair
	twice to the first actor of the pair and never to the second; the plugin uses the symmetric statistic documented there.

	The log rate of the dyad (j,k), j != k, at an event is the sum over the effects of theta_e X_e(j,k). The ordinal likelihood is
	the softmax probability of the observed dyad over the dyads of the risk set; the interval likelihood is the sum over the
	events of  log rate(observed) - dt * sum of the rates of the risk set  plus the survival term of the final interval.
	Every statistic is a sum X_e(j,k) = U_e[j] + W_e[k] + S_e(j,k) of a part of the sender, a part of the receiver and a sparse
	dyadic part S that is non-zero only for dyads in contact so far (frpsndsnd, frrecsnd, rsndsnd, rrecsnd, the triadic effects),
	for non-zero cells of covevent, or for the dyads of the previous event (participation shifts). The normaliser is then
	Z = (sum_j e^a_j)(sum_k e^b_k) minus the diagonal, plus a correction over the sparse dyads only: O(n + number of dyads in
	contact) per event instead of O(n^2). Dyads that are not in the risk set (the mask) are sparse dyads whose weight is zero.
	The sums that leave out the diagonal are formed from prefix and suffix sums (no cancellation). The fast evaluator gives up
	(and the dense O(n^2) evaluator with one global shift is used) when exp() overflows, a normaliser underflows, or the
	correction cancels more than six digits; the fixed effects are always evaluated densely.
	Counts, the recency ranks of rsndsnd / rrecsnd (move-to-front lists), the weighted two-path and shared-partner counts and
	the list of dyads in contact are updated after every event; none of it depends on theta.
*/

#include "stplugin.h"
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <stdint.h>

typedef int64_t nwint;

#ifndef REM_PROTOCOL
#define REM_PROTOCOL 2   /* raise together with REM_PROTOCOL_NEEDED() in unw_rem.do; the tests build a plugin with another number */
#endif
#define HDR 48
#define NEFF 27

typedef struct { int eff, col; } Par;

typedef struct {
	nwint n, m;
	int mode, ncond;
	double dtc;
	int ncs, ncr, nci, nce;
	int act[NEFF];
	int hasmask, haswin, hasdrop;
	const double *ev;                 /* m x 3 */
	const double *cs, *cr, *ci;       /* ncs*n, ncr*n, nci*n */
	const double *C;                  /* nce * n * n */
	const double *mask;               /* n x n or NULL */
	const double *lo, *hi;            /* n each or NULL */
	const double *drop;               /* Pall flags or NULL */
	int Pall;
	Par *pall;
	int P;
	Par *par;                         /* the parameters of the model that is evaluated */
	double *blob;
} Spec;

typedef struct {
	nwint len, cap;
	int32_t *k;
	double *sig, *ex, *e1;
	double *sv;                       /* len * NS: statistics of the S-type parameters */
	unsigned char *excl, *tch;
} Row;

typedef struct {
	nwint n;
	int has7, has8, has12, has13, has14, has15, has16, has17, has18, hasps, transient, hasmask;
	double *ocnt, *icnt;
	int32_t *cij, *rk13, *rk14, *outl, *inl, *outlen, *inlen, *top, *sop, *sip;
	int32_t *pidx;                    /* n*n: index of the dyad in its row of sparse dyads, -1 = not in the list */
	Row *row;
	nwint np, nbig;                   /* number of sparse dyads; number with sigma > 700 */
	int hasprev; nwint pa, pb;        /* the previous event (participation shifts) */
	nwint *tj, *tix; nwint nt, tcap;  /* dyads touched by the last event (to be refreshed) */
	int NS, P;
	int *sidx;                        /* parameter index of the s-th S-type parameter */
	const Spec *sp;
	const double *theta;
} State;

static int is_A(int e) { return e == 1 || e == 3 || e == 5 || e == 7 || e == 8 || e == 9 || e == 11 || e == 23 || e == 26 || e == 27; }
static int is_B(int e) { return e == 2 || e == 4 || e == 6 || e == 10 || e == 11 || e == 24 || e == 25 || e == 26; }
static int is_S(int e) { return e == 7 || e == 8 || (e >= 12 && e <= 18) || (e >= 22 && e <= 27); }
static int is_FE(int e) { return e >= 19 && e <= 21; }

static void row_free(Row *r) {
	free(r->k); free(r->sig); free(r->ex); free(r->e1); free(r->sv); free(r->excl); free(r->tch);
	memset(r, 0, sizeof(Row));
}

static void state_free(State *st) {
	nwint j;
	if (st->row) for (j = 0; j < st->n; j++) row_free(&st->row[j]);
	free(st->row);
	free(st->ocnt); free(st->icnt); free(st->cij); free(st->rk13); free(st->rk14); free(st->outl); free(st->inl);
	free(st->outlen); free(st->inlen); free(st->top); free(st->sop); free(st->sip); free(st->pidx); free(st->tj); free(st->tix);
	free(st->sidx);
	memset(st, 0, sizeof(State));
}

/* append the dyad (j,k) to the list of sparse dyads (when it is not in it); *ix = its index in the row */
static int row_add(State *st, nwint j, nwint k, nwint *ix) {
	int32_t *slot = &st->pidx[j * st->n + k];
	Row *r;
	if (*slot >= 0) { *ix = *slot; return 0; }
	r = &st->row[j];
	if (r->len >= r->cap) {
		nwint nc = r->cap < 8 ? 8 : r->cap * 2;
		void *t;
		t = realloc(r->k, (size_t)nc * sizeof(int32_t)); if (!t) return 909; r->k = (int32_t *)t;
		t = realloc(r->sig, (size_t)nc * sizeof(double)); if (!t) return 909; r->sig = (double *)t;
		t = realloc(r->ex, (size_t)nc * sizeof(double)); if (!t) return 909; r->ex = (double *)t;
		t = realloc(r->e1, (size_t)nc * sizeof(double)); if (!t) return 909; r->e1 = (double *)t;
		t = realloc(r->excl, (size_t)nc); if (!t) return 909; r->excl = (unsigned char *)t;
		t = realloc(r->tch, (size_t)nc); if (!t) return 909; r->tch = (unsigned char *)t;
		if (st->NS > 0) { t = realloc(r->sv, (size_t)nc * (size_t)st->NS * sizeof(double)); if (!t) return 909; r->sv = (double *)t; }
		r->cap = nc;
	}
	r->k[r->len] = (int32_t)k;
	r->sig[r->len] = 0.0; r->ex[r->len] = 1.0; r->e1[r->len] = 0.0;
	r->excl[r->len] = (unsigned char)(st->hasmask && st->sp->mask[j * st->n + k] == 0.0);
	r->tch[r->len] = 0;
	if (st->NS > 0) memset(r->sv + (size_t)r->len * (size_t)st->NS, 0, (size_t)st->NS * sizeof(double));
	*slot = (int32_t)r->len;
	*ix = r->len;
	r->len++;
	st->np++;
	return 0;
}

static int touch(State *st, nwint j, nwint k) {
	nwint ix;
	Row *r;
	if (row_add(st, j, k, &ix)) return 909;
	r = &st->row[j];
	if (!r->tch[ix]) {
		r->tch[ix] = 1;
		if (st->nt >= st->tcap) {
			nwint nc = st->tcap < 64 ? 64 : st->tcap * 2;
			nwint *a = (nwint *)realloc(st->tj, (size_t)nc * sizeof(nwint));
			nwint *b;
			if (!a) return 909;
			st->tj = a;
			b = (nwint *)realloc(st->tix, (size_t)nc * sizeof(nwint));
			if (!b) return 909;
			st->tix = b;
			st->tcap = nc;
		}
		st->tj[st->nt] = j; st->tix[st->nt] = ix; st->nt++;
	}
	return 0;
}

static void list_clear(State *st) {
	nwint j, c;
	for (j = 0; j < st->n; j++) {
		Row *r = &st->row[j];
		for (c = 0; c < r->len; c++) st->pidx[j * st->n + r->k[c]] = -1;
		r->len = 0;
	}
	st->np = 0; st->nbig = 0; st->nt = 0;
}

static int state_init(const Spec *sp, State *st, const double *theta) {
	nwint n = sp->n;
	size_t nn = (size_t)n * (size_t)n, un = (size_t)n;
	int p, e, needsparse = 0, persistent = 0;
	memset(st, 0, sizeof(State));
	st->n = n;
	st->P = sp->P;
	st->sp = sp;
	st->theta = theta;
	st->sidx = (int *)calloc((size_t)(sp->P > 0 ? sp->P : 1), sizeof(int));
	if (!st->sidx) return 909;
	for (p = 0; p < sp->P; p++) {
		e = sp->par[p].eff;
		if (is_S(e)) { st->sidx[st->NS++] = p; needsparse = 1; }
		if (e == 7) st->has7 = 1;
		if (e == 8) st->has8 = 1;
		if (e == 12) st->has12 = 1;
		if (e == 13) st->has13 = 1;
		if (e == 14) st->has14 = 1;
		if (e == 15) st->has15 = 1;
		if (e == 16) st->has16 = 1;
		if (e == 17) st->has17 = 1;
		if (e == 18) st->has18 = 1;
		if (e >= 22) st->hasps = 1;
		if (is_S(e) && !(e >= 22)) persistent = 1;
	}
	st->hasmask = sp->hasmask;
	if (sp->hasmask) needsparse = 1;
	st->transient = (st->hasps && !persistent && !sp->hasmask);
	st->ocnt = (double *)calloc(un, sizeof(double));
	st->icnt = (double *)calloc(un, sizeof(double));
	if (!st->ocnt || !st->icnt) return 909;
	if (st->has7 || st->has8 || st->has15 || st->has16 || st->has17 || st->has18) {
		st->cij = (int32_t *)calloc(nn, sizeof(int32_t));
		if (!st->cij) return 909;
	}
	if (st->has15 || st->has16) { st->top = (int32_t *)calloc(nn, sizeof(int32_t)); if (!st->top) return 909; }
	if (st->has17) { st->sop = (int32_t *)calloc(nn, sizeof(int32_t)); if (!st->sop) return 909; }
	if (st->has18) { st->sip = (int32_t *)calloc(nn, sizeof(int32_t)); if (!st->sip) return 909; }
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
	if (needsparse) {
		size_t q;
		st->pidx = (int32_t *)malloc(nn * sizeof(int32_t));
		st->row = (Row *)calloc(un, sizeof(Row));
		if (!st->pidx || !st->row) return 909;
		for (q = 0; q < nn; q++) st->pidx[q] = -1;
		if (st->has12) {
			nwint j, k;
			int c;
			for (j = 0; j < n; j++) for (k = 0; k < n; k++) {
				int any = 0;
				if (j == k) continue;
				for (c = 0; c < sp->nce; c++) if (sp->C[(size_t)c * nn + (size_t)(j * n + k)] != 0.0) any = 1;
				if (any) { nwint ix; if (row_add(st, j, k, &ix)) return 909; }
			}
		}
		if (sp->hasmask) {
			nwint j, k;
			for (j = 0; j < n; j++) for (k = 0; k < n; k++) {
				if (j != k && sp->mask[j * n + k] == 0.0) { nwint ix; if (row_add(st, j, k, &ix)) return 909; }
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

/* state after the event (s,r); the dyads whose statistics changed outside the rows of s and r are touched */
static int state_update(State *st, nwint s, nwint r) {
	nwint n = st->n, l;
	int32_t cnew = st->cij ? st->cij[s * n + r] + 1 : 0;
	st->nt = 0;
	if (st->has15 || st->has16) {
		/* weighted outbound two-paths top[j][l] = sum_k min(c[j][k], c[k][l]), l != j */
		for (l = 0; l < n; l++) {
			if (l != s && st->cij[r * n + l] >= cnew) {
				st->top[s * n + l]++;
				if (st->has15) if (touch(st, s, l)) return 909;
				if (st->has16) if (touch(st, l, s)) return 909;
			}
			if (l != r && st->cij[l * n + s] >= cnew) {
				st->top[l * n + r]++;
				if (st->has15) if (touch(st, l, r)) return 909;
				if (st->has16) if (touch(st, r, l)) return 909;
			}
		}
	}
	if (st->has17) {
		for (l = 0; l < n; l++) if (l != s && st->cij[l * n + r] >= cnew) {
			st->sop[s * n + l]++; st->sop[l * n + s]++;
			if (touch(st, s, l)) return 909;
			if (touch(st, l, s)) return 909;
		}
	}
	if (st->has18) {
		for (l = 0; l < n; l++) if (l != r && st->cij[s * n + l] >= cnew) {
			st->sip[r * n + l]++; st->sip[l * n + r]++;
			if (touch(st, r, l)) return 909;
			if (touch(st, l, r)) return 909;
		}
	}
	st->ocnt[s] += 1.0;
	st->icnt[r] += 1.0;
	if (st->cij) st->cij[s * n + r]++;
	if (st->has13) list_front(st->outl + s * n, &st->outlen[s], st->rk13 + s * n, (int32_t)r);
	if (st->has14) list_front(st->inl + r * n, &st->inlen[r], st->rk14 + r * n, (int32_t)s);
	if (st->has7 || st->has13) if (touch(st, s, r)) return 909;
	if (st->has8 || st->has14) if (touch(st, r, s)) return 909;
	if (st->hasps) {
		if (st->transient) {
			list_clear(st);
		}
		else if (st->hasprev) {
			if (touch(st, st->pa, st->pb)) return 909;
			if (touch(st, st->pb, st->pa)) return 909;
		}
		st->hasprev = 1; st->pa = s; st->pb = r;
		if (touch(st, s, r)) return 909;
		if (touch(st, r, s)) return 909;
	}
	return 0;
}

/* the sparse statistic of the parameter with effect e and column col at the dyad (j,k) in the current state */
static double sval_one(const Spec *sp, const State *st, int e, int col, nwint j, nwint k) {
	nwint n = st->n;
	switch (e) {
	case 7: return st->ocnt[j] > 0.0 ? (double)st->cij[j * n + k] / st->ocnt[j] : 0.0;
	case 8: return st->icnt[j] > 0.0 ? (double)st->cij[k * n + j] / st->icnt[j] : 0.0;
	case 12: return sp->C[(size_t)col * (size_t)n * (size_t)n + (size_t)(j * n + k)];
	case 13: return st->rk13[j * n + k] > 0 ? 1.0 / (double)st->rk13[j * n + k] : 0.0;
	case 14: return st->rk14[j * n + k] > 0 ? 1.0 / (double)st->rk14[j * n + k] : 0.0;
	case 15: return (double)st->top[j * n + k];
	case 16: return (double)st->top[k * n + j];
	case 17: return (double)st->sop[j * n + k];
	case 18: return (double)st->sip[j * n + k];
	}
	if (e >= 22 && st->hasprev) {
		nwint a = st->pa, b = st->pb;
		switch (e) {
		case 22: return (j == b && k == a) ? 1.0 : 0.0;                    /* AB-BA */
		case 23: return (j == b && k == a) ? -1.0 : 0.0;                   /* AB-BY: sender B, receiver not A */
		case 24: return (j == b && k == a) ? -1.0 : 0.0;                   /* AB-XA: receiver A, sender not B */
		case 25: return (j == a && k == b) ? -1.0 : 0.0;                   /* AB-XB: receiver B, sender not A */
		case 26: return ((j == a && k == b) || (j == b && k == a)) ? 1.0 : 0.0;   /* AB-XY */
		case 27: return (j == a && k == b) ? -1.0 : 0.0;                   /* AB-AY: sender A, receiver not B */
		}
	}
	return 0.0;
}

static void refresh_cell(State *st, nwint j, nwint ix) {
	Row *r = &st->row[j];
	nwint k = r->k[ix];
	double sg = 0.0, *sv = r->sv + (size_t)ix * (size_t)st->NS;
	int q;
	if (r->sig[ix] > 700.0) st->nbig--;
	for (q = 0; q < st->NS; q++) {
		int p = st->sidx[q];
		double v = sval_one(st->sp, st, st->sp->par[p].eff, st->sp->par[p].col, j, k);
		sv[q] = v;
		sg += st->theta[p] * v;
	}
	r->tch[ix] = 0;
	if (r->excl[ix]) { r->sig[ix] = 0.0; r->ex[ix] = 0.0; r->e1[ix] = -1.0; return; }
	r->sig[ix] = sg;
	if (sg > 700.0) { r->ex[ix] = 0.0; r->e1[ix] = 0.0; st->nbig++; }   /* the fast evaluator gives up when it meets sigma > 700 */
	else { double e1 = expm1(sg); r->e1[ix] = e1; r->ex[ix] = 1.0 + e1; }
}

static void refresh_row(State *st, nwint j) {
	nwint c;
	for (c = 0; c < st->row[j].len; c++) refresh_cell(st, j, c);
}

static void refresh_touched(State *st) {
	nwint t;
	for (t = 0; t < st->nt; t++) refresh_cell(st, st->tj[t], st->tix[t]);
	st->nt = 0;
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
   needE2 = 1: the second moments are computed (Hessian, or the uncentred moments of the dependence check).
   ------------------------------------------------------------------ */
static int run(const Spec *sp, const double *theta, int todo, int dense, int wantexx, double *ll, double *g, double *H, double *Exx) {
	nwint n = sp->n, m = sp->m, i, j, k, c;
	int P = sp->P, p, q, rc = 0, nFE = 0, needE2 = (todo >= 2 || wantexx), interval = (sp->mode == 1);
	char *hA, *hB, *hS;
	int *fesnd, *ferec, *feint;       /* parameter index of the fixed effect of an actor, -1 = none */
	int *bl, *sl, nb = 0, ns = 0;     /* compact lists: B-type and S-type parameters */
	int *bpos, *spos;
	State st;
	double *ws = NULL, *wsd = NULL;
	const double **A, **B;
	double *od, *idg, *td, *buf7, *buf8;
	double *a, *b, *ea, *eb, *XB1, *XA1, *tmp, *zero, *XBw, *IBt;
	double *Esep, *Esup, *xs, *Ea, *gacc, *Esep2, *Hsup, *E2, *ys, *psbuf;
	char *actS;
	double fb = 1.0 / (double)(n - 1), lltot = 0.0;
	int needshare = 0, haveA = 0;
	size_t unn = (size_t)n, uP = (size_t)P, wsn, uP2 = (size_t)P * (size_t)P;
	double *mb, *mbb, *ms, *msb, *mss, *iaF, *mbF, *msF;
	size_t nbb, nss, nsb;

	hA = (char *)calloc(uP + 1, 1); hB = (char *)calloc(uP + 1, 1); hS = (char *)calloc(uP + 1, 1);
	bl = (int *)calloc(uP + 1, sizeof(int)); sl = (int *)calloc(uP + 1, sizeof(int));
	bpos = (int *)calloc(uP + 1, sizeof(int)); spos = (int *)calloc(uP + 1, sizeof(int));
	fesnd = (int *)malloc(unn * sizeof(int)); ferec = (int *)malloc(unn * sizeof(int)); feint = (int *)malloc(unn * sizeof(int));
	A = (const double **)calloc(uP + 1, sizeof(double *)); B = (const double **)calloc(uP + 1, sizeof(double *));
	if (!hA || !hB || !hS || !bl || !sl || !bpos || !spos || !fesnd || !ferec || !feint || !A || !B) {
		free(hA); free(hB); free(hS); free(bl); free(sl); free(bpos); free(spos); free(fesnd); free(ferec); free(feint); free(A); free(B);
		return 909;
	}
	for (j = 0; j < n; j++) { fesnd[j] = -1; ferec[j] = -1; feint[j] = -1; }
	for (p = 0; p < P; p++) {
		int e = sp->par[p].eff;
		hA[p] = (char)is_A(e); hB[p] = (char)is_B(e); hS[p] = (char)is_S(e);
		bpos[p] = -1; spos[p] = -1;
		if (hB[p]) { bpos[p] = nb; bl[nb++] = p; }
		if (hS[p]) { spos[p] = ns; sl[ns++] = p; }
		if (hA[p]) haveA = 1;
		if (e == 19) { fesnd[sp->par[p].col] = p; nFE++; }
		if (e == 20) { ferec[sp->par[p].col] = p; nFE++; }
		if (e == 21) { feint[sp->par[p].col] = p; nFE++; }
		if (e >= 1 && e <= 6) needshare = 1;
	}
	(void)haveA;
	nbb = (size_t)nb * (size_t)(nb + 1) / 2; nss = (size_t)ns * (size_t)(ns + 1) / 2; nsb = (size_t)ns * (size_t)nb;
	memset(&st, 0, sizeof(State));
	if (state_init(sp, &st, theta)) { state_free(&st); rc = 909; goto fin; }
	if (st.row) for (j = 0; j < n; j++) refresh_row(&st, j);
	if (nFE > 0 && !dense) { rc = 1; goto fin; }       /* the fast evaluator does not do the fixed effects */
	/* one workspace: shares, fallback vectors, a, b, ea, eb, XB1, XA1, tmp, zero, XBw (P vectors), small arrays */
	wsn = unn * 16 + unn * uP * 2 + unn * (size_t)(nb + 1) + uP * 12 + uP2 * 4 + (size_t)nbb + (size_t)nss + nsb + 64 + unn * 8;
	ws = (double *)calloc(wsn, sizeof(double));
	psbuf = (double *)calloc(unn * uP * 2 + 1, sizeof(double));      /* participation-shift vectors: A and B part of each parameter */
	actS = (char *)calloc(unn + 1, 1);
	if (!ws || !psbuf || !actS) { free(ws); free(psbuf); free(actS); rc = 909; goto fin; }
	od = ws; idg = od + n; td = idg + n; buf7 = td + n; buf8 = buf7 + n;
	a = buf8 + n; b = a + n; ea = b + n; eb = ea + n; XB1 = eb + n; XA1 = XB1 + n; tmp = XA1 + n; zero = tmp + n;
	XBw = zero + n;                                   /* P vectors of n */
	IBt = XBw + unn * uP;                             /* n x nb */
	Esep = IBt + unn * (size_t)(nb + 1);
	Esup = Esep + uP; xs = Esup + uP; Ea = xs + uP; gacc = Ea + uP; ys = gacc + uP;
	Esep2 = ys + uP; Hsup = Esep2 + uP2; E2 = Hsup + uP2;
	mb = E2 + uP2; mbb = mb + (size_t)(nb + 1); ms = mbb + nbb + 1; msb = ms + (size_t)(ns + 1); mss = msb + nsb + 1;
	iaF = mss + nss + 1; mbF = iaF + uP + 1; msF = mbF + uP + 1;
	wsd = msF + uP + 1;
	(void)wsd; (void)tmp;
	{
		for (p = 0; p < P; p++) {
			int e = sp->par[p].eff, col = sp->par[p].col;
			if (e == 9) A[p] = sp->cs + (size_t)col * unn;
			if (e == 10) B[p] = sp->cr + (size_t)col * unn;
			if (e == 11) { A[p] = sp->ci + (size_t)col * unn; B[p] = A[p]; }
			if (e == 7) A[p] = buf7;
			if (e == 8) A[p] = buf8;
			if (e == 1 || e == 3 || e == 5) A[p] = (e == 1 ? od : (e == 3 ? idg : td));
			if (e == 2 || e == 4 || e == 6) B[p] = (e == 2 ? idg : (e == 4 ? od : td));
			if (e >= 22) {
				if (hA[p]) A[p] = psbuf + (size_t)p * unn * 2;
				if (hB[p]) B[p] = psbuf + (size_t)p * unn * 2 + unn;
			}
		}
		if (todo >= 2) for (p = 0; p < P * P; p++) H[p] = 0.0;
		if (Exx) for (p = 0; p < P; p++) Exx[p] = 0.0;
		for (p = 0; p < P; p++) gacc[p] = 0.0;
		for (i = 0; i <= m; i++) {
			int isev = (i < m), counted;
			nwint s = 0, r = 0, ja;
			double Ma, Mb, Z0 = 0.0, Zc = 0.0, Zt, lr = 0.0, lsr_sig = 0.0, logZ, dt = 0.0, idx = (double)(i + 1);
			double prior = (double)i;
			int nact = 0, nactr = 0;

			if (i == m && !(interval && sp->dtc > 0.0)) break;
			counted = (i >= sp->ncond);
			if (isev) { s = (nwint)sp->ev[3 * i] - 1; r = (nwint)sp->ev[3 * i + 1] - 1; dt = sp->ev[3 * i + 2]; }
			else dt = sp->dtc;
			(void)ja;
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
				int e = sp->par[p].eff;
				if (e == 7) for (j = 0; j < n; j++) buf7[j] = st.ocnt[j] == 0.0 ? fb : 0.0;
				if (e == 8) for (j = 0; j < n; j++) buf8[j] = st.icnt[j] == 0.0 ? fb : 0.0;
				if (e >= 22) {
					nwint pa = st.pa, pb = st.pb;
					int hp = st.hasprev;
					double *ua = hA[p] ? psbuf + (size_t)p * unn * 2 : NULL, *wb = hB[p] ? psbuf + (size_t)p * unn * 2 + unn : NULL;
					if (ua) for (j = 0; j < n; j++) ua[j] = 0.0;
					if (wb) for (j = 0; j < n; j++) wb[j] = 0.0;
					if (hp) {
						if (e == 23) ua[pb] = 1.0;
						if (e == 27) ua[pa] = 1.0;
						if (e == 24) wb[pa] = 1.0;
						if (e == 25) wb[pb] = 1.0;
						if (e == 26) {
							for (j = 0; j < n; j++) ua[j] = 1.0;
							ua[pa] = 0.0; ua[pb] = 0.0;
							wb[pa] = -1.0; wb[pb] = -1.0;
						}
					}
				}
			}
			/* the risk set: actors in it at this event */
			for (j = 0; j < n; j++) {
				actS[j] = (char)(!sp->haswin || (idx >= sp->lo[j] && idx <= sp->hi[j]));
				if (actS[j]) { nact++; nactr++; }
			}
			(void)nactr;
			/* a_j and b_k */
			for (j = 0; j < n; j++) { a[j] = 0.0; b[j] = 0.0; }
			for (p = 0; p < P; p++) {
				if (hA[p]) { const double *u = A[p]; double th = theta[p]; for (j = 0; j < n; j++) a[j] += th * u[j]; }
				if (hB[p]) { const double *w = B[p]; double th = theta[p]; for (j = 0; j < n; j++) b[j] += th * w[j]; }
			}
			if (nFE > 0) for (j = 1; j < n; j++) {
				if (fesnd[j] >= 0) a[j] += theta[fesnd[j]];
				if (feint[j] >= 0) { a[j] += theta[feint[j]]; b[j] += theta[feint[j]]; }
				if (ferec[j] >= 0) b[j] += theta[ferec[j]];
			}
			/* the realised dyad */
			if (isev) {
				if (!actS[s] || !actS[r]) { rc = 2; goto done; }
				if (sp->hasmask && sp->mask[s * n + r] == 0.0) { rc = 2; goto done; }
				for (p = 0; p < P; p++) {
					double x = 0.0;
					int e = sp->par[p].eff;
					if (hA[p]) x += A[p][s];
					if (hB[p]) x += B[p][r];
					if (hS[p]) { double v = sval_one(sp, &st, e, sp->par[p].col, s, r); x += v; lsr_sig += theta[p] * v; }
					if (e == 19) x = (sp->par[p].col == s) ? 1.0 : 0.0;
					if (e == 20) x = (sp->par[p].col == r) ? 1.0 : 0.0;
					if (e == 21) x = ((sp->par[p].col == s) ? 1.0 : 0.0) + ((sp->par[p].col == r) ? 1.0 : 0.0);
					xs[p] = x;
				}
				lr = a[s] + b[r] + lsr_sig;
			}
			for (p = 0; p < P; p++) Ea[p] = 0.0;
			if (needE2) for (p = 0; p < P * P; p++) E2[p] = 0.0;
			if (!dense) {
				nwint nb0 = 0;
				Ma = -1e308; Mb = -1e308;
				for (j = 0; j < n; j++) {
					if (!actS[j]) continue;
					if (a[j] > Ma) Ma = a[j];
					if (b[j] > Mb) Mb = b[j];
					nb0++;
				}
				if (nb0 == 0) { rc = 1; goto done; }
				for (j = 0; j < n; j++) {
					ea[j] = actS[j] ? exp(a[j] - Ma) : 0.0;
					eb[j] = actS[j] ? exp(b[j] - Mb) : 0.0;
				}
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
				if (needE2) {
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
				for (p = 0; p < P; p++) Esup[p] = 0.0;
				if (needE2) for (p = 0; p < P * P; p++) Hsup[p] = 0.0;
				if (st.nbig > 0) { rc = 1; goto done; }
				if (st.np > 0) {
					for (k = 0; k < n; k++) for (q = 0; q < nb; q++) IBt[(size_t)k * (size_t)nb + (size_t)q] = B[bl[q]][k];
					/* the sparse correction, one sender row at a time: sums over the dyads of the row, then the parts of the sender */
					for (j = 0; j < n; j++) {
						Row *R = &st.row[j];
						double m0 = 0.0, eaj = ea[j];
						if (R->len == 0 || eaj == 0.0) continue;
						for (q = 0; q < nb; q++) mb[q] = 0.0;
						for (q = 0; q < (int)nss; q++) mss[q] = 0.0;
						for (q = 0; q < ns; q++) ms[q] = 0.0;
						if (needE2) {
							for (q = 0; q < (int)nbb; q++) mbb[q] = 0.0;
							for (q = 0; q < (int)nsb; q++) msb[q] = 0.0;
						}
						for (c = 0; c < R->len; c++) {
							int32_t kk = R->k[c];
							double ebk = eb[kk], w1, w2;
							const double *sv, *ib;
							int u, v;
							if (ebk == 0.0) continue;
							w1 = ebk * R->e1[c];
							w2 = ebk * R->ex[c];
							sv = R->sv + (size_t)c * (size_t)ns;
							ib = IBt + (size_t)kk * (size_t)nb;
							m0 += w1;
							for (u = 0; u < nb; u++) mb[u] += w1 * ib[u];
							for (u = 0; u < ns; u++) ms[u] += w2 * sv[u];
							if (needE2) {
								size_t pos = 0;
								for (u = 0; u < nb; u++) { double wu = w1 * ib[u]; for (v = u; v < nb; v++) mbb[pos++] += wu * ib[v]; }
								for (u = 0; u < ns; u++) {
									double wu = w2 * sv[u];
									for (v = 0; v < nb; v++) msb[(size_t)u * nb + v] += wu * ib[v];
								}
								pos = 0;
								for (u = 0; u < ns; u++) { double wu = w2 * sv[u]; for (v = u; v < ns; v++) mss[pos++] += wu * sv[v]; }
							}
							else {
								/* mss is only needed with the second moments */
							}
						}
						Zc += eaj * m0;
						for (p = 0; p < P; p++) {
							double ia = hA[p] ? A[p][j] : 0.0;
							double bsum = hB[p] ? mb[bpos[p]] : 0.0, ssum = hS[p] ? ms[spos[p]] : 0.0;
							iaF[p] = ia; mbF[p] = bsum; msF[p] = ssum;
							Esup[p] += eaj * (ia * m0 + bsum + ssum);
						}
						if (needE2) {
							for (p = 0; p < P; p++) {
								double iap = iaF[p];
								int bp = bpos[p], sp_ = spos[p];
								double *hrow = Hsup + (size_t)p * P;
								for (q = p; q < P; q++) {
									double iaq = iaF[q], t = 0.0;
									int bq = bpos[q], sq = spos[q];
									if (iap != 0.0) { t += iap * (iaq * m0 + mbF[q] + msF[q]); }
									if (iaq != 0.0) { t += iaq * (mbF[p] + msF[p]); }
									if (bp >= 0 && bq >= 0) { int lo = bp < bq ? bp : bq, hi = bp < bq ? bq : bp; t += mbb[(size_t)lo * (size_t)nb - (size_t)lo * (size_t)(lo - 1) / 2 + (size_t)(hi - lo)]; }
									if (sp_ >= 0 && sq >= 0) { int lo = sp_ < sq ? sp_ : sq, hi = sp_ < sq ? sq : sp_; t += mss[(size_t)lo * (size_t)ns - (size_t)lo * (size_t)(lo - 1) / 2 + (size_t)(hi - lo)]; }
									if (sq >= 0 && bp >= 0) t += msb[(size_t)sq * nb + bp];
									if (sp_ >= 0 && bq >= 0) t += msb[(size_t)sp_ * nb + bq];
									hrow[q] += eaj * t;
								}
							}
						}
					}
				}
				Zt = Z0 + Zc;
				if (!(Zt > 1e-6 * Z0) || !isfinite(Zt)) { rc = 1; goto done; }
				for (p = 0; p < P; p++) Ea[p] = (Esep[p] + Esup[p]) / Zt;
				if (needE2) for (p = 0; p < P; p++) for (q = p; q < P; q++) E2[(size_t)p * P + q] = (Esep2[(size_t)p * P + q] + Hsup[(size_t)p * P + q]) / Zt;
				logZ = Ma + Mb + log(Zt);
			}
			else {
				/* dense evaluator: all dyads j != k of the risk set, one global shift */
				double mx = -1e308, Z = 0.0;
				for (j = 0; j < n; j++) {
					if (!actS[j]) continue;
					for (k = 0; k < n; k++) {
						double v;
						int32_t ps;
						if (j == k || !actS[k]) continue;
						ps = st.pidx ? st.pidx[j * n + k] : -1;
						if (ps >= 0 && st.row[j].excl[ps]) continue;
						v = a[j] + b[k];
						if (ps >= 0) v += st.row[j].sig[ps];
						if (v > mx) mx = v;
					}
				}
				if (mx < -1e307) { rc = 2; goto done; }
				for (j = 0; j < n; j++) {
					if (!actS[j]) continue;
					for (k = 0; k < n; k++) {
						double v, w;
						int32_t ps;
						int f[4], nf = 0, u;
						if (j == k || !actS[k]) continue;
						ps = st.pidx ? st.pidx[j * n + k] : -1;
						if (ps >= 0 && st.row[j].excl[ps]) continue;
						v = a[j] + b[k];
						if (ps >= 0) v += st.row[j].sig[ps];
						w = exp(v - mx);
						Z += w;
						if (todo >= 1 || needE2) {
							for (p = 0; p < P; p++) {
								double x = 0.0;
								if (hA[p]) x += A[p][j];
								if (hB[p]) x += B[p][k];
								if (hS[p] && ps >= 0) x += st.row[j].sv[(size_t)ps * (size_t)ns + (size_t)spos[p]];
								ys[p] = x;
							}
							if (nFE > 0) {
								if (j > 0 && fesnd[j] >= 0) f[nf++] = fesnd[j];
								if (j > 0 && feint[j] >= 0) f[nf++] = feint[j];
								if (k > 0 && ferec[k] >= 0) f[nf++] = ferec[k];
								if (k > 0 && feint[k] >= 0) f[nf++] = feint[k];
							}
							for (p = 0; p < P; p++) if (ys[p] != 0.0) Ea[p] += w * ys[p];
							for (u = 0; u < nf; u++) Ea[f[u]] += w;
							if (needE2) {
								for (p = 0; p < P; p++) {
									double yp = ys[p];
									if (yp == 0.0) continue;
									for (q = p; q < P; q++) if (ys[q] != 0.0) E2[(size_t)p * P + q] += w * yp * ys[q];
								}
								for (u = 0; u < nf; u++) {
									int fu = f[u];
									for (p = 0; p < P; p++) {
										double yp = ys[p];
										if (yp == 0.0) continue;
										if (p < fu) E2[(size_t)p * P + fu] += w * yp; else E2[(size_t)fu * P + p] += w * yp;
									}
									for (q = 0; q < nf; q++) {
										int fq = f[q];
										if (fu <= fq) E2[(size_t)fu * P + fq] += w;
									}
								}
							}
						}
					}
				}
				if (!(Z > 0.0) || !isfinite(Z)) { rc = 2; goto done; }
				for (p = 0; p < P; p++) Ea[p] /= Z;
				if (needE2) for (p = 0; p < P; p++) for (q = p; q < P; q++) E2[(size_t)p * P + q] /= Z;
				logZ = mx + log(Z);
			}
			if (counted) {
				if (interval) {
					double rate;
					if (logZ > 700.0) { rc = (dense ? 2 : 1); goto done; }
					rate = dt * exp(logZ);
					lltot += (isev ? lr : 0.0) - rate;
					if (todo >= 1) for (p = 0; p < P; p++) gacc[p] += (isev ? xs[p] : 0.0) - rate * Ea[p];
					if (todo >= 2) for (p = 0; p < P; p++) for (q = p; q < P; q++) H[p * P + q] -= rate * E2[(size_t)p * P + q];
				}
				else {
					lltot += lr - logZ;
					if (todo >= 1) for (p = 0; p < P; p++) gacc[p] += xs[p] - Ea[p];
					if (todo >= 2) for (p = 0; p < P; p++) for (q = p; q < P; q++) H[p * P + q] -= E2[(size_t)p * P + q] - Ea[p] * Ea[q];
					if (Exx) for (p = 0; p < P; p++) Exx[p] += E2[(size_t)p * P + p];
				}
			}
			if (isev) {
				if (state_update(&st, s, r)) { rc = 909; goto done; }
				if (st.row) {
					if (st.has7 || st.has13) refresh_row(&st, s);        /* the dyadic statistics of the other effects are static */
					if (st.has8 || st.has14) refresh_row(&st, r);
					refresh_touched(&st);
				}
			}
		}
		*ll = lltot;
		for (p = 0; p < P; p++) g[p] = gacc[p];
		if (todo >= 2) for (p = 0; p < P; p++) for (q = p + 1; q < P; q++) H[q * P + p] = H[p * P + q];
	}
done:
	free(ws); free(psbuf); free(actS);
fin:
	free(hA); free(hB); free(hS); free(bl); free(sl); free(bpos); free(spos); free(fesnd); free(ferec); free(feint); free(A); free(B);
	state_free(&st);
	return rc;
}

/* ------------------------------------------------------------------
   Blob reading
   ------------------------------------------------------------------ */
static int spec_read(Spec *sp, nwint L) {
	nwint i, pos;
	int k, c, e;
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
	sp->mode = (int)sp->blob[3];
	sp->ncond = (int)sp->blob[4];
	sp->dtc = sp->blob[5];
	sp->ncs = (int)sp->blob[6]; sp->ncr = (int)sp->blob[7]; sp->nci = (int)sp->blob[8]; sp->nce = (int)sp->blob[9];
	sp->hasmask = sp->blob[10] != 0.0; sp->haswin = sp->blob[11] != 0.0; sp->hasdrop = sp->blob[12] != 0.0;
	for (k = 0; k < NEFF; k++) sp->act[k] = sp->blob[16 + k] != 0.0;
	if (sp->n < 2 || sp->m < 1) return 198;
	if (sp->n * sp->n > 2000000000LL) { SF_error("rem_sim: too many actors\n"); return 198; }
	if (sp->mode != 0 && sp->mode != 1) return 198;
	if (sp->ncond < 0 || sp->ncond >= sp->m) return 198;
	if (sp->ncs < 0 || sp->ncr < 0 || sp->nci < 0 || sp->nce < 0) return 198;
	pos = HDR;
	sp->ev = sp->blob + pos; pos += 3 * sp->m;
	sp->cs = sp->blob + pos; pos += sp->n * sp->ncs;
	sp->cr = sp->blob + pos; pos += sp->n * sp->ncr;
	sp->ci = sp->blob + pos; pos += sp->n * sp->nci;
	sp->C = sp->blob + pos; pos += sp->n * sp->n * sp->nce;
	if (sp->hasmask) { sp->mask = sp->blob + pos; pos += sp->n * sp->n; }
	if (sp->haswin) { sp->lo = sp->blob + pos; pos += sp->n; sp->hi = sp->blob + pos; pos += sp->n; }
	/* the parameters of the full model */
	{
		nwint cnt = 0;
		for (e = 1; e <= NEFF; e++) if (sp->act[e - 1]) {
			int nc = 1;
			if (e == 9) nc = sp->ncs; else if (e == 10) nc = sp->ncr; else if (e == 11) nc = sp->nci; else if (e == 12) nc = sp->nce;
			else if (e >= 19 && e <= 21) nc = (int)sp->n - 1;
			cnt += nc;
		}
		sp->Pall = (int)cnt;
		sp->pall = (Par *)calloc((size_t)(cnt > 0 ? cnt : 1), sizeof(Par));
		sp->par = (Par *)calloc((size_t)(cnt > 0 ? cnt : 1), sizeof(Par));
		if (!sp->pall || !sp->par) return 909;
		cnt = 0;
		for (e = 1; e <= NEFF; e++) if (sp->act[e - 1]) {
			int nc = 1;
			if (e == 9) nc = sp->ncs; else if (e == 10) nc = sp->ncr; else if (e == 11) nc = sp->nci; else if (e == 12) nc = sp->nce;
			else if (e >= 19 && e <= 21) nc = (int)sp->n - 1;
			for (c = 0; c < nc; c++) { sp->pall[cnt].eff = e; sp->pall[cnt].col = (e >= 19 && e <= 21) ? c + 1 : c; cnt++; }
		}
	}
	if (sp->hasdrop) { sp->drop = sp->blob + pos; pos += sp->Pall; }
	if (pos != L) return 198;
	for (i = 0; i < sp->m; i++) {
		double a = sp->ev[3 * i], b = sp->ev[3 * i + 1];
		if (!(a >= 1.0 && a <= (double)sp->n && b >= 1.0 && b <= (double)sp->n) || a == b) {
			SF_error("rem_sim: an event has a sender or receiver outside 1..n, or sender == receiver\n");
			return 198;
		}
	}
	sp->P = 0;
	for (k = 0; k < sp->Pall; k++) if (!sp->hasdrop || sp->drop[k] == 0.0) sp->par[sp->P++] = sp->pall[k];
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
	if (Pt < 0 || Pt > 100000) { free(argbuf); return 198; }
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
		/* every parameter of the model, at theta = 0 */
		for (k = 0; k < sp.Pall; k++) sp.par[k] = sp.pall[k];
		sp.P = sp.Pall;
		for (k = 0; k < Pt; k++) theta[k] = 0.0;
		todo = 2;
	}
	if (rc == 0 && sp.P != Pt) { SF_error("rem_sim: parameter count does not match the model\n"); rc = 198; }
	if (rc == 0) {
		int wantexx = (code == 30);
		if (code == 21) { usedense = 1; rc = run(&sp, theta, todo, 1, wantexx, &ll, g, H, Exx); }
		else {
			rc = run(&sp, theta, todo, 0, wantexx, &ll, g, H, Exx);
			if (rc == 1 && code != 22) { usedense = 1; rc = run(&sp, theta, todo, 1, wantexx, &ll, g, H, Exx); }
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
	free(sp.blob); free(sp.pall); free(sp.par);
	free(theta); free(g); free(H); free(Exx);
	return rc;
}
