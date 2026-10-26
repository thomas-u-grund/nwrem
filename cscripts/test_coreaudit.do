cscript

* Core 3.6.0 audit: covevent() reads the tie values of a one-mode network (valued or binary, by value); a two-mode
* network is refused with the common message (error 6088, it holds missing cells between nodes of the same mode, which
* used to end in repeated "initial values not feasible"); a network with missing tie values stops with error 416.
* A valued event network (a weight variable in nwset) is accepted: relevent has no event weights, they are ignored.

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
clear
set obs 300
gen long sender = .
gen long receiver = .
gen eventtime = _n
gen double w = 1 + floor(runiform()*3)
mata:
mata set matastrict off
rseed(20260902)
for (i=1; i<=300; i++) {
	pair = runiformint(1, 2, 1, 10)
	while (pair[1] == pair[2]) pair = runiformint(1, 2, 1, 10)
	st_store(i, "sender", pair[1])
	st_store(i, "receiver", pair[2])
}
end
tempfile ev
save "`ev'"
nwset sender receiver, eventtime(eventtime) name(ev0)
use "`ev'", clear
nwset sender receiver w, eventtime(eventtime) name(ev1)
_nwsyntax ev1, max(1)
assert "`valued'" == "true"

* valued event network: same estimates as the unweighted one (the weights are not used)
nwrem ev0, nodsnd nidrec
matrix B0 = e(b)
nwrem ev1, nodsnd nidrec
assert mreldif(B0, e(b)) < 1e-3
di as text "  PASS: a valued event network is accepted"

mata: rseed(7); M = (runiform(10,10):<.3); st_matrix("__S", M); M2 = M :* (1:+floor(runiform(10,10):*4)); st_matrix("__V", M2)
mata: M3 = M; M3[2,3] = .; st_matrix("__M", M3)
nwset, mat(__S) directed name(st0) nooutput
nwset, mat(__V) directed name(stv) nooutput
nwset, mat(__M) directed name(miss) nooutput
mata: st_matrix("__T", (runiform(6,4):<.4))
nwset, mat(__T) bipartite name(two10) nooutput
_nwsyntax two10, max(1)
assert `nodes' == 10 & "`is2mode'" == "true"

* covevent with a binary and a valued network: the valued one uses the values (a covariate, as in relevent)
nwrem ev0, nodsnd covevent(st0)
assert colsof(e(b)) == 2
nwrem ev0, nodsnd covevent(stv)
assert colsof(e(b)) == 2
* the valued covariate is not the binary one: a different coefficient (the values 1-4 enter the covariate)
nwrem ev0, nodsnd covevent(stv)
local bv = el(e(b),1,2)
nwrem ev0, nodsnd covevent(st0)
assert abs(`bv' - el(e(b),1,2)) > 1e-4

* two-mode and missing: refused
capture nwrem ev0, nodsnd covevent(two10)
assert _rc == 6088
capture nwrem ev0, nodsnd covevent(miss)
assert _rc == 416
di as text "  PASS: covevent() with valued, two-mode and missing covariate networks"
di as text "test_coreaudit (nwrem) PASS"
