cscript

* nwrem reads every event as directed from sender to receiver, whatever the nwset declaration says: a directed
* (nwset's default) and an undirected declaration of the same events give the same estimates (to the
* optimizer's tolerance), and the order of the two variables matters.

local nwcore : env NWCORE
if `"`nwcore'"' == "" {
	di as error "set the environment variable NWCORE to the directory of the nwcommands (core) package"
	exit 198
}
adopath ++ `"`nwcore'"'
adopath ++ `"`c(pwd)'"'
quietly do `"`nwcore'/unw_core.do"'
quietly do unw_rem.do

nwclear
nwwebuse socialevolution, nwclear
tempfile ev
quietly save `ev'
nwset sender receiver, eventtime(t) name(callsd)
nwrem callsd, nodsnd nidrec frpsndsnd frrecsnd
matrix bd = e(b)
scalar lld = e(ll)
assert e(N) == 439 | e(N) == .
use `ev', clear
nwset sender receiver, eventtime(t) name(callsu) undirected
nwrem callsu, nodsnd nidrec frpsndsnd frrecsnd
assert mreldif(bd, e(b)) < 1e-4
assert reldif(lld, e(ll)) < 1e-6
di as text "PASS: directed and undirected declarations give the same estimates"
* the order of the variables is the direction: swapping sender and receiver changes the fit
use `ev', clear
nwset receiver sender, eventtime(t) name(callsr)
nwrem callsr, nodsnd nidrec frpsndsnd frrecsnd
assert mreldif(bd, e(b)) > 1e-2
di as text "PASS: swapping sender and receiver changes the estimates"
