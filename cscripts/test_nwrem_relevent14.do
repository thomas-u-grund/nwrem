cscript

* nwrem 1.4.0 against the R package relevent (1.2-1) on fixed reference values: the waiting-time (interval) likelihood, conditioned
* events, the triadic and shared-partner effects, fixed effects, participation shifts, several covariates per effect, several
* covariate networks, posterior-mode estimation (relevent's "BPM"), risk sets (dyad mask, entry and exit windows).
* cscripts/ref14/ holds the event logs, covariates and networks and the reference values; dev/rem_relevent14_gen.R made them.
* Two reference routes (see the generator): "trust" = relevent's own statistics fitted by rem() (analytic gradient and Hessian: the
* exact maximum; nwrem must agree to 1e-6 in the coefficients and the standard errors, 1e-9 in the log likelihood) and "dyad" =
* rem.dyad() itself (BFGS with a numerical Hessian, stops at the fifth to sixth digit of the coefficients: 1e-4 here).
local nwcore : env NWCORE
if `"`nwcore'"' == "" {
	di as error "set the environment variable NWCORE to the directory of the nwcommands (core) package"
	exit 198
}
quietly do `"`nwcore'/unw_core.do"'
quietly do unw_rem.do

local ref "cscripts/ref14"
tempfile res cases
import delimited "`ref'/results.csv", clear varnames(1) asdouble stringcols(1 2 3)
save `res'
import delimited "`ref'/cases.csv", clear varnames(1) asdouble stringcols(1 4 5 7)
save `cases'

capture program drop chk14
program chk14
	args case ref res cases
	use `cases', clear
	keep if case == "`case'"
	local opts = opts[1]
	local nets = nets[1]
	local hasact = actors[1]
	nwclear
	foreach nm of local nets {
		import delimited "`ref'/`case'.`nm'.csv", clear varnames(1) asdouble
		nwset i j value, name(`nm') edgelist directed
	}
	import delimited "`ref'/`case'.events.csv", clear varnames(1) asdouble
	nwset sender receiver, eventtime(t) name(net)
	if "`hasact'" == "true" | "`hasact'" == "TRUE" {
		nwload net, xvars
		gen long aid = real(substr(_nwnode, 2, .))
		preserve
		import delimited "`ref'/`case'.actors.csv", clear varnames(1) asdouble
		tempfile act
		save `act'
		restore
		merge 1:1 aid using `act', keep(master match) nogen
	}
	quietly nwrem net, `opts'
	matrix B = e(b)
	matrix V = e(V)
	local ll = e(ll)
	use `res', clear
	keep if case == "`case'"
	local maxb = 0
	local maxs = 0
	local maxl = 0
	local maxbd = 0
	local maxsd = 0
	forvalues i = 1/`=_N' {
		local p = param[`i']
		local j = colnumb(B, "`p'")
		if `j' >= . {
			di as error "case `case': parameter `p' of relevent is not in e(b) of nwrem"
			exit 9
		}
		local db = abs(B[1, `j'] - coef[`i']) / (1 + abs(coef[`i']))
		local ds = abs(sqrt(V[`j', `j']) - se[`i']) / (1 + abs(se[`i']))
		local dl = abs(`ll' - ll[`i']) / (1 + abs(ll[`i']))
		if route[`i'] == "trust" {
			local maxb = max(`maxb', `db')
			local maxs = max(`maxs', `ds')
			local maxl = max(`maxl', `dl')
		}
		else {
			local maxbd = max(`maxbd', `db')
			local maxsd = max(`maxsd', `ds')
		}
	}
	di as text %-12s "`case'" " exact: coef " as result %9.2e `maxb' as text "  se " as result %9.2e `maxs' as text "  ll " as result %9.2e `maxl' ///
		as text "   rem.dyad: coef " as result %9.2e `maxbd' as text "  se " as result %9.2e `maxsd'
	if `maxb' > 1e-5 | `maxs' > 1e-5 | `maxl' > 1e-9 {
		di as error "case `case': nwrem and relevent (exact route) differ"
		global nfail14 = $nfail14 + 1
	}
	if `maxbd' > 2e-4 | `maxsd' > 2e-4 {
		di as error "case `case': nwrem and rem.dyad differ"
		global nfail14 = $nfail14 + 1
	}
end

global nfail14 = 0
use `cases', clear
drop if note == "dependence"
local ncase = _N
forvalues k = 1/`ncase' {
	local c`k' = case[`k']
}
forvalues k = 1/`ncase' {
	chk14 `c`k'' `ref' `res' `cases'
}
assert $nfail14 == 0
di as text "  PASS: nwrem agrees with relevent in all `ncase' cases"
di "test_nwrem_relevent14: ALL OK"
