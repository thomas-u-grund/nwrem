* dev/rem_benchmark.do -- wall-clock timing of nwrem's unit-1 Mata
* engine on the SAME event dataset dev/rem_benchmark.R timed with real
* relevent::rem.dyad(). See the development notes' "benchmark speed
* against it" entry.
*
* Real relevent::rem.dyad() reference timing (captured 2026-08-28, this
* exact dev/rem_bench_events.csv, n=30, nevents=2000, MLE, ordinal,
* effects=c("NODSnd","NIDRec"), hessian=FALSE): 1.538481 seconds
* (coefficients NIDRec=-3.822438, NODSnd=-1.203382 - a real, if noisy,
* MLE result per the development notes section 3a-ii's own disclosed
* finding about this effect family's finite-sample behavior; the point
* of this script is timing, not re-verifying the match already
* confirmed in dev/rem_relevent_crosscheck.do).

* (run from the root of this repository)
* The core package nwcommands is found through the environment variable NWCORE (path of the core checkout).
local nwcore : env NWCORE
if `"`nwcore'"' == "" {
	di as error "set the environment variable NWCORE to the directory of the nwcommands (core) package"
	exit 198
}
adopath ++ `"`nwcore'"'
adopath ++ `"`c(pwd)'"'
quietly do `"`nwcore'/unw_core.do"'
do unw_rem.do

import delimited "dev/rem_bench_events.csv", clear varnames(1)

mata:
sender = st_data(., "sender")
receiver = st_data(., "receiver")
eventtime = st_data(., "eventtime")
eventmat = (sender, receiver, eventtime)
end

timer clear 1
timer on 1
mata: RemFitUnit1(eventmat, 30, "bench_b", "bench_V", "bench_ll")
timer off 1
timer list 1

di as text "{hline 60}"
di as text "nwrem (Mata, unit 1) wall-clock: " %9.4f r(t1) " seconds"
di as text "relevent::rem.dyad wall-clock:   1.5385 seconds (dev/rem_benchmark.R, same data)"
di as text "speedup: " %6.2f (1.5385 / r(t1)) "x"
di as text "{hline 60}"
di as text "nwrem coefficients: NODSnd=" %9.4f el(bench_b,1,1) "  NIDRec=" %9.4f el(bench_b,1,2)
di as text "relevent coefficients: NODSnd=-1.2034  NIDRec=-3.8224"
