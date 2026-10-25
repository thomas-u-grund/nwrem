cscript

* Regression test: nwrem with ntdegsnd together with nodsnd and nidsnd. The three shares are exactly collinear
* (total-degree share = out-degree share + in-degree share); the fit returned a missing standard error for
* ntdegsnd and no warning. It now prints a note and returns the effect in e(unidentified).

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
nwset sender receiver, eventtime(t) directed name(calls)

nwrem calls, nodsnd nidsnd ntdegsnd
assert "`e(unidentified)'" == "ntdegsnd"
di as text "  PASS: collinear ntdegsnd is reported (e(unidentified) = `e(unidentified)')"

nwrem calls, nodsnd nidrec
assert "`e(unidentified)'" == ""
di as text "  PASS: identified fit has empty e(unidentified)"
di as result "ALL TESTS PASSED"
