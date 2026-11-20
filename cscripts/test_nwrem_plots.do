cscript

* nwrem result graphs: estat rank, estat actors, estat time. Default graph names, name(), saving(), export() (files written), graph options
* (pass-through, last), title("") and a user title, black default titles, noplot, the option errors without a graph (198), data untouched,
* the message of a core without the shared graph helper (199). Run from the repository root (cscripts/run_tests.sh). Needs NWCORE >= 3.29.0.
capture program drop nwinstall
local nwcore : env NWCORE
if `"`nwcore'"' == "" {
	di as error "set the environment variable NWCORE to the directory of the nwcommands (core) package"
	exit 198
}
quietly do `"`nwcore'/unw_core.do"'
quietly do unw_rem.do
local out `"`c(tmpdir)'/nwrem_plots_test"'
capture mkdir `"`out'"'
foreach f in a1.gph a1.png b1.gph b1.png c1.gph c1.png d1.gph d1.png t1.png t2.png {
	capture erase `"`out'/`f'"'
}

* ---- the example: 5 actors, 22 events (as in test_nwrem_estat)
mata: EV = (1,2 \ 2,3 \ 3,1 \ 1,3 \ 4,5 \ 5,1 \ 2,1 \ 3,4 \ 1,2 \ 2,5 \ 5,3 \ 4,1 \ 1,4 \ 3,2 \ 2,4 \ 5,2 \ 1,5 \ 4,3 \ 3,5 \ 2,1 \ 1,3 \ 5,4)
nwclear
clear
quietly set obs 22
gen long sender = .
gen long receiver = .
mata: st_store(., ("sender", "receiver"), EV)
gen double t = (_n)^1.2
nwset sender receiver, eventtime(t) directed name(tiny)
nwload tiny, xvars
gen double xc = (_n == 2) + 2 * (_n == 4) - (_n == 5)
gen double canary = _n * 1.5
quietly nwrem tiny, nodsnd nidrec covsnd(xc)

* ---- default names
graph drop _all
estat rank
graph describe rank
estat rank, plot(hist) bins(5)
graph describe rank
estat actors
graph describe actors
estat actors, role(sender)
graph describe actors
estat time
graph describe time
di as text "  PASS: default graph names rank, actors, time"

* ---- name(), saving(), export() with graph options
foreach cmd in "estat rank" "estat rank, plot(hist)" "estat actors" "estat actors, role(receiver)" "estat time, bins(4)" {
	if strpos("`cmd'", ",") == 0 local cmd "`cmd',"
	graph drop _all
	capture erase `"`out'/s1.gph"'
	capture erase `"`out'/s1.png"'
	`cmd' name(gnm, replace) saving(`"`out'/s1"') export(`"`out'/s1.png"', width(700)) scheme(s2color)
	graph describe gnm
	confirm file `"`out'/s1.gph"'
	confirm file `"`out'/s1.png"'
	* replace is implied: the same call again
	`cmd' name(gnm) saving(`"`out'/s1.gph"', replace) export(`"`out'/s1.png"')
	di as text "  PASS: name(), saving(), export() of `cmd'"
}

* ---- pass-through goes last (the user's title wins), title("") suppresses the default, a user title is respected
estat rank, name(a1) export(`"`out'/t1.png"', width(600)) title("Custom title") xtitle("custom x")
estat rank, name(a2) export(`"`out'/t2.png"', width(600)) title("")
estat rank, name(a3) title("Own title", color(red)) subtitle("sub")
graph describe a3
quietly estat rank, name(d1) export(`"`out'/d1.png"', width(600))
foreach f in d1 t1 t2 {
	quietly checksum `"`out'/`f'.png"'
	local ck_`f' = r(checksum)
}
assert `ck_t1' != `ck_d1' & `ck_t2' != `ck_d1' & `ck_t1' != `ck_t2'
* the command of the graph: the user's options come last
quietly graph describe a1
assert strpos(`"`r(command)'"', "title(" + char(34) + "Custom title" + char(34) + ")") > strpos(`"`r(command)'"', "name(a1")
di as text "  PASS: pass-through options, title(), user title"

* ---- the default titles, axis titles are black; title("") leaves no title; the user's colour is respected
graph drop _all
foreach cmd in "estat rank" "estat rank, plot(hist)" "estat time" "estat actors" "estat actors, role(sender)" {
	if strpos("`cmd'", ",") == 0 local cmd "`cmd',"
	`cmd' name(bk)
	quietly graph describe bk
	local c `"`r(command)'"'
	assert strpos(`"`c'"', "title(") > 0
	assert strpos(`"`c'"', "color(black)") > 0
	`cmd' name(bk) title("")
	quietly graph describe bk
	assert strpos(`"`r(command)'"', `"title("")"') > 0
}
estat rank, name(bk) title("Mine", color(red))
quietly graph describe bk
assert strpos(`"`r(command)'"', "Rank diagnostic") == 0
di as text "  PASS: black default titles, title(""), user title"

* ---- estat actors: one role only (the book draws the sender panel), a short footnote that fits a 3.6 inch wide graph
graph drop _all
estat actors, role(sender) name(as1) export(`"`out'/as1.png"', width(1080)) xsize(3.6) ysize(2.2)
estat actors, role(receiver) name(as2) xsize(3.6) ysize(2.2)
estat actors, name(as3) xsize(3.6) ysize(2.2) export(`"`out'/as3.png"', width(1080))
quietly graph describe as1
assert strpos(`"`r(command)'"', "Expected events as receiver") == 0
assert strpos(`"`r(command)'"', "Expected events as sender") > 0
quietly graph describe as2
assert strpos(`"`r(command)'"', "Expected events as sender") == 0
quietly graph describe as3
assert strlen(`"`r(command)'"') > 0
confirm file `"`out'/as1.png"'
confirm file `"`out'/as3.png"'
* the footnote is one short line
quietly graph describe as3
assert strpos(`"`r(command)'"', "Dashed line: observed = expected.") > 0
assert strpos(`"`r(command)'"', "Extension of nwrem") == 0
di as text "  PASS: estat actors, role(sender|receiver), short footnote"

* ---- noplot: the table only, no graph is drawn; options without a graph are errors
graph drop _all
estat rank, noplot
estat actors, noplot
estat time, noplot
capture graph describe rank
assert _rc != 0
capture graph describe actors
assert _rc != 0
foreach cmd in "estat rank" "estat actors" "estat time" {
	capture `cmd', noplot name(x)
	assert _rc == 198
	capture `cmd', noplot saving(`"`out'/x.gph"')
	assert _rc == 198
	capture `cmd', noplot export(`"`out'/x.png"')
	assert _rc == 198
	capture `cmd', noplot title("x")
	assert _rc == 198
	capture `cmd', noplot scheme(s2color)
	assert _rc == 198
}
di as text "  PASS: noplot and the errors for options without a graph"

* ---- bad values and names (before any computation)
capture estat rank, name("bad name")
assert _rc == 198
capture estat rank, name(x, keep)
assert _rc == 198
capture estat rank, saving(`"`out'/nosuchdir/x.gph"')
assert _rc == 603
capture estat actors, export(`"`out'/nosuchdir/x.png"')
assert _rc == 603
capture estat rank, plot(pie)
assert _rc == 198
capture estat time, bins(1)
assert _rc == 198
capture estat actors, role(x)
assert _rc == 198
di as text "  PASS: error paths"

* ---- data and results untouched
quietly nwrem tiny, nodsnd nidrec covsnd(xc)
tempname b0
matrix `b0' = e(b)
quietly summarize canary
local s0 = r(sum)
local n0 = _N
estat rank, name(u1)
estat actors, name(u2)
estat time, name(u3)
quietly summarize canary
assert r(sum) == `s0' & _N == `n0'
assert mreldif(e(b), `b0') == 0
capture frame __nwrem_dgev: describe
assert _rc != 0
di as text "  PASS: data and e() untouched, no frames left"

* ---- a core without the helper: message and r(199), no computation (a stub of api 0 stands in for an old core)
local stub `"`c(tmpdir)'/nwrem_plots_stub"'
capture mkdir `"`stub'"'
capture erase `"`stub'/_nw_gfinish.ado"'
tempname fh
file open `fh' using `"`stub'/_nw_gfinish.ado"', write replace
file write `fh' "program define _nw_gfinish, rclass" _n "return scalar api = 0" _n "end" _n
file close `fh'
adopath ++ `"`stub'"'
capture program drop _nw_gfinish
capture noisily estat rank
assert _rc == 199
capture noisily estat time, bins(3)
assert _rc == 199
* the table without a graph needs no helper
estat rank, noplot
adopath - `"`stub'"'
capture program drop _nw_gfinish
erase `"`stub'/_nw_gfinish.ado"'
estat rank
graph describe rank
di as text "  PASS: core without the graph helper -> r(199) with a message; noplot still works"

di as text "ALL TESTS PASSED"
