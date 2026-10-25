cscript

* Regression test: events with the same time (ties). The events were sorted by time with order() on the time column alone,
* which breaks ties arbitrarily (it depends on the state of the random-number generator), so the same data gave a different
* order of the tied events, a different likelihood and a different estimate from run to run (and between core versions).
* Tied events now keep the order in which the network lists them. Reference: relevent::rem.dyad() (version 1.2-1, ordinal=TRUE,
* effects NODSnd and NIDRec) on the same event sequence: NODSnd 9.18457, NIDRec 9.92774, log likelihood -2877.2243.

local nwcore : env NWCORE
if `"`nwcore'"' == "" {
	di as error "set the environment variable NWCORE to the directory of the nwcommands (core) package"
	exit 198
}
adopath ++ `"`nwcore'"'
adopath ++ `"`c(pwd)'"'
quietly do `"`nwcore'/unw_core.do"'
do unw_rem.do
global nwwebpath `"`nwcore'/data"'

nwclear
nwwebuse socialevolution, nwclear
generate tt = ceil(t/20)
generate long row = _n
sort tt row
duplicates report tt
nwset sender receiver, eventtime(tt) directed name(tied)

forvalues s = 1/4 {
	quietly nwrem tied, nodsnd nidrec seed(`s')
	assert reldif(e(ll), -2877.2243) < 1e-6
	assert reldif(el(e(b),1,1), 9.18457) < 1e-3
	assert reldif(el(e(b),1,2), 9.92774) < 1e-3
	di as text "  PASS: seed `s': ll " %10.4f e(ll) ", same as relevent"
}
di as result "ALL TESTS PASSED"
