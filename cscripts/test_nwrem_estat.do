cscript

* nwrem estat rank / actors / time (extensions of nwrem; relevent has no plot or diagnostic methods): the numbers against an
* independent enumeration in Mata on a tiny example (every dyad of the risk set at every event, statistics recomputed from the
* history), both likelihoods, condition(), riskset(); the graphs exist; error paths; e() is left untouched.
capture program drop nwinstall
local nwcore : env NWCORE
if `"`nwcore'"' != "" quietly do `"`nwcore'/unw_core.do"'
quietly do unw_rem.do

* ---- the independent computation -----------------------------------------------------------------------------------
* Statistics (relevent): nodsnd = out-degree share of the sender, nidrec = in-degree share of the receiver (1/(n-1) before the first
* event), covsnd = the covariate of the sender. eta = b1 nodsnd + b2 nidrec + b3 covsnd. mask: n x n, 1 = dyad can occur.
mata:
real matrix REF_diag(real matrix ev, real scalar n, real rowvector b, real colvector x, real scalar ncond, real scalar interval,
		real scalar dt0, real scalar tend, real scalar k, real matrix mask, real matrix actout, real scalar finalrate)
{
	real scalar m, i, j, l, R, g, q, vo, Z, mx, rate, prior, dt
	real colvector od, id, w
	real matrix out, eta
	m = rows(ev)
	od = J(n, 1, 0)
	id = J(n, 1, 0)
	out = J(m, 9, .)
	actout = J(n, 4, 0)
	finalrate = 0
	for (i = 1; i <= m + (interval & tend > ev[m, 3]); i++) {
		prior = i - 1
		eta = J(n, n, .)
		for (j = 1; j <= n; j++) for (l = 1; l <= n; l++) {
			if (j == l) continue
			if (rows(mask) > 0) if (mask[j, l] == 0) continue
			eta[j, l] = b[1] * (prior == 0 ? 1 / (n - 1) : od[j] / prior) + b[2] * (prior == 0 ? 1 / (n - 1) : id[l] / prior) + b[3] * x[j]
		}
		w = select(vec(eta), vec(eta) :< .)
		R = rows(w)
		mx = max(w)
		Z = sum(exp(w :- mx))
		dt = (i <= m ? ev[i, 3] - (i == 1 ? dt0 : ev[i - 1, 3]) : tend - ev[m, 3])
		if (i > ncond) {
			if (i <= m) {
				vo = eta[ev[i, 1], ev[i, 2]]
				g = sum(w :> vo + 1e-10)
				q = sum(abs(w :- vo) :<= 1e-10)
				out[i, .] = (ev[i, 1], ev[i, 2], ev[i, 3], g, q, R, vo - mx - ln(Z), (interval ? dt * exp(mx) * Z : 0), sum(sort(exp(w :- mx), -1)[1..min((k, R))]) / Z)
			}
			else finalrate = dt * exp(mx) * Z
			for (j = 1; j <= n; j++) for (l = 1; l <= n; l++) {
				if (eta[j, l] >= .) continue
				rate = (interval ? dt * exp(eta[j, l]) : exp(eta[j, l] - mx) / Z)
				actout[j, 1] = actout[j, 1] + rate
				actout[l, 2] = actout[l, 2] + rate
			}
			if (i <= m) {
				actout[ev[i, 1], 3] = actout[ev[i, 1], 3] + 1
				actout[ev[i, 2], 4] = actout[ev[i, 2], 4] + 1
			}
		}
		if (i <= m) {
			od[ev[i, 1]] = od[ev[i, 1]] + 1
			id[ev[i, 2]] = id[ev[i, 2]] + 1
		}
	}
	return(out)
}
end

capture program drop chk
program chk
	* chk name value reference [tol]
	args nm v ref tol
	if "`tol'" == "" local tol 1e-9
	if reldif(`v', `ref') > `tol' {
		di as error "  FAIL: `nm': `v' vs reference `ref'"
		exit 9
	}
end

* ---- the example: 5 actors, 22 events, distinct times -----------------------------------------------------------------
mata: EV = (1,2 \ 2,3 \ 3,1 \ 1,3 \ 4,5 \ 5,1 \ 2,1 \ 3,4 \ 1,2 \ 2,5 \ 5,3 \ 4,1 \ 1,4 \ 3,2 \ 2,4 \ 5,2 \ 1,5 \ 4,3 \ 3,5 \ 2,1 \ 1,3 \ 5,4)
nwclear
clear
quietly set obs 22
gen long sender = .
gen long receiver = .
mata: st_store(., ("sender", "receiver"), EV)
gen double t = (_n)^1.2
nwset sender receiver, eventtime(t) directed name(tiny)
nwload tiny, xvars
capture confirm string variable _nwnode
if _rc local labs : di `=_N' // numeric labels
else {
	mata: st_local("labs", invtokens(st_sdata(., "_nwnode")'))
	di "LABS: `labs'"
}
assert _N == 5
gen double xc = (_n == 2) + 2 * (_n == 4) - (_n == 5)
* the risk set: all dyads but 4 -> 2, which is no event
matrix MK = (0,1,1,1,1 \ 1,0,1,1,1 \ 1,1,0,1,1 \ 1,0,1,0,1 \ 1,1,1,1,0)
nwset, mat(MK) directed name(rs) nooutput
mata: XC = st_data(., "xc")
mata: EVT = (EV, (1::22):^1.2)
mata: REFACT = .
mata: REFFIN = .

foreach lik in ordinal interval {
foreach cond in 0 3 {
foreach rsopt in "" "riskset(rs)" {
	local iopt = cond("`lik'" == "interval", "interval starttime(0) endtime(45)", "")
	if "`rsopt'" != "" mata: MKM = st_matrix("MK")
	else mata: MKM = J(0, 0, .)
	quietly nwrem tiny, nodsnd nidrec covsnd(xc) `iopt' condition(`cond') `rsopt'
	tempname B
	matrix `B' = e(b)
	mata: BB = st_matrix("`B'")
		mata: REFOUT = REF_diag(EVT, 5, BB, XC, `cond', ("`lik'" == "interval"), 0, 45, 5, MKM, REFACT, REFFIN)
	mata: st_local("nc", strofreal(sum(REFOUT[., 4] :< .)))
	* ---- estat rank
	estat rank, topk(5) noplot
	local kk = 5
	mata: _r = select(REFOUT, REFOUT[., 4] :< .)
	mata: _mid = _r[., 4] :+ (_r[., 5] :+ 1) :/ 2
	mata: st_numscalar("__ref", rows(_r))
	chk "N" r(N) scalar(__ref)
	mata: st_numscalar("__ref", mean(_mid))
	chk "mean rank" r(mean_rank) scalar(__ref)
	mata: st_numscalar("__ref", mean(_mid :/ _r[., 6]))
	chk "mean pct rank" r(mean_pct_rank) scalar(__ref)
	mata: st_numscalar("__ref", mean(_r[., 9]))
	chk "hit model" r(hit_model) scalar(__ref)
	mata: st_numscalar("__ref", mean(rowmax((J(rows(_r), 1, 0), rowmin((J(rows(_r), 1, 1), (5 :- _r[., 4]) :/ _r[., 5]))))))
	chk "hit" r(hit) scalar(__ref)
	mata: st_numscalar("__ref", mean(_r[., 7]))
	chk "mean logp" r(mean_logp) scalar(__ref)
	* ordinal likelihood without conditioning: the log probabilities of the observed dyads add up to the log likelihood of the fit
	* (which test_nwrem_relevent14 checks against R's relevent)
	if "`lik'" == "ordinal" & `cond' == 0 {
		scalar __llsum = r(mean_logp) * r(N)
		chk "sum logp = e(ll)" scalar(__llsum) e(ll) 1e-8
	}
	mata: st_numscalar("__ref", mean(-ln(_r[., 6])))
	chk "null logp" r(mean_logp_null) scalar(__ref)
	mata: st_numscalar("__ref", mean(rowmin((J(rows(_r), 1, 5), _r[., 6])) :/ _r[., 6]))
	chk "hit null" r(hit_null) scalar(__ref)
	mata: _s = sort(_mid, 1)
	mata: st_numscalar("__ref", rows(_s) / 2 == floor(rows(_s) / 2) ? (_s[rows(_s) / 2] + _s[rows(_s) / 2 + 1]) / 2 : _s[(rows(_s) + 1) / 2])
	chk "median" r(median_rank) scalar(__ref)
	* ---- estat actors
	estat actors, noplot
	matrix A = r(actors)
	mata: st_matrix("__refA", REFACT[., (3, 1, 4, 2)])
	* the matrix is ordered obs_sender exp_sender obs_receiver exp_receiver
	assert mreldif(A, __refA) < 1e-9
	* ---- estat time
	estat time, bins(4) topk(5) noplot
	matrix TB = r(bins)
	mata: _nn = rows(_r)
	mata: _bin = ceil((1::_nn) :* 4 :/ _nn)
	mata: _obs = ("`lik'" == "interval") ? J(_nn, 1, 1) : rowmax((J(_nn, 1, 0), rowmin((J(_nn, 1, 1), (5 :- _r[., 4]) :/ _r[., 5]))))
	mata: _exp = ("`lik'" == "interval") ? _r[., 8] : _r[., 9]
	mata: _exp[_nn] = _exp[_nn] + ("`lik'" == "interval") * REFFIN
	forvalues bb = 1/4 {
		mata: st_numscalar("__ro", sum(select(_obs, _bin :== `bb')))
		mata: st_numscalar("__re", sum(select(_exp, _bin :== `bb')))
		local vv = el(TB, `bb', 4)
		chk "time obs bin `bb'" `vv' scalar(__ro)
		local vv = el(TB, `bb', 5)
		chk "time exp bin `bb'" `vv' scalar(__re)
	}
	di as text "  PASS: `lik', condition(`cond') `rsopt': estat rank, actors, time agree with the enumeration (`nc' events)"
}
}
}

* ---- the fixed effect case (dense in the plugin) and a covariate network: only that the numbers are finite and consistent
quietly nwrem tiny, nodsnd nidrec fesnd
estat rank, noplot
assert r(N) == 22 & r(mean_rank) > 0
estat actors, noplot
* expected counts add up to the number of events (ordinal likelihood)
matrix A = r(actors)
mata: st_numscalar("__s", sum(st_matrix("A")[., 2]))
assert reldif(scalar(__s), 22) < 1e-9
mata: st_numscalar("__s", sum(st_matrix("A")[., 4]))
assert reldif(scalar(__s), 22) < 1e-9
di as text "  PASS: expected sender and receiver counts add up to the number of events (with fesnd)"

* ---- graphs exist
quietly nwrem tiny, nodsnd nidrec covsnd(xc)
tempfile gf
foreach cmd in "estat rank, plot(cdf)" "estat rank, plot(hist) bins(6)" "estat actors, labels" "estat actors, role(sender)" "estat actors, role(receiver)" "estat time, bins(5)" {
	graph drop _all
	`cmd' name(gtest, replace)
	graph describe gtest
	quietly graph export "`c(tmpdir)'/nwrem_estat_gtest.png", name(gtest) replace width(900)
	confirm file "`c(tmpdir)'/nwrem_estat_gtest.png"
	capture erase "`c(tmpdir)'/nwrem_estat_gtest.png"
	di as text "  PASS: graph of `cmd'"
}
quietly nwrem tiny, nodsnd nidrec interval starttime(0) endtime(45)
estat time
graph describe time
di as text "  PASS: graph of estat time after interval"

* ---- e() untouched, no leftovers
quietly nwrem tiny, nodsnd nidrec covsnd(xc)
tempname b0
matrix `b0' = e(b)
estat rank, noplot
assert "`e(cmd)'" == "nwrem"
assert mreldif(e(b), `b0') == 0

capture frame __nwrem_dgev: describe
assert _rc != 0
capture frame __nwrem_native: describe
assert _rc != 0
capture scalar list __nwrem_dgfinal
assert _rc != 0
di as text "  PASS: e() unchanged, frames and scalars cleaned up"

* ---- error paths
capture estat rank, topk(0)
assert _rc == 198
capture estat rank, topk(abc)
assert _rc == 198
capture estat rank, plot(pie)
assert _rc == 198
capture estat rank, bins(1)
assert _rc == 198
capture estat actors, role(both2)
assert _rc == 198
capture estat time, bins(0)
assert _rc == 198
capture estat time, topk(1.5)
assert _rc == 198
capture estat nonsense
assert _rc != 0
* the network is gone
nwclear
capture estat rank, noplot
assert _rc != 0
di as text "  PASS: error paths (198 for bad options, an error when the network is gone)"
ereturn clear
capture estat rank
assert _rc == 301
di as text "  PASS: r(301) without nwrem results"
di as text "ALL TESTS PASSED"
