cscript

* nwrem 1.4.0: effects that are exact functions of others are omitted (coefficient 0, no standard error), for all effects (also the
* state-dependent ones frpsndsnd, frrecsnd, rsndsnd, rrecsnd, the triadic, fixed-effect and participation-shift effects).
* cscripts/ref14/collinear.csv: for 39 tiny networks (2 and 3 actors, so that many effects become exactly dependent) the set of
* omitted coefficients found from the statistics of the R package relevent (dev/rem_relevent14_gen.R, section I).
local nwcore : env NWCORE
if `"`nwcore'"' == "" {
	di as error "set the environment variable NWCORE to the directory of the nwcommands (core) package"
	exit 198
}
quietly do `"`nwcore'/unw_core.do"'
quietly do unw_rem.do

local ref "cscripts/ref14"
tempfile col cases
import delimited "`ref'/collinear.csv", clear varnames(1) stringcols(1 2)
save `col'
import delimited "`ref'/cases.csv", clear varnames(1) asdouble stringcols(1 4 5 7)
keep if note == "dependence"
save `cases'
local ncase = _N
forvalues k = 1/`ncase' {
	local c`k' = case[`k']
	local o`k' = opts[`k']
}
local nomit = 0
local nwrong = 0
forvalues k = 1/`ncase' {
	use `cases', clear
	nwclear
	import delimited "`ref'/`c`k''.events.csv", clear varnames(1) asdouble
	nwset sender receiver, eventtime(t) name(net)
	quietly nwrem net, `o`k''
	matrix B = e(b)
	matrix V = e(V)
	use `col', clear
	keep if case == "`c`k''"
	local bad = 0
	local nd = 0
	forvalues i = 1/`=_N' {
		local p = param[`i']
		local j = colnumb(B, "`p'")
		if `j' >= . {
			di as error "case `c`k'': parameter `p' not in e(b)"
			local bad = 1
			continue
		}
		local omitted = (V[`j', `j'] == 0 & B[1, `j'] == 0)
		if `omitted' != dropped[`i'] {
			di as error "case `c`k'': `p' omitted by nwrem: `omitted', by the reference: `=dropped[`i']'"
			local bad = 1
		}
		local nd = `nd' + dropped[`i']
	}
	local nomit = `nomit' + `nd'
	local nwrong = `nwrong' + `bad'
	di as text %-8s "`c`k''" " parameters " as result %3.0f `=_N' as text "  omitted " as result %3.0f `nd' as text "   " as result cond(`bad', "DIFFERENT", "same")
}
assert `nwrong' == 0
assert `nomit' > 20
di as text "  PASS: the omitted coefficients agree with the reference in all `ncase' cases (`nomit' omitted coefficients in all)"
di "test_nwrem_collinear14: ALL OK"
