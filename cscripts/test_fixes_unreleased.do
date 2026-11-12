cscript

* The note on effects without a usable standard error describes the total-degree share correctly: ntdegsnd is the
* average of the out-degree and in-degree shares, (nodsnd + nidsnd)/2, as in relevent (NTDegSnd). Run from the
* repository root with NWCORE set.
capture program drop nwinstall
local nwcore : env NWCORE
if `"`nwcore'"' == "" {
	di as error "set the environment variable NWCORE to the directory of the nwcommands (core) package"
	exit 198
}
adopath ++ `"`nwcore'"'
adopath ++ `"`nwcore'/lib"'
adopath ++ `"`c(pwd)'"'
adopath ++ `"`c(pwd)'/lib"'
quietly do `"`nwcore'/unw_core.do"'
do unw_rem.do
global nwwebpath `"`nwcore'/data"'

capture program drop _fx_has
program _fx_has, rclass
	args file text
	mata: st_numscalar("r(has)", strpos(stritrim(invtokens(cat(st_local("file"))', " ")), st_local("text")) > 0)
	return scalar has = r(has)
end

nwclear
nwwebuse socialevolution, nwclear
nwset sender receiver, eventtime(t) directed name(calls)

tempfile lg
log using `"`lg'"', text replace name(fx1)
nwrem calls, nodsnd nidsnd ntdegsnd seed(1)
log close fx1
assert "`e(unidentified)'" == "ntdegsnd"
_fx_has `"`lg'"' "half the sum of nodsnd and nidsnd"
assert r(has) == 1
_fx_has `"`lg'"' "is the sum of nodsnd"
assert r(has) == 0
di "PASS ntdegsnd note"

di "ALL PASS"
