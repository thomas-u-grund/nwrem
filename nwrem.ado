*! version 1.5.0  17nov2026 nwrem
* Copyright (C) 2026 Thomas U. Grund
* This file is part of nwrem, a Stata package derived from the R package 'relevent' (Carter T. Butts; GPL (>= 2)).
* nwrem is free software: you can redistribute it and/or modify it under the terms of the GNU General
* Public License, version 3, as published by the Free Software Foundation. It is distributed in the hope
* that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
* or FITNESS FOR A PARTICULAR PURPOSE. See the file LICENSE for the full text.

capture program drop nwrem
program nwrem, eclass
	version 14
	if word(`"`0'"', 1) == "version" {
		nwrem_version
		exit
	}
	// replay: nwrem with no arguments, or with display options only (ci, level(), noci, nopvalues, cformat() and the
	// other options of Stata's ereturn display), after an nwrem fit; also what estimates replay runs
	if replay() {
		capture _nwrem_tabopts __t check `0'
		if !_rc {
			if "`e(cmd)'" != "nwrem" error 301
			_nwrem_display `0'
			exit
		}
	}
	syntax [anything(name=netname)] [, NODSND NIDREC NIDSND NODREC NTDEGSND NTDEGREC FRPSNDSND FRRECSND COVSND(varlist numeric) COVREC(varlist numeric) COVINT(varlist numeric) COVEVENT(string) RSNDSND RRECSND ///
		OTPSND ITPSND OSPSND ISPSND FESND FEREC FEINT PSABBA PSABBY PSABXA PSABXB PSABXY PSABAY ///
		INTerval STARTtime(string) ENDtime(string) CONDition(string) RISKset(string) ENTRY(varname numeric) EXIT(varname numeric) ///
		POSTmode PRIORMean(string) PRIORScale(string) PRIORDf(string) SEED(string) *]
	// display options of the coefficient table (ci, level(), noci, nopvalues, cformat(), ...); any other option is
	// refused here with Stata's usual message
	local __tabopts `"`options'"'
	_nwrem_tabopts __chk check, `__tabopts'
	if `"`seed'"' != "" {
		capture confirm integer number `seed'
		if _rc | real(`"`seed'"') < 0 | real(`"`seed'"') > 2147483647 {
			di as error "seed() must be an integer between 0 and 2147483647"
			error 198
		}
	}
	// likelihood, conditioning, prior
	local __nwrem_interval = ("`interval'" != "")
	if !`__nwrem_interval' & (`"`starttime'"' != "" | `"`endtime'"' != "") {
		di as error "{p 0 0 2}starttime() and endtime() belong to the waiting-time likelihood: add the option {bf:interval}.{p_end}"
		error 198
	}
	local __nwrem_start = 0
	if `"`starttime'"' != "" {
		capture confirm number `starttime'
		if _rc {
			di as error "starttime() must be a number"
			error 198
		}
		local __nwrem_start = `starttime'
	}
	local __nwrem_end = .
	if `"`endtime'"' != "" {
		capture confirm number `endtime'
		if _rc {
			di as error "endtime() must be a number"
			error 198
		}
		local __nwrem_end = `endtime'
	}
	local __nwrem_cond = 0
	if `"`condition'"' != "" {
		capture confirm integer number `condition'
		if _rc | real(`"`condition'"') < 0 {
			di as error "condition() must be a non-negative integer (the number of leading events that only build the history)"
			error 198
		}
		local __nwrem_cond = `condition'
	}
	local __nwrem_prior = ("`postmode'" != "")
	if !`__nwrem_prior' & (`"`priormean'"' != "" | `"`priorscale'"' != "" | `"`priordf'"' != "") {
		di as error "{p 0 0 2}priormean(), priorscale() and priordf() belong to posterior-mode estimation: add the option {bf:postmode}.{p_end}"
		error 198
	}
	local __nwrem_pmean = 0
	local __nwrem_pscale = 100
	local __nwrem_pdf = 4
	if `"`priormean'"' != "" {
		capture confirm number `priormean'
		if _rc {
			di as error "priormean() must be a number"
			error 198
		}
		local __nwrem_pmean = `priormean'
	}
	if `"`priorscale'"' != "" {
		capture confirm number `priorscale'
		if _rc | real(`"`priorscale'"') <= 0 {
			di as error "priorscale() must be a positive number"
			error 198
		}
		local __nwrem_pscale = `priorscale'
	}
	if `"`priordf'"' != "" {
		if `"`priordf'"' == "." local __nwrem_pdf = .
		else {
			capture confirm number `priordf'
			if _rc | real(`"`priordf'"') <= 0 {
				di as error "priordf() must be a positive number, or . for a normal prior"
				error 198
			}
			local __nwrem_pdf = `priordf'
		}
	}
	set more off
	_nwrem_libcheck

	_nwsyntax `netname', max(1)

	if "`istemporal'" != "true" | "`temporaltype'" != "event" {
		di as error "{p 0 0 2}nwrem requires a network declared via nwset's eventtime() option (an event-type temporal network) - see {help nwset##temporal:nwset}.{p_end}"
		error 198
	}
	// nwset accepts eventtime() together with twomode; nwrem's effects are defined on one-mode data only
	if "`is2mode'" == "true" {
		di as error "nwrem does not support two-mode (bipartite) networks; {bf:`netname'} is two-mode."
		error 198
	}

	// Fixed effect order of RemFitX() (unw_rem.do); the covariate effects stand for one parameter per variable (network), the
	// fixed effects for one parameter per actor from the second on. At least one effect must be selected; no default is
	// silently assumed.
	local __nwrem_effnames "nodsnd nidrec nidsnd nodrec ntdegsnd ntdegrec frpsndsnd frrecsnd covsnd covrec covint covevent rsndsnd rrecsnd otpsnd itpsnd ospsnd ispsnd fesnd ferec feint psabba psabby psabxa psabxb psabxy psabay"
	local __nwrem_active ""
	local __nwrem_sep ""
	local __nwrem_collabs ""
	local __nwrem_nactive = 0
	local __nwrem_nfe = 0
	foreach __nwrem_e of local __nwrem_effnames {
		if "``__nwrem_e''" != "" {
			local __nwrem_active "`__nwrem_active'`__nwrem_sep'1"
			local __nwrem_nactive = `__nwrem_nactive' + 1
			if inlist("`__nwrem_e'", "fesnd", "ferec", "feint") local __nwrem_nfe = `__nwrem_nfe' + 1
		}
		else {
			local __nwrem_active "`__nwrem_active'`__nwrem_sep'0"
		}
		local __nwrem_sep ","
	}
	if `__nwrem_nactive' == 0 {
		di as error "{p 0 0 2}nwrem requires at least one effect: {bf:nodsnd} {bf:nidrec} {bf:nidsnd} {bf:nodrec} {bf:ntdegsnd} {bf:ntdegrec} {bf:frpsndsnd} {bf:frrecsnd} {bf:covsnd()} {bf:covrec()} {bf:covint()} {bf:covevent()} {bf:rsndsnd} {bf:rrecsnd} {bf:otpsnd} {bf:itpsnd} {bf:ospsnd} {bf:ispsnd} {bf:fesnd} {bf:ferec} {bf:feint} {bf:psabba} {bf:psabby} {bf:psabxa} {bf:psabxb} {bf:psabxy} {bf:psabay} (see {help nwrem} for what each computes).{p_end}"
		error 198
	}
	if `__nwrem_nfe' > 0 & `nodes' * `__nwrem_nfe' > 600 {
		di as error "{p 0 0 2}the fixed effects add `=`nodes'-1' parameters per effect; with `nodes' actors that is too many (at most about 600 parameters in all).{p_end}"
		error 198
	}
	if `__nwrem_cond' >= . | `__nwrem_cond' < 0 {
		error 198
	}

	// Per-actor variables (covariates, entry and exit times) are read from the current dataset. When it carries the node
	// labels (variable _nwnode, as after nwload, xvars), every actor of the network is matched to its row by label, whatever the
	// sort order; otherwise the data must have one row per actor, in actor order.
	tempname __nwrem_rows __nwrem_CS __nwrem_CR __nwrem_CI __nwrem_entry __nwrem_exit
	if "`covsnd'`covrec'`covint'`entry'`exit'" != "" {
		unw_defs
		capture confirm string variable `nw_nodename'
		if !_rc {
			mata: `__nwrem_rows' = rem_node_rows(`netobj'->get_nodenames(), st_sdata(., "`nw_nodename'"))
			mata: st_local("__nwrem_nf", strofreal(sum(`__nwrem_rows' :== 0)))
			mata: st_local("__nwrem_nd", strofreal(sum(`__nwrem_rows' :< 0)))
			if `__nwrem_nf' > 0 {
				mata: st_local("__nwrem_lab", select(`netobj'->get_nodenames(), (`__nwrem_rows' :== 0)')[1])
				capture mata: mata drop `__nwrem_rows'
				di as error "{p 0 0 2}`__nwrem_nf' actor(s) of `netname' (first: {bf:`__nwrem_lab'}) have no row in the current dataset (variable `nw_nodename'); covariates need one row per actor (see {help nwload}'s {bf:xvars} option).{p_end}"
				error 198
			}
			if `__nwrem_nd' > 0 {
				mata: st_local("__nwrem_lab", select(`netobj'->get_nodenames(), (`__nwrem_rows' :< 0)')[1])
				capture mata: mata drop `__nwrem_rows'
				di as error "{p 0 0 2}`__nwrem_nd' actor(s) of `netname' (first: {bf:`__nwrem_lab'}) have more than one row in the current dataset (variable `nw_nodename'); covariates need exactly one row per actor.{p_end}"
				error 198
			}
		}
		else {
			if _N != `nodes' {
				di as error "{p 0 0 2}the current dataset has `=_N' observations but `netname' has `nodes' actors and no node labels (variable `nw_nodename'); covariates need one row per actor, in actor order (see {help nwload}'s {bf:xvars} option).{p_end}"
				error 198
			}
			mata: `__nwrem_rows' = (1::`nodes')
		}
	}
	else {
		mata: `__nwrem_rows' = (1::`nodes')
	}
	mata: `__nwrem_CS' = J(0, `nodes', .)
	mata: `__nwrem_CR' = J(0, `nodes', .)
	mata: `__nwrem_CI' = J(0, `nodes', .)
	foreach __nwrem_cvset in "covsnd:CS" "covrec:CR" "covint:CI" {
		gettoken __nwrem_cv __nwrem_cvm : __nwrem_cvset, parse(":")
		local __nwrem_cvm = substr("`__nwrem_cvm'", 2, .)
		foreach __nwrem_var of local `__nwrem_cv' {
			mata: `__nwrem_`__nwrem_cvm'' = (`__nwrem_`__nwrem_cvm'' \ st_data(`__nwrem_rows', "`__nwrem_var'")')
			mata: st_local("__nwrem_nmiss", strofreal(missing(st_data(`__nwrem_rows', "`__nwrem_var'"))))
			if `__nwrem_nmiss' > 0 {
				capture mata: mata drop `__nwrem_rows' `__nwrem_CS' `__nwrem_CR' `__nwrem_CI'
				di as error "{p 0 0 2}`__nwrem_cv'(`__nwrem_var'): `__nwrem_nmiss' actor(s) of `netname' have a missing value; the covariate must be defined for every actor.{p_end}"
				error 416
			}
			local __nwrem_collabs "`__nwrem_collabs' `=substr("`__nwrem_cv'_`__nwrem_var'", 1, 32)'"
		}
	}
	mata: `__nwrem_entry' = J(0, 1, .)
	mata: `__nwrem_exit' = J(0, 1, .)
	if "`entry'`exit'" != "" {
		if "`entry'" != "" mata: `__nwrem_entry' = st_data(`__nwrem_rows', "`entry'")
		else mata: `__nwrem_entry' = J(`nodes', 1, .)
		if "`exit'" != "" mata: `__nwrem_exit' = st_data(`__nwrem_rows', "`exit'")
		else mata: `__nwrem_exit' = J(`nodes', 1, .)
	}
	capture mata: mata drop `__nwrem_rows'

	// covevent() and riskset() reference ANOTHER already-loaded network (a pairwise, not per-actor, covariate) - resolved via
	// _nwsyntax exactly as nwergm's own edgecov()/hamming() do (nwergm.ado's dyadic-covariate block), using other() so its
	// locals (covevnetobj/covevnodes) don't clobber `netobj'/`nodes' from the primary network above.
	tempname __nwrem_covevmat __nwrem_mask
	mata: `__nwrem_covevmat' = J(`nodes', 0, .)
	mata: `__nwrem_mask' = J(0, 0, .)
	foreach __nwrem_cvn of local covevent {
		_nwsyntax `__nwrem_cvn', max(1) other(covev)
		// a two-mode covariate network has missing cells between nodes of the same mode (core >= 3.6.0 rule: refused with error 6088)
		_nw2guard `__nwrem_cvn', cmd(nwrem covevent())
		if `covevnodes' != `nodes' {
			di as error "{p 0 0 2}covevent() network `__nwrem_cvn' has `covevnodes' actors but `netname' has `nodes' - covevent() requires the same actors as `netname'.{p_end}"
			error 198
		}
		mata: `__nwrem_covevmat' = (`__nwrem_covevmat', *(`covevnetobj'->get_matrix_mod(1,1)))
		mata: st_local("__nwrem_covmiss", strofreal(missing(`__nwrem_covevmat'[., (cols(`__nwrem_covevmat') - `nodes' + 1)..cols(`__nwrem_covevmat')]) - missing(diagonal(`__nwrem_covevmat'[., (cols(`__nwrem_covevmat') - `nodes' + 1)..cols(`__nwrem_covevmat')]))))
		if `__nwrem_covmiss' > 0 {
			di as error "{p 0 0 2}covevent() network `__nwrem_cvn' has `__nwrem_covmiss' missing tie values; the covariate must be defined for every ordered pair of actors.{p_end}"
			error 416
		}
		local __nwrem_collabs "`__nwrem_collabs' `=substr("covevent_`__nwrem_cvn'", 1, 32)'"
	}
	if `"`riskset'"' != "" {
		_nwsyntax `riskset', max(1) other(covev)
		_nw2guard `riskset', cmd(nwrem riskset())
		if `covevnodes' != `nodes' {
			di as error "{p 0 0 2}riskset() network `riskset' has `covevnodes' actors but `netname' has `nodes' - riskset() requires the same actors as `netname'.{p_end}"
			error 198
		}
		mata: `__nwrem_mask' = *(`covevnetobj'->get_matrix_mod(1,1))
		mata: st_local("__nwrem_covmiss", strofreal(missing(`__nwrem_mask') - missing(diagonal(`__nwrem_mask'))))
		if `__nwrem_covmiss' > 0 {
			di as error "{p 0 0 2}riskset() network `riskset' has `__nwrem_covmiss' missing tie values; every ordered pair of actors must be 0 (cannot occur) or non-zero (can occur).{p_end}"
			error 416
		}
		mata: `__nwrem_mask' = (`__nwrem_mask' :!= 0)
	}

	// the coefficient labels, in the order of the parameters
	local __nwrem_labs ""
	foreach __nwrem_e of local __nwrem_effnames {
		if "``__nwrem_e''" == "" continue
		if inlist("`__nwrem_e'", "covsnd", "covrec", "covint") {
			foreach __nwrem_var of local `__nwrem_e' {
				local __nwrem_labs "`__nwrem_labs' `=substr("`__nwrem_e'_`__nwrem_var'", 1, 32)'"
			}
		}
		else if "`__nwrem_e'" == "covevent" {
			foreach __nwrem_cvn of local covevent {
				local __nwrem_labs "`__nwrem_labs' `=substr("covevent_`__nwrem_cvn'", 1, 32)'"
			}
		}
		else if inlist("`__nwrem_e'", "fesnd", "ferec", "feint") {
			forvalues __nwrem_a = 2/`nodes' {
				local __nwrem_labs "`__nwrem_labs' `__nwrem_e'_`__nwrem_a'"
			}
		}
		else local __nwrem_labs "`__nwrem_labs' `__nwrem_e'"
	}
	local __nwrem_collabs "`__nwrem_labs'"

	if `"`seed'"' != "" {
		set seed `seed'
	}

	tempname __nwrem_events
	mata: `__nwrem_events' = *(`netobj'->get_eventlist())
	mata: st_numscalar("__nwrem_nevents", rows(`__nwrem_events'))
	local nevents = __nwrem_nevents
	scalar drop __nwrem_nevents

	// events whose sender or receiver is not an actor of the network (a missing or unmatched id; actor index 0) or
	// that have no time cannot be placed in the event sequence: refuse them
	mata: st_local("__nwrem_bad0", strofreal(sum((`__nwrem_events'[., 1] :< 1) :| (`__nwrem_events'[., 2] :< 1) :| missing(`__nwrem_events'[., 1]) :| missing(`__nwrem_events'[., 2]))))
	mata: st_local("__nwrem_badt", strofreal(missing(`__nwrem_events'[., 3])))
	if `__nwrem_bad0' > 0 | `__nwrem_badt' > 0 {
		capture mata: mata drop `__nwrem_events' `__nwrem_CS' `__nwrem_CR' `__nwrem_CI' `__nwrem_covevmat' `__nwrem_mask' `__nwrem_entry' `__nwrem_exit'
		if `__nwrem_bad0' > 0 {
			di as error "{p 0 0 2}`__nwrem_bad0' event(s) of `netname' have a sender or receiver that is not an actor of the network (a missing actor id, or an id that does not match a node label); drop these events before {cmd:nwset}.{p_end}"
		}
		if `__nwrem_badt' > 0 {
			di as error "{p 0 0 2}`__nwrem_badt' event(s) of `netname' have a missing event time; drop these events before {cmd:nwset}.{p_end}"
		}
		error 416
	}

	if `nevents' < 2 {
		capture mata: mata drop `__nwrem_events' `__nwrem_CS' `__nwrem_CR' `__nwrem_CI' `__nwrem_covevmat' `__nwrem_mask' `__nwrem_entry' `__nwrem_exit'
		di as error "nwrem needs at least 2 events to fit a model; `netname' has `nevents'."
		error 2001
	}
	if `__nwrem_cond' >= `nevents' {
		capture mata: mata drop `__nwrem_events' `__nwrem_CS' `__nwrem_CR' `__nwrem_CI' `__nwrem_covevmat' `__nwrem_mask' `__nwrem_entry' `__nwrem_exit'
		di as error "condition() must be smaller than the number of events (`nevents')."
		error 198
	}

	// the fit runs in the compiled plugin (it writes the model into the frame __nwrem_native and leaves the current frame
	// as it was); an error inside the fit must not leave that frame behind
	local __nwrem_frame = c(frame)
	capture noisily mata: RemFitX(`__nwrem_events', `nodes', (`__nwrem_active'), `__nwrem_CS', `__nwrem_CR', `__nwrem_CI', `__nwrem_covevmat', `__nwrem_mask', `__nwrem_entry', `__nwrem_exit', (`__nwrem_interval', `__nwrem_cond', `__nwrem_start', `__nwrem_end', `__nwrem_prior', `__nwrem_pmean', `__nwrem_pscale', `__nwrem_pdf'), "__nwrem_")
	local __nwrem_rc = _rc
	if "`c(frame)'" != "`__nwrem_frame'" quietly frame change `__nwrem_frame'
	capture frame drop __nwrem_native
	capture mata: mata drop `__nwrem_events' `__nwrem_CS' `__nwrem_CR' `__nwrem_CI' `__nwrem_covevmat' `__nwrem_mask' `__nwrem_entry' `__nwrem_exit'
	if `__nwrem_rc' {
		capture matrix drop __nwrem_b
		capture matrix drop __nwrem_V
		capture scalar drop __nwrem_ll
		capture scalar drop __nwrem_ll0
		capture scalar drop __nwrem_df
		exit `__nwrem_rc'
	}

	tempname b V
	matrix `b' = __nwrem_b
	matrix `V' = __nwrem_V
	matrix colnames `b' = `__nwrem_collabs'
	matrix colnames `V' = `__nwrem_collabs'
	matrix rownames `V' = `__nwrem_collabs'
	local __nwrem_ll = __nwrem_ll
	local __nwrem_ll0 = __nwrem_ll0
	local __nwrem_df = __nwrem_df
	matrix drop __nwrem_b __nwrem_V
	scalar drop __nwrem_ll __nwrem_ll0 __nwrem_df

	// the number of events that enter the likelihood (conditioned events only build the history)
	local __nwrem_meff = `nevents' - `__nwrem_cond'
	local __nwrem_kpar = colsof(`b')
	local __nwrem_dev = -2 * `__nwrem_ll'

	ereturn post `b' `V', obs(`nevents')
	ereturn local cmd "nwrem"
	ereturn local version "1.5.0"
	if `__nwrem_interval' local __nwrem_lik "waiting-time likelihood"
	else local __nwrem_lik "ordinal partial likelihood"
	if `__nwrem_prior' local __nwrem_meth "posterior mode"
	else local __nwrem_meth "MLE"
	ereturn local title "Relational event model (`__nwrem_lik', `__nwrem_meth')"
	ereturn local lik = cond(`__nwrem_interval', "interval", "ordinal")
	ereturn local depvar "`netname'"
	ereturn scalar N = `nevents'
	ereturn scalar nodes = `nodes'
	ereturn scalar ll = `__nwrem_ll'
	ereturn scalar deviance = `__nwrem_dev'
	if !missing(`__nwrem_ll0') {
		ereturn scalar ll_0 = `__nwrem_ll0'
	}
	ereturn scalar df_m = `__nwrem_df'
	ereturn scalar N_cond = `__nwrem_cond'
	ereturn scalar aic = `__nwrem_dev' + 2 * `__nwrem_df'
	local __nwrem_meff2 = `__nwrem_meff' - `__nwrem_interval'
	if `__nwrem_meff2' - `__nwrem_df' - 1 > 0 {
		ereturn scalar aicc = e(aic) + 2 * `__nwrem_df' * (`__nwrem_df' + 1) / (`__nwrem_meff2' - `__nwrem_df' - 1)
	}
	if `__nwrem_meff2' > 0 {
		ereturn scalar bic = `__nwrem_dev' + `__nwrem_df' * ln(`__nwrem_meff2')
	}
	if `__nwrem_interval' {
		ereturn scalar starttime = `__nwrem_start'
		if !missing(`__nwrem_end') ereturn scalar endtime = `__nwrem_end'
	}
	if `__nwrem_prior' {
		ereturn scalar priormean = `__nwrem_pmean'
		ereturn scalar priorscale = `__nwrem_pscale'
		ereturn scalar priordf = `__nwrem_pdf'
	}

	// effects without a usable standard error: exactly collinear with other effects in the model (for example the
	// total-degree share ntdegsnd = (nodsnd + nidsnd)/2), or not identified by the data
	local __nwrem_bad ""
	local __nwrem_k = colsof(e(b))
	forvalues __nwrem_j = 1/`__nwrem_k' {
		local __nwrem_v = el(e(V), `__nwrem_j', `__nwrem_j')
		if missing(`__nwrem_v') | `__nwrem_v' <= 0 {
			local __nwrem_bad "`__nwrem_bad' `: word `__nwrem_j' of `__nwrem_collabs''"
		}
		else if sqrt(`__nwrem_v') > 100 {
			local __nwrem_bad "`__nwrem_bad' `: word `__nwrem_j' of `__nwrem_collabs''"
		}
	}
	ereturn local unidentified "`=trim("`__nwrem_bad'")'"
	_nwrem_display, `__tabopts'
end

capture program drop _nwrem_display
program _nwrem_display
	syntax [, *]
	di as text "{hline 60}"
	di as text "`e(title)'"
	di as text "Network: " as result "`e(depvar)'" _col(40) as text "Actors: " as result e(nodes)
	di as text "Events: " as result e(N) _col(40) as text "Log likelihood: " as result %9.4f e(ll)
	di as text "{hline 60}"
	_nwrem_tabopts __t, `options'
	ereturn display, `__t'
	if "`e(unidentified)'" != "" {
		di as text "{p 0 6 2}Note: no usable standard error for " as result "`e(unidentified)'" as text ".{p_end}"
		di as text "{p 6 6 2}These effects are not identified: typically an effect is an exact function of others in the model"   ///
			" (the total-degree share ntdegsnd is half the sum of nodsnd and nidsnd). Its estimate is arbitrary;"   ///
			" drop one of the effects.{p_end}"
	}
end

// the options of ereturn display for the coefficient table. The coefficient names are shown in full: the
// confidence intervals are left out (noci) at a linesize below 100, where names of up to 32 characters do not fit next
// to them. ci, or level(#) given explicitly, shows the intervals (long names are then cut, e.g. nodematch_o~e); noci,
// nopvalues, cformat() and the other display options of Stata's estimation commands are passed on. With check, only
// the options are checked (before a fit).
// Use: _nwrem_tabopts <local> [check] [, options]; the options for ereturn display are returned in <local>.
capture program drop _nwrem_tabopts
program _nwrem_tabopts
	version 14
	gettoken __mac 0 : 0, parse(" ,")
	gettoken __chk : 0, parse(" ,")
	if `"`__chk'"' == "check" gettoken __chk 0 : 0, parse(" ,")
	else local __chk
	syntax [, Level(string) *]
	local __lev `"`level'"'
	// ci is picked out by hand: declared to syntax, ci would also take noci (as its negation)
	local ci
	local __rest
	while `"`options'"' != "" {
		gettoken __o options : options, bind
		if strlower(`"`__o'"') == "ci" local ci ci
		else local __rest `"`__rest' `__o'"'
	}
	_get_diopts __di, `__rest'
	local __noci : list posof "noci" in __di
	local __nopv : list posof "nopvalues" in __di
	if "`ci'" != "" & `__noci' {
		di as err "only one of options ci or noci is allowed"
		exit 198
	}
	local __show = ("`ci'" != "" | `"`__lev'"' != "")
	if `"`__lev'"' != "" {
		local 0 , level(`__lev')
		syntax [, Level(cilevel)]
		local __lev `level'
	}
	else local __lev = c(level)
	if "`__chk'" != "" exit
	local __add
	if !`__show' & !`__noci' & !`__nopv' {
		// full names: at a linesize below 100 (or with lstretch off) the names of up to 32 characters do not fit next
		// to the intervals; from 100 on both fit
		if c(linesize) < 100 | c(lstretch) == "off" | `: list posof "nolstretch" in __di' local __add noci
	}
	c_local `__mac' `"level(`__lev') `__di' `__add'"'
end
