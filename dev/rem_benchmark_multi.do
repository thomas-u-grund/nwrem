* dev/rem_benchmark_multi.do -- wall-clock timing of nwrem's real
* end-to-end command (not RemFitMulti() called directly in Mata),
* fitting the full 8-effect degree+inertia model on the SAME event
* dataset dev/rem_benchmark_multi.R timed with real relevent::rem.dyad().
* See the development notes' "benchmark speed against it" entry - this
* extends dev/rem_benchmark.do's own unit-1-only (2-effect) timing to
* the full multi-effect engine, since the retry-based optimizer and the
* degree family's own collinearity ridge (the development notes' own
* "optimizer performance" finding) make per-effect-count timing
* behavior a real question, not a given from unit 1's own number alone.
*
* Real relevent::rem.dyad() reference timing (captured 2026-09-01, this
* exact dev/rem_bench_multi_events.csv, n=30, nevents=2000, MLE,
* ordinal, effects=8-effect degree+inertia model, hessian=FALSE):
* 107.7521 seconds.

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
* (not needed here: unw_ergm.do belongs to another package)
do unw_rem.do

nwclear
import delimited "dev/rem_bench_multi_events.csv", clear varnames(1)
nwset sender receiver, eventtime(eventtime) name(benchnet)

timer clear 2
timer on 2
nwrem benchnet, nodsnd nidrec nidsnd nodrec ntdegsnd ntdegrec frpsndsnd frrecsnd
timer off 2
timer list 2

di as text "{hline 60}"
di as text "nwrem (real command, 8-effect model) wall-clock: " %9.4f r(t2) " seconds"
di as text "relevent::rem.dyad wall-clock:                   107.7521 seconds (dev/rem_benchmark_multi.R, same data)"
di as text "speedup: " %6.2f (107.7521 / r(t2)) "x"
di as text "{hline 60}"
matrix list e(b)
