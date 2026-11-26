cscript

* Regression test: events with the same time (ties). The events were sorted by time with order() on the time column alone,
* which breaks ties arbitrarily (it depends on the state of the random-number generator), so the same data gave a different
* order of the tied events, a different likelihood and a different estimate from run to run (and between core versions).
* Tied events now keep the order in which the network lists them. Reference: relevent::rem.dyad() (version 1.2-1, ordinal=TRUE,
* effects NODSnd and NIDRec) on the same event sequence (manufacturing emails with t < 4, 368 events, in two-hour bins): NODSnd 7.80720, NIDRec 18.19903, log likelihood -3196.5014.

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
nwwebuse manufacturing, nwclear
keep if t < 4
generate tt = ceil(t*12)
generate long row = _n
sort tt row
duplicates report tt
nwset sender receiver, eventtime(tt) directed name(tied) dropvars

forvalues s = 1/4 {
	quietly nwrem tied, nodsnd nidrec seed(`s')
	assert reldif(e(ll), -3196.5014) < 1e-6
	assert reldif(el(e(b),1,1), 7.80720) < 1e-3
	assert reldif(el(e(b),1,2), 18.19903) < 1e-3
	di as text "  PASS: seed `s': ll " %10.4f e(ll) ", same as relevent"
}
di as result "ALL TESTS PASSED"
