* dev/rem_relevent_crosscheck.do -- fits nwrem's own unit-1 engine on the
* EXACT SAME event data dev/rem_relevent_crosscheck.R fit with real
* relevent::rem.dyad(), for a direct, real cross-tool comparison -
* matching nwsaom's own development discipline
* (dev/saom_rsiena_crosscheck.do) of checking against a real reference
* implementation on identical data, not a self-consistency check alone.
*
* Real relevent::rem.dyad() reference (effects=c("NODSnd","NIDRec"),
* ordinal=TRUE, fit.method="MLE", this exact
* dev/rem_crosscheck_events.csv - see dev/rem_relevent_crosscheck.R's
* own real console output, captured 2026-08-28):
*   NIDRec = 0.9514706  (SE 0.7887066)
*   NODSnd = -0.5744956 (SE 1.0999637)

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

import delimited "dev/rem_crosscheck_events.csv", clear varnames(1)

mata:
sender = st_data(., "sender")
receiver = st_data(., "receiver")
eventtime = st_data(., "eventtime")
eventmat = (sender, receiver, eventtime)

n_actors = 10
bname = "nwrem_b"
vname = "nwrem_V"
llname = "nwrem_ll"
RemFitUnit1(eventmat, n_actors, bname, vname, llname)
end

di as text "{hline 60}"
di as text "nwrem fit on the SAME event data as the real relevent::rem.dyad() run above:"
di as text "  NODSnd = " %9.7f el(nwrem_b,1,1) "   (relevent: -0.5744956)"
di as text "  NIDRec = " %9.7f el(nwrem_b,1,2) "   (relevent:  0.9514706)"

scalar reldiff_nodsnd = abs(el(nwrem_b,1,1) - (-0.5744956))
scalar reldiff_nidrec = abs(el(nwrem_b,1,2) - 0.9514706)
di as text "{hline 60}"
di as text "abs difference vs. real relevent: NODSnd=" %9.7f reldiff_nodsnd "  NIDRec=" %9.7f reldiff_nidrec

* Both are MLE for the identical likelihood on the identical data (see
* the development notes section 3a-ii for why point-recovery against a
* "true" theta is NOT used as a pass/fail bar elsewhere in this
* project's own REM certification, but agreement between TWO
* independent MLE implementations on the SAME fixed data has no such
* excuse - they are climbing the identical likelihood surface and
* should land at (numerically) the identical optimum).
assert reldiff_nodsnd < 0.01
assert reldiff_nidrec < 0.01

di as result "MATCH CONFIRMED (agreement to better than 1e-2)"
