*! version 1.5.1  18nov2026 nwrem_estat
* Copyright (C) 2026 Thomas U. Grund
* This file is part of nwrem, a Stata package derived from the R package 'relevent' (Carter T. Butts; GPL (>= 2)).
* nwrem is free software: you can redistribute it and/or modify it under the terms of the GNU General
* Public License, version 3, as published by the Free Software Foundation. It is distributed in the hope
* that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
* or FITNESS FOR A PARTICULAR PURPOSE. See the file LICENSE for the full text.

* Postestimation diagnostics of nwrem: estat rank, estat actors, estat time. relevent has no such methods; these are
* extensions of nwrem. The linear predictor of every dyad of the risk set is evaluated at every event in the compiled plugin
* (rem_sim, code 40) at the stored coefficients; the model is set up again by re-running the data preparation of the fit
* (the command line stored in e(cmdline)), so the network and the covariate variables must be as they were at the fit.

capture program drop nwrem_estat
program nwrem_estat, rclass
	version 16
	if "`e(cmd)'" != "nwrem" error 301
	gettoken subcmd rest : 0, parse(" ,")
	local subcmd = lower(trim("`subcmd'"))
	local len = strlen("`subcmd'")
	if `len' >= 1 & "`subcmd'" == substr("rank", 1, `len') {
		_nwrem_estat_rank `rest'
	}
	else if `len' >= 1 & "`subcmd'" == substr("actors", 1, `len') {
		_nwrem_estat_actors `rest'
	}
	else if `len' >= 1 & "`subcmd'" == substr("time", 1, `len') {
		_nwrem_estat_time `rest'
	}
	else {
		exit 321
	}
	return add
end

* evaluates the diagnostics: frames __nwrem_dgev (one row per event in time order) and __nwrem_dgact (one row per actor)
capture program drop _nwrem_diagrun
program _nwrem_diagrun
	args topk
	if "`e(cmd)'" != "nwrem" error 301
	local cl `"`e(cmdline)'"'
	if `"`cl'"' == "" {
		di as error "{p 0 0 2}the estimation results do not carry the command line (they come from an older version of nwrem); fit the model again.{p_end}"
		exit 498
	}
	capture frame drop __nwrem_dgev
	capture frame drop __nwrem_dgact
	tempname bsave
	matrix `bsave' = e(b)
	matrix __nwrem_dgb = `bsave'
	if strpos(`"`cl'"', ",") == 0 local cl `"`cl' , nwxdiag(`topk')"'
	else local cl `"`cl' nwxdiag(`topk')"'
	capture noisily `cl'
	local rc = _rc
	capture matrix drop __nwrem_dgb
	if `rc' {
		capture frame drop __nwrem_dgev
		capture frame drop __nwrem_dgact
		if `rc' == 3499 | `rc' == 3498 exit `rc'
		exit `rc'
	}
end

capture program drop _nwrem_diagclean
program _nwrem_diagclean
	capture frame drop __nwrem_dgev
	capture frame drop __nwrem_dgact
	capture scalar drop __nwrem_dgfinal
	capture scalar drop __nwrem_dgncond
	capture scalar drop __nwrem_dgll
end

* the options that are checked and passed on
capture program drop _nwrem_diagtopk
program _nwrem_diagtopk
	args mac val
	capture confirm integer number `val'
	if _rc | real(`"`val'"') < 1 {
		di as error "topk() must be a positive integer"
		exit 198
	}
	c_local `mac' = real(`"`val'"')
end

* ---------------------------------------------------------------------------------------------------------------------
* estat rank: the rank of the observed dyad among all dyads of the risk set by the fitted linear predictor
capture program drop _nwrem_estat_rank
program _nwrem_estat_rank, rclass
	syntax [, TOPk(string) PLOT(string) BINs(integer 10) NOGraph *]
	local k = 10
	if `"`topk'"' != "" _nwrem_diagtopk k `"`topk'"'
	if `"`plot'"' == "" local plot "cdf"
	if !inlist(`"`plot'"', "cdf", "hist") {
		di as error "plot() must be cdf or hist"
		exit 198
	}
	if `bins' < 2 | `bins' > 1000 {
		di as error "bins() must be an integer between 2 and 1000"
		exit 198
	}
	_nwrem_diagrun `k'
	tempname N meanrank medrank meanpct hit hitm hitr mlp nlp meanR
	frame __nwrem_dgev {
		quietly {
			gen double __mid = ngreater + (ntied + 1) / 2 if !missing(logp)
			gen double __pct = __mid / rsize
			gen double __hit = max(0, min(1, (`k' - ngreater) / ntied)) if !missing(logp)
			gen double __hitr = min(`k', rsize) / rsize if !missing(logp)
			gen double __nlp = -ln(rsize) if !missing(logp)
			count if !missing(__mid)
			scalar `N' = r(N)
			summarize __mid, detail
			scalar `meanrank' = r(mean)
			scalar `medrank' = r(p50)
			summarize __pct
			scalar `meanpct' = r(mean)
			summarize rsize if !missing(__mid)
			scalar `meanR' = r(mean)
			summarize __hit
			scalar `hit' = r(mean)
			summarize topm
			scalar `hitm' = r(mean)
			summarize __hitr
			scalar `hitr' = r(mean)
			summarize logp
			scalar `mlp' = r(mean)
			summarize __nlp
			scalar `nlp' = r(mean)
		}
	}
	frame __nwrem_dgev {
		quietly gen double __er = (rsize + 1) / 2 if !missing(logp)
		quietly gen double __erp = (rsize + 1) / (2 * rsize) if !missing(logp)
		quietly summarize __er
		local exprank = r(mean)
		quietly summarize __erp
		local exppct = r(mean)
	}
	local kshow = `k'
	di
	di as text "{p 0 0 2}Rank diagnostic of the fitted model (an extension of nwrem; relevent has no such method).{p_end}"
	di as text "{p 0 0 2}Rank of the observed dyad among all dyads of the risk set at the time of the event, by the fitted linear predictor (1 = most likely; tied dyads share the mid-rank).{p_end}"
	di as text "{hline 70}"
	di as text "Events evaluated" _col(50) as result %12.0fc `N'
	di as text "Events left out (condition())" _col(50) as result %12.0fc e(N_cond)
	di as text "Mean size of the risk set" _col(50) as result %12.2f `meanR'
	di as text "{hline 70}"
	di as text _col(34) %12s "observed" _col(47) %12s "fitted model" _col(60) %10s "no effects"
	di as text "Mean rank" _col(34) as result %12.2f `meanrank' _col(60) %10.2f `exprank'
	di as text "Median rank" _col(34) as result %12.2f `medrank'
	di as text "Mean percentile rank" _col(34) as result %12.4f `meanpct' _col(60) %10.4f `exppct'
	di as text "Share of events in the top `kshow'" _col(34) as result %12.4f `hit' _col(47) %12.4f `hitm' _col(60) %10.4f `hitr'
	di as text "Mean log prob. of observed dyad" _col(34) as result %12.4f `mlp' _col(60) %10.4f `nlp'
	di as text "{hline 70}"
	di as text "{p 0 0 2}Percentile rank = rank / size of the risk set. Fitted model: top-`kshow' share expected under the model (the summed probability of the `kshow' most likely dyads). No effects: every dyad equally likely.{p_end}"
	return scalar N = `N'
	return scalar topk = `k'
	return scalar mean_rank = `meanrank'
	return scalar median_rank = `medrank'
	return scalar mean_pct_rank = `meanpct'
	return scalar hit = `hit'
	return scalar hit_model = `hitm'
	return scalar hit_null = `hitr'
	return scalar mean_logp = `mlp'
	return scalar mean_logp_null = `nlp'
	return scalar mean_risksize = `meanR'
	if "`nograph'" == "" {
		if "`plot'" == "cdf" {
			frame __nwrem_dgev {
				quietly {
					keep if !missing(__pct)
					sort __pct
					gen double __cum = _n / _N
					local obs0 = _N + 1
					set obs `obs0'
					replace __pct = 0 in `obs0'
					replace __cum = 0 in `obs0'
					sort __pct __cum
				}
				twoway (line __cum __pct, connect(J) lcolor(navy) lwidth(medthick)) ///
					(function y = x, range(0 1) lpattern(dash) lcolor(gs8)), ///
					xtitle("Percentile rank of the observed dyad (rank / risk set size)") ///
					ytitle("Share of events at or below") ///
					legend(order(1 "fitted model" 2 "no effects (uniform)") rows(1) position(6)) ///
					title("Rank diagnostic: cumulative distribution") ///
					note("Curve above the diagonal: the observed dyad ranks better than chance. Extension of nwrem.") ///
					xlabel(0(.2)1) ylabel(0(.2)1) aspectratio(1) `options'
			}
		}
		else {
			frame __nwrem_dgev {
				quietly keep if !missing(__pct)
				histogram __pct, bin(`bins') density start(0) lcolor(white) fcolor(navy%70) ///
					addplot(function y = 1, range(0 1) lpattern(dash) lcolor(gs6)) ///
					xtitle("Percentile rank of the observed dyad (rank / risk set size)") ytitle("Density") ///
					legend(order(1 "events" 2 "no effects (uniform)") rows(1) position(6)) ///
					title("Rank diagnostic: distribution of ranks") ///
					note("Mass near 0 = the observed dyad ranks high. Extension of nwrem.") `options'
			}
		}
	}
	else if `"`options'"' != "" {
		* graph options without a graph are still checked: none to check (they are passed to twoway only)
	}
	_nwrem_diagclean
end

* ---------------------------------------------------------------------------------------------------------------------
* estat actors: observed versus expected number of events as sender and as receiver, by actor
capture program drop _nwrem_estat_actors
program _nwrem_estat_actors, rclass
	syntax [, ROLE(string) LABels LISt NOGraph *]
	if `"`role'"' == "" local role "both"
	if !inlist(`"`role'"', "both", "sender", "receiver") {
		di as error "role() must be sender, receiver or both"
		exit 198
	}
	_nwrem_diagrun 1
	local netname "`e(depvar)'"
	_nwsyntax `netname', max(1)
	frame __nwrem_dgact {
		quietly {
			gen str40 actor = ""
			mata: st_sstore(., "actor", vec(`netobj'->get_nodenames()))
			gen double __rs = (obssnd - expsnd) / sqrt(expsnd) if expsnd > 0
			gen double __rr = (obsrec - exprec) / sqrt(exprec) if exprec > 0
			summarize obssnd
			local nsum = r(sum)
			gen double __sqs = __rs^2
			gen double __sqr = __rr^2
			summarize __sqs
			local x2s = r(sum)
			summarize __sqr
			local x2r = r(sum)
			correlate obssnd expsnd
			local cs = r(rho)
			correlate obsrec exprec
			local cr = r(rho)
			count
			local na = r(N)
		}
	}
	di
	di as text "{p 0 0 2}Observed and expected events by actor (an extension of nwrem; relevent has no such method).{p_end}"
	di as text "{p 0 0 2}Expected = sum over the events of the model probability that the actor is the sender (receiver); under the waiting-time likelihood, the summed rate integrals.{p_end}"
	di as text "{hline 66}"
	di as text "Actors" _col(40) as result %10.0fc `na' as text _col(52) "Events" _col(60) as result %10.0fc `nsum'
	di as text "{hline 66}"
	di as text _col(33) "Sender" _col(55) "Receiver"
	di as text "Correlation observed, expected" _col(30) as result %10.4f `cs' _col(52) %10.4f `cr'
	di as text "Sum of squared Pearson residuals" _col(30) as result %10.2f `x2s' _col(52) %10.2f `x2r'
	di as text "{hline 66}"
	di as text "{p 0 0 2}Pearson residual = (observed - expected) / sqrt(expected); the sums describe the fit, they are not a test (events are not independent draws given the effects).{p_end}"
	if "`list'" != "" {
		di
		frame __nwrem_dgact: list actor obssnd expsnd obsrec exprec, noobs sep(0) abbreviate(12)
	}
	return scalar n_actors = `na'
	return scalar corr_sender = `cs'
	return scalar corr_receiver = `cr'
	return scalar chi2_sender = `x2s'
	return scalar chi2_receiver = `x2r'
	tempname M
	frame __nwrem_dgact {
		mkmat obssnd expsnd obsrec exprec, matrix(`M')
	}
	matrix colnames `M' = obs_sender exp_sender obs_receiver exp_receiver
	return matrix actors = `M'
	if "`nograph'" == "" {
		local mlab ""
		if "`labels'" != "" local mlab "mlabel(actor) mlabsize(vsmall) mlabposition(1)"
		local ng = ("`role'" == "both") + 1
		tempname g1 g2
		frame __nwrem_dgact {
			if inlist("`role'", "both", "sender") {
				quietly summarize obssnd
				local mx1 = r(max)
				quietly summarize expsnd
				local mx1 = max(`mx1', r(max))
				twoway (scatter obssnd expsnd, msymbol(Oh) mcolor(navy) `mlab') ///
					(function y = x, range(0 `mx1') lpattern(dash) lcolor(gs8)), ///
					xtitle("Expected events as sender") ytitle("Observed events as sender") ///
					title("Sender activity") legend(off) aspectratio(1) ///
					nodraw name(`g1', replace)
			}
			if inlist("`role'", "both", "receiver") {
				quietly summarize obsrec
				local mx2 = r(max)
				quietly summarize exprec
				local mx2 = max(`mx2', r(max))
				twoway (scatter obsrec exprec, msymbol(Oh) mcolor(maroon) `mlab') ///
					(function y = x, range(0 `mx2') lpattern(dash) lcolor(gs8)), ///
					xtitle("Expected events as receiver") ytitle("Observed events as receiver") ///
					title("Receiver activity") legend(off) aspectratio(1) ///
					nodraw name(`g2', replace)
			}
		}
		if "`role'" == "both" {
			graph combine `g1' `g2', rows(1) title("Observed versus expected events by actor") ///
				note("Points on the dashed 45 degree line: the model reproduces the actor's activity. Extension of nwrem.") `options'
		}
		else if "`role'" == "sender" graph display `g1', `options'
		else graph display `g2', `options'
		capture graph drop `g1'
		capture graph drop `g2'
	}
	_nwrem_diagclean
end

* ---------------------------------------------------------------------------------------------------------------------
* estat time: observed versus expected over the time of the event sequence, in bins of equally many events
capture program drop _nwrem_estat_time
program _nwrem_estat_time, rclass
	syntax [, BINs(integer 10) TOPk(string) NOGraph *]
	local k = 10
	if `"`topk'"' != "" _nwrem_diagtopk k `"`topk'"'
	if `bins' < 2 | `bins' > 1000 {
		di as error "bins() must be an integer between 2 and 1000"
		exit 198
	}
	local interval = ("`e(lik)'" == "interval")
	_nwrem_diagrun `k'
	tempname fin
	scalar `fin' = __nwrem_dgfinal
	frame __nwrem_dgev {
		quietly {
			keep if !missing(logp)
			local ne = _N
			if `bins' > `ne' {
				noisily di as text "(bins(" `bins' ") reduced to the number of events, " `ne' ")"
				local bins = `ne'
			}
			gen long bin = ceil(_n * `bins' / _N)
			if `interval' {
				gen double __obs = 1
				gen double __exp = rate
				replace __exp = __exp + `fin' if _n == _N
			}
			else {
				gen double __obs = max(0, min(1, (`k' - ngreater) / ntied))
				gen double __exp = topm
			}
			collapse (count) nev = __obs (sum) obs = __obs expd = __exp (min) tmin = time (max) tmax = time (mean) tmean = time, by(bin)
		}
	}
	di
	di as text "{p 0 0 2}Observed versus expected over time (an extension of nwrem; relevent has no such method).{p_end}"
	if `interval' {
		di as text "{p 0 0 2}Waiting-time likelihood: observed = number of events in the bin of consecutive events; expected = sum of the integrated rates of the fitted model over the intervals that end with those events (the last bin also carries the final interval up to endtime()). The model has no baseline rate, so a level that is far off says the effects cannot reproduce the overall event rate.{p_end}"
	}
	else {
		di as text "{p 0 0 2}Ordinal likelihood (it has no time scale): observed = number of events whose observed dyad is among the `k' most likely dyads of the risk set (ties split); expected = sum of the probabilities of the `k' most likely dyads.{p_end}"
	}
	frame __nwrem_dgev {
		di as text "{hline 66}"
		di as text "   bin" _col(10) "events" _col(21) "time from" _col(34) "time to" _col(46) "observed" _col(58) "expected"
		forvalues b = 1/`=_N' {
			di as result %6.0f bin[`b'] _col(10) %7.0f nev[`b'] _col(20) %10.4g tmin[`b'] _col(32) %10.4g tmax[`b'] ///
				_col(44) %10.3f obs[`b'] _col(56) %10.3f expd[`b']
		}
		di as text "{hline 66}"
		quietly summarize obs
		local tobs = r(sum)
		quietly summarize expd
		local texp = r(sum)
		di as text "total" _col(44) as result %10.3f `tobs' _col(56) %10.3f `texp'
		local nb = _N
		tempname M
		mkmat nev tmin tmax obs expd, matrix(`M')
	}
	matrix colnames `M' = events time_from time_to observed expected
	return scalar n_bins = `nb'
	return scalar obs_total = `tobs'
	return scalar exp_total = `texp'
	return matrix bins = `M'
	return scalar topk = `k'
	if "`nograph'" == "" {
		frame __nwrem_dgev {
			if `interval' {
				local yt "Events per bin"
				local ttl "Observed versus expected events over time"
			}
			else {
				local yt "Top-`k' hits per bin"
				local ttl "Observed versus expected top-`k' hits over time"
			}
			twoway (connected obs tmean, lcolor(navy) mcolor(navy) msymbol(O)) ///
				(connected expd tmean, lcolor(maroon) mcolor(maroon) msymbol(T) lpattern(dash)), ///
				xtitle("Time (mean event time of the bin)") ytitle("`yt'") ///
				legend(order(1 "observed" 2 "expected under the model") rows(1) position(6)) ///
				title("`ttl'") note("Bins hold equally many consecutive events. Extension of nwrem.") `options'
		}
	}
	_nwrem_diagclean
end
