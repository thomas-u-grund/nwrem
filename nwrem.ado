*! version 1.1.1  13nov2026 nwrem
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
	// replay: nwrem with no arguments, or with display options only (level()), after an nwrem fit; also what
	// estimates replay runs
	if replay() {
		capture syntax [, Level(cilevel)]
		if !_rc {
			if "`e(cmd)'" != "nwrem" error 301
			_nwrem_display, level(`level')
			exit
		}
	}
	syntax [anything(name=netname)] [, NODSND NIDREC NIDSND NODREC NTDEGSND NTDEGREC FRPSNDSND FRRECSND COVSND(varname numeric) COVREC(varname numeric) COVINT(varname numeric) COVEVENT(string) RSNDSND RRECSND SEED(string) Level(cilevel)]
	if `"`seed'"' != "" {
		capture confirm integer number `seed'
		if _rc | real(`"`seed'"') < 0 | real(`"`seed'"') > 2147483647 {
			di as error "seed() must be an integer between 0 and 2147483647"
			error 198
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

	// Fixed effect order matching unw_rem.do's own rem_loglik_grad_multi()
	// exactly - see that function's own header comment. At least one
	// effect must be selected; no default is silently assumed.
	local __nwrem_effnames "nodsnd nidrec nidsnd nodrec ntdegsnd ntdegrec frpsndsnd frrecsnd covsnd covrec covint covevent rsndsnd rrecsnd"
	local __nwrem_active ""
	local __nwrem_sep ""
	local __nwrem_collabs ""
	local __nwrem_nactive = 0
	foreach __nwrem_e of local __nwrem_effnames {
		if "``__nwrem_e''" != "" {
			local __nwrem_active "`__nwrem_active'`__nwrem_sep'1"
			// covsnd()/covrec()/covint() are valued options (a variable
			// name), the other 8 are booleans - label with the variable
			// for the covariate trio (matching nwsaom's own
			// nodecov_`varname' convention) so e(b) shows which
			// variable was used, not just the generic effect name.
			if inlist("`__nwrem_e'", "covsnd", "covrec", "covint", "covevent") {
				// matrix column names have at most 32 characters: longer names are cut
				local __nwrem_collabs "`__nwrem_collabs' `=substr("`__nwrem_e'_``__nwrem_e''", 1, 32)'"
			}
			else {
				local __nwrem_collabs "`__nwrem_collabs' `__nwrem_e'"
			}
			local __nwrem_nactive = `__nwrem_nactive' + 1
		}
		else {
			local __nwrem_active "`__nwrem_active'`__nwrem_sep'0"
		}
		local __nwrem_sep ","
	}
	if `__nwrem_nactive' == 0 {
		di as error "{p 0 0 2}nwrem requires at least one effect: {bf:nodsnd} {bf:nidrec} {bf:nidsnd} {bf:nodrec} {bf:ntdegsnd} {bf:ntdegrec} {bf:frpsndsnd} {bf:frrecsnd} {bf:covsnd()} {bf:covrec()} {bf:covint()} {bf:covevent()} {bf:rsndsnd} {bf:rrecsnd} (see {help nwrem} for what each computes).{p_end}"
		error 198
	}

	// Per-actor covariates are read from the current dataset. When it carries the node labels (variable _nwnode, as after
	// nwload, xvars), every actor of the network is matched to its row by label, whatever the sort order; otherwise
	// the data must have one row per actor, in actor order.
	tempname __nwrem_covsnd __nwrem_covrec __nwrem_covint __nwrem_rows
	if "`covsnd'`covrec'`covint'" != "" {
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
	foreach __nwrem_cv in covsnd covrec covint {
		if "``__nwrem_cv''" != "" {
			mata: `__nwrem_`__nwrem_cv'' = st_data(`__nwrem_rows', "``__nwrem_cv''")'
			mata: st_local("__nwrem_nmiss", strofreal(missing(`__nwrem_`__nwrem_cv'')))
			if `__nwrem_nmiss' > 0 {
				capture mata: mata drop `__nwrem_rows' `__nwrem_covsnd' `__nwrem_covrec' `__nwrem_covint'
				di as error "{p 0 0 2}`__nwrem_cv'(``__nwrem_cv''): `__nwrem_nmiss' actor(s) of `netname' have a missing value; the covariate must be defined for every actor.{p_end}"
				error 416
			}
		}
		else {
			mata: `__nwrem_`__nwrem_cv'' = J(1, `nodes', 0)
		}
	}
	capture mata: mata drop `__nwrem_rows'

	// covevent() references ANOTHER already-loaded network (a pairwise,
	// not per-actor, covariate) - resolved via _nwsyntax exactly as
	// nwergm's own edgecov()/hamming() do (nwergm.ado's dyadic-covariate
	// block), using other() so its locals (covevnetobj/covevnodes) don't
	// clobber `netobj'/`nodes' from the primary network above.
	tempname __nwrem_covevmat
	if "`covevent'" != "" {
		_nwsyntax `covevent', max(1) other(covev)
		// a two-mode covariate network has missing cells between nodes of the same mode (core >= 3.6.0 rule: refused with error 6088)
		_nw2guard `covevent', cmd(nwrem covevent())
		if `covevnodes' != `nodes' {
			di as error "{p 0 0 2}covevent() network `covevent' has `covevnodes' actors but `netname' has `nodes' - covevent() requires the same actors as `netname'.{p_end}"
			error 198
		}
		mata: `__nwrem_covevmat' = *(`covevnetobj'->get_matrix_mod(1,1))
		mata: st_local("__nwrem_covmiss", strofreal(missing(`__nwrem_covevmat') - missing(diagonal(`__nwrem_covevmat'))))
		if `__nwrem_covmiss' > 0 {
			di as error "{p 0 0 2}covevent() network `covevent' has `__nwrem_covmiss' missing tie values; the covariate must be defined for every ordered pair of actors.{p_end}"
			error 416
		}
	}
	else {
		mata: `__nwrem_covevmat' = J(`nodes', `nodes', 0)
	}

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
		capture mata: mata drop `__nwrem_events' `__nwrem_covsnd' `__nwrem_covrec' `__nwrem_covint' `__nwrem_covevmat'
		if `__nwrem_bad0' > 0 {
			di as error "{p 0 0 2}`__nwrem_bad0' event(s) of `netname' have a sender or receiver that is not an actor of the network (a missing actor id, or an id that does not match a node label); drop these events before {cmd:nwset}.{p_end}"
		}
		if `__nwrem_badt' > 0 {
			di as error "{p 0 0 2}`__nwrem_badt' event(s) of `netname' have a missing event time; drop these events before {cmd:nwset}.{p_end}"
		}
		error 416
	}

	if `nevents' < 2 {
		di as error "nwrem needs at least 2 events to fit a model; `netname' has `nevents'."
		error 2001
	}

	mata: RemFitMulti(`__nwrem_events', `nodes', (`__nwrem_active'), `__nwrem_covsnd', `__nwrem_covrec', `__nwrem_covint', `__nwrem_covevmat', "__nwrem_b", "__nwrem_V", "__nwrem_ll")
	mata: mata drop `__nwrem_events' `__nwrem_covsnd' `__nwrem_covrec' `__nwrem_covint' `__nwrem_covevmat'

	tempname b V
	matrix `b' = __nwrem_b
	matrix `V' = __nwrem_V
	matrix colnames `b' = `__nwrem_collabs'
	matrix colnames `V' = `__nwrem_collabs'
	matrix rownames `V' = `__nwrem_collabs'
	local __nwrem_ll = __nwrem_ll
	matrix drop __nwrem_b __nwrem_V
	scalar drop __nwrem_ll

	ereturn post `b' `V', obs(`nevents')
	ereturn local cmd "nwrem"
	ereturn local version "1.1.1"
	ereturn local title "Relational event model (ordinal partial likelihood, MLE)"
	ereturn local depvar "`netname'"
	ereturn scalar N = `nevents'
	ereturn scalar nodes = `nodes'
	ereturn scalar ll = `__nwrem_ll'

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
	_nwrem_display, level(`level')
end

capture program drop _nwrem_display
program _nwrem_display
	syntax [, Level(cilevel)]
	di as text "{hline 60}"
	di as text "Relational event model (ordinal partial likelihood, MLE)"
	di as text "Network: " as result "`e(depvar)'" _col(40) as text "Actors: " as result e(nodes)
	di as text "Events: " as result e(N) _col(40) as text "Log likelihood: " as result %9.4f e(ll)
	di as text "{hline 60}"
	ereturn display, level(`level')
	if "`e(unidentified)'" != "" {
		di as text "{p 0 6 2}Note: no usable standard error for " as result "`e(unidentified)'" as text ".{p_end}"
		di as text "{p 6 6 2}These effects are not identified: typically an effect is an exact function of others in the model"   ///
			" (the total-degree share ntdegsnd is half the sum of nodsnd and nidsnd). Its estimate is arbitrary;"   ///
			" drop one of the effects.{p_end}"
	}
end
