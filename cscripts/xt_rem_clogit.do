cscript

* xt_rem_clogit.do -- DRAFT, not yet run.
* Cross-route check: nwrem's ordinal partial likelihood is a conditional logit with one stratum per event and one
* alternative per ordered actor pair (j,k), j != k. This file computes all 14 statistics with its own Mata code
* (written from the help file's definitions, not from unw_rem.do), fits -clogit- on the long data and compares
* coefficients and log likelihood with nwrem. Also: tied times (nwrem reads them in the listed order), and a
* permutation of the actor labels with permuted covariates (estimates unchanged).
* Data: 5 actors, 150 events, generated below with rseed(20261112) (repetition and reciprocation tendencies).
* Expected runtime: about 60 seconds (Stata 17 BE).
* Run from the repository root; the test runner sets the adopath. No sysdir/adopath here.

capture program drop nwinstall
local nwcore : env NWCORE
if `"`nwcore'"' != "" quietly do `"`nwcore'/unw_core.do"'
quietly do unw_rem.do

capture mata: mata drop xt_rankrecip()
capture mata: mata drop xt_rem_long()
mata:
mata set matastrict off
// 1 / (rank of v[k] among the positive entries of v, largest = rank 1); 0 when v[k] is 0 (never contacted)
real scalar xt_rankrecip(real rowvector v, real scalar k)
{
	if (v[k] <= 0) return(0)
	return(1 / sum(v :>= v[k]))
}
// one row per event i and ordered pair (j,k), j != k; events are processed in the row order of E (N x 2).
// columns: 1 ev 2 j 3 k 4 chosen 5 nodsnd 6 nidrec 7 nidsnd 8 nodrec 9 ntdegsnd 10 ntdegrec 11 frpsndsnd 12 frrecsnd
//          13 rsndsnd 14 rrecsnd 15 covsnd 16 covrec 17 covint 18 covevent
// definitions (help file): degree shares = counts over the number of prior events (1/(n-1) for every actor at the
// first event); frpsndsnd = share of j's past sends that went to k, frrecsnd = share of j's past receipts that came
// from k (1/(n-1) while j has none); rsndsnd / rrecsnd = 1/recency rank of k among j's past receivers / senders.
real matrix xt_rem_long(real matrix E, real scalar n, real colvector xs, real colvector xr, real colvector xi, real matrix C)
{
	N = rows(E)
	f = 1 / (n - 1)
	L = J(N * n * (n - 1), 18, .)
	cnt = J(n, n, 0)
	last = J(n, n, 0)
	outd = J(1, n, 0)
	ind = J(1, n, 0)
	row = 0
	for (i=1; i<=N; i++) {
		s = E[i,1]
		r = E[i,2]
		for (j=1; j<=n; j++) {
			for (k=1; k<=n; k++) {
				if (j == k) continue
				row = row + 1
				L[row,1] = i
				L[row,2] = j
				L[row,3] = k
				L[row,4] = (j == s & k == r)
				if (i == 1) {
					L[|row,5 \ row,10|] = J(1, 6, f)
				}
				else {
					L[row,5] = outd[j] / (i - 1)
					L[row,6] = ind[k] / (i - 1)
					L[row,7] = ind[j] / (i - 1)
					L[row,8] = outd[k] / (i - 1)
					L[row,9] = (outd[j] + ind[j]) / (2 * (i - 1))
					L[row,10] = (outd[k] + ind[k]) / (2 * (i - 1))
				}
				L[row,11] = (outd[j] > 0 ? cnt[j,k] / outd[j] : f)
				L[row,12] = (ind[j] > 0 ? cnt[k,j] / ind[j] : f)
				L[row,13] = xt_rankrecip(last[j,.], k)
				L[row,14] = xt_rankrecip(last[.,j]', k)
				L[row,15] = xs[j]
				L[row,16] = xr[k]
				L[row,17] = xi[j] + xi[k]
				L[row,18] = C[j,k]
			}
		}
		cnt[s,r] = cnt[s,r] + 1
		outd[s] = outd[s] + 1
		ind[r] = ind[r] + 1
		last[s,r] = i
	}
	return(L)
}
end

* ---------------------------------------------------------------------------------------------------------------------
* data
mata:
rseed(20261112)
xn = 5
xN = 150
XE = J(xN, 2, 0)
lastr = J(1, xn, 0)
lasts = J(1, xn, 0)
for (i=1; i<=xN; i++) {
	s = runiformint(1, 1, 1, xn)
	u = runiform(1, 1)
	if (lastr[s] > 0 & u < 0.35) r = lastr[s]
	else if (lasts[s] > 0 & u < 0.55) r = lasts[s]
	else {
		r = runiformint(1, 1, 1, xn - 1)
		if (r >= s) r = r + 1
	}
	XE[i,.] = (s, r)
	lastr[s] = r
	lasts[r] = s
}
xs = (0.5 \ -1 \ 1.5 \ 0 \ 2)
xr = (1 \ 0 \ 0 \ 1 \ 1)
xi = (-0.3 \ 0.8 \ 0.1 \ -1.2 \ 0.6)
XC = round(runiform(xn, xn) :* 4, 1)
st_matrix("XCEM", XC)
end

capture program drop xt_events
program xt_events
	* the generated events in memory; `1' = time expression in i (default i)
	args texp
	if "`texp'" == "" local texp "_n"
	clear
	mata: st_local("nobs", strofreal(rows(XE)))
	quietly set obs `nobs'
	quietly gen long sender = .
	quietly gen long receiver = .
	mata: st_store(., ("sender", "receiver"), XE)
	quietly gen double t = `texp'
end

capture program drop xt_covs
program xt_covs
	* per-actor covariates cs, cr, ci (actor order 1..5) from the Mata vectors xs, xr, xi
	args net
	nwload `net', xvars
	assert _N == 5
	quietly gen double cs = .
	quietly gen double cr = .
	quietly gen double ci = .
	mata: st_store(., ("cs", "cr", "ci"), (xs, xr, xi))
end

capture program drop xt_cmp
program xt_cmp
	* xt_cmp B LL "nwrem names" "clogit variables": saved nwrem fit (matrix B, scalar LL) against the clogit in memory
	args bmat llsc nwn clv
	local k : word count `nwn'
	assert colsof(`bmat') == `k'
	forvalues q = 1/`k' {
		local a : word `q' of `nwn'
		local c : word `q' of `clv'
		local bn = el(`bmat', 1, colnumb(`bmat', "`a'"))
		assert abs(`bn' - _b[`c']) <= 1e-3 * (1 + abs(_b[`c']))
	}
	assert abs(scalar(`llsc') - e(ll)) < 1e-5
	di as text "  PASS: nwrem (`nwn') = clogit (`clv'), ll " %12.6f e(ll)
end

* ---------------------------------------------------------------------------------------------------------------------
di as text "{hline 60}"
di as text "Block A: nwrem fits on the generated events (distinct times)"
di as text "{hline 60}"
nwclear
xt_events
nwset sender receiver, eventtime(t) directed name(gen)
nwset, mat(XCEM) directed name(gce) nooutput
xt_covs gen
local m 0
foreach spec in "nodsnd nidrec" "nidsnd nodrec" "ntdegsnd ntdegrec" "frpsndsnd frrecsnd" "rsndsnd rrecsnd" "nodsnd frpsndsnd rsndsnd" "covsnd(cs) covrec(cr) covint(ci) covevent(gce)" {
	local ++m
	nwrem gen, `spec' seed(1)
	assert e(N) == 150 & e(nodes) == 5
	matrix XB`m' = e(b)
	scalar XLL`m' = e(ll)
	di as text "  fitted: `spec'"
}
* tied times: ceil(i/5) gives 30 time points; nwrem reads ties in the listed order = the same sequence
nwclear
xt_events "ceil(_n/5)"
nwset sender receiver, eventtime(t) directed name(gtie)
nwrem gtie, nodsnd nidrec seed(1)
assert mreldif(e(b), XB1) < 1e-12
nwrem gtie, frpsndsnd frrecsnd seed(1)
assert mreldif(e(b), XB4) < 1e-12
di as text "  PASS: tied times in listed order = distinct times"

* ---------------------------------------------------------------------------------------------------------------------
di as text "{hline 60}"
di as text "Block B: clogit on the long data built in this file"
di as text "{hline 60}"
clear
mata: XL = xt_rem_long(XE, xn, xs, xr, xi, XC)
mata: (void) st_addvar("double", ("ev", "j", "k", "chosen", "nodsnd", "nidrec", "nidsnd", "nodrec", "ntdegsnd", "ntdegrec", "frpsndsnd", "frrecsnd", "rsndsnd", "rrecsnd", "covsnd", "covrec", "covint", "covevent"))
mata: st_addobs(rows(XL))
mata: st_store(., ., XL)
assert _N == 150 * 20
quietly count if chosen == 1
assert r(N) == 150
quietly clogit chosen nodsnd nidrec, group(ev)
xt_cmp XB1 XLL1 "nodsnd nidrec" "nodsnd nidrec"
quietly clogit chosen nidsnd nodrec, group(ev)
xt_cmp XB2 XLL2 "nidsnd nodrec" "nidsnd nodrec"
quietly clogit chosen ntdegsnd ntdegrec, group(ev)
xt_cmp XB3 XLL3 "ntdegsnd ntdegrec" "ntdegsnd ntdegrec"
quietly clogit chosen frpsndsnd frrecsnd, group(ev)
xt_cmp XB4 XLL4 "frpsndsnd frrecsnd" "frpsndsnd frrecsnd"
quietly clogit chosen rsndsnd rrecsnd, group(ev)
xt_cmp XB5 XLL5 "rsndsnd rrecsnd" "rsndsnd rrecsnd"
quietly clogit chosen nodsnd frpsndsnd rsndsnd, group(ev)
xt_cmp XB6 XLL6 "nodsnd frpsndsnd rsndsnd" "nodsnd frpsndsnd rsndsnd"
quietly clogit chosen covsnd covrec covint covevent, group(ev)
xt_cmp XB7 XLL7 "covsnd_cs covrec_cr covint_ci covevent_gce" "covsnd covrec covint covevent"

* ---------------------------------------------------------------------------------------------------------------------
di as text "{hline 60}"
di as text "Block C: permuted actor labels (ids 1..5 -> 3,5,1,2,4) with permuted covariates"
di as text "{hline 60}"
mata:
xpi = (3 \ 5 \ 1 \ 2 \ 4)
xpinv = invorder(xpi)
XEp = (xpi[XE[.,1]], xpi[XE[.,2]])
st_matrix("XCEP", XC[xpinv, xpinv])
end
nwclear
clear
quietly set obs 150
gen long sender = .
gen long receiver = .
mata: st_store(., ("sender", "receiver"), XEp)
gen double t = _n
nwset sender receiver, eventtime(t) directed name(gperm)
nwset, mat(XCEP) directed name(gcep) nooutput
nwload gperm, xvars
assert _N == 5
gen double cs = .
gen double cr = .
gen double ci = .
mata: st_store(., ("cs", "cr", "ci"), (xs[xpinv], xr[xpinv], xi[xpinv]))
nwrem gperm, nodsnd nidrec seed(1)
assert mreldif(e(b), XB1) < 1e-5
assert reldif(e(ll), scalar(XLL1)) < 1e-9
nwrem gperm, frpsndsnd frrecsnd seed(1)
assert mreldif(e(b), XB4) < 1e-5
assert reldif(e(ll), scalar(XLL4)) < 1e-9
nwrem gperm, covsnd(cs) covrec(cr) covint(ci) covevent(gcep) seed(1)
matrix XB7p = e(b)
matrix colnames XB7p = covsnd_cs covrec_cr covint_ci covevent_gce
assert mreldif(XB7p, XB7) < 1e-5
assert reldif(e(ll), scalar(XLL7)) < 1e-9
di as text "  PASS: label permutation leaves estimates and ll unchanged"

di "ALL PASS"
