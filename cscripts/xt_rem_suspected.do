cscript

* xt_rem_suspected.do -- DRAFT, not yet run.
* Checks of SUSPECTED bugs and code/help mismatches found by reading the code (details and file:line in xt_NOTES.md).
* Each check runs on its own (capture noisily { }); the file reports every failing check by name and stops with
* r(9) at the end if any failed. A failure here is a finding to look at, not necessarily a regression. Checks marked
* DESIGN encode a behaviour that is arguably right but not promised by the help file: decide, then keep or drop.
* The reference fit of every invariance check is W40 nodsnd nidrec (equal to relevent, see xt_rem_edges.do).
* Expected runtime: about 20 seconds (Stata 17 BE).
* Run from the repository root; the test runner sets the adopath. No sysdir/adopath here.

capture program drop nwinstall
local nwcore : env NWCORE
if `"`nwcore'"' != "" quietly do `"`nwcore'/unw_core.do"'
quietly do unw_rem.do

mata: XT_W40 = (1,3 \ 1,3 \ 1,3 \ 1,3 \ 2,1 \ 4,2 \ 2,4 \ 2,4 \ 1,3 \ 4,3 \ 3,1 \ 4,2 \ 3,2 \ 4,2 \ 1,3 \ 1,3 \ 2,4 \ 4,2 \ 2,4 \ 2,4 \ 3,1 \ 3,1 \ 1,2 \ 1,3 \ 3,4 \ 4,1 \ 1,3 \ 3,1 \ 1,2 \ 1,3 \ 4,2 \ 2,1 \ 4,2 \ 4,2 \ 3,2 \ 2,3 \ 1,3 \ 2,4 \ 4,2 \ 2,3)

capture program drop xt_w40
program xt_w40
	clear
	quietly set obs 40
	quietly gen long sender = .
	quietly gen long receiver = .
	mata: st_store(., ("sender", "receiver"), XT_W40)
	quietly gen double t = _n
end

local fails 0
local failed ""

nwclear
xt_w40
nwset sender receiver, eventtime(t) directed name(w40)
nwrem w40, nodsnd nidrec seed(1)
assert reldif(e(ll), -98.11630985) < 1e-6
matrix XB = e(b)
scalar XLL = e(ll)

* ---------------------------------------------------------------------------------------------------------------------
di as text "{hline 60}"
* CORE BUG S1 (cause in core nwset; nwrem refuses the events with r(416) until the core is fixed. Triage: ids of 8+ digits, i.e. >= 10,000,000, already fail; %9.0g prints 1.00e+07)
di as text "S1: numeric actor ids above 16,777,216 (not exact in float): 20000001, 20000003, ..."
di as text "{hline 60}"
* core nwset.ado:285-286 labels events "n" + strofreal(id) (format %9.0g) while nwfromedge builds the node names
* from a float dictionary with %18.0g (nwfromedge.ado:218, 246): the labels differ, events get actor index 0.
capture noisily {
	nwclear
	xt_w40
	replace sender = 20000000 + 2*sender - 1
	replace receiver = 20000000 + 2*receiver - 1
	nwset sender receiver, eventtime(t) directed name(wbig)
	nwrem wbig, nodsnd nidrec seed(1)
	assert e(nodes) == 4 & e(N) == 40
	assert mreldif(e(b), XB) < 1e-12
}
if _rc == 416 di as text "  CORE BUG S1 (not nwrem; nwrem refuses the unmatched events cleanly, r(416))"
else if _rc {
	local ++fails
	local failed "`failed' S1"
	di as error "  FAIL S1 (r(`=_rc')): large numeric ids"
}
else di as text "  PASS: S1"

* ---------------------------------------------------------------------------------------------------------------------
di as text "{hline 60}"
* CORE BUG S2 (same cause as S1)
di as text "S2: numeric actor ids 1e9, 2e9, 3e9, 4e9 (exact in float, but %9.0g prints 1.000e+09)"
di as text "{hline 60}"
capture noisily {
	nwclear
	xt_w40
	recast double sender receiver
	replace sender = sender * 1e9
	replace receiver = receiver * 1e9
	nwset sender receiver, eventtime(t) directed name(wbil)
	nwrem wbil, nodsnd nidrec seed(1)
	assert e(nodes) == 4 & e(N) == 40
	assert mreldif(e(b), XB) < 1e-12
}
if _rc == 416 di as text "  CORE BUG S2 (not nwrem; nwrem refuses the unmatched events cleanly, r(416))"
else if _rc {
	local ++fails
	local failed "`failed' S2"
	di as error "  FAIL S2 (r(`=_rc')): ids of 1e9 and more"
}
else di as text "  PASS: S2"

* ---------------------------------------------------------------------------------------------------------------------
di as text "{hline 60}"
* CONFIRMED BUG S3
di as text "S3: an event row with a missing sender"
di as text "{hline 60}"
* nwfromedge drops the missing id from the actors; build_eventlist gives the event actor index 0 (label "n." not
* found) and RemState indexes column 0: expected r(3301). Wanted: a clear refusal, or the row left out (e(N) = 40).
capture noisily {
	nwclear
	xt_w40
	set obs 41
	replace receiver = 2 in 41
	replace t = 41 in 41
	nwset sender receiver, eventtime(t) directed name(wmis)
	capture noisily nwrem wmis, nodsnd nidrec seed(1)
	local rc = _rc
	if `rc' == 0 assert e(N) == 40
	else assert `rc' < 3000 | `rc' > 3999
}
if _rc {
	local ++fails
	local failed "`failed' S3"
	di as error "  FAIL S3: missing sender gives a raw Mata error or is counted as an event"
}
else di as text "  PASS: S3"

* ---------------------------------------------------------------------------------------------------------------------
di as text "{hline 60}"
* CONFIRMED BUG S4
di as text "S4: an event row with a missing time"
di as text "{hline 60}"
* nwset stores the missing time; RemState sorts missing last, so the event silently becomes the LAST event.
capture noisily {
	nwclear
	xt_w40
	replace t = . in 10
	nwset sender receiver, eventtime(t) directed name(wmt)
	capture noisily nwrem wmt, nodsnd nidrec seed(1)
	local rc = _rc
	if `rc' == 0 assert e(N) == 39
	else assert `rc' < 3000 | `rc' > 3999
}
if _rc {
	local ++fails
	local failed "`failed' S4"
	di as error "  FAIL S4: an event without a time is used (placed last)"
}
else di as text "  PASS: S4"

* ---------------------------------------------------------------------------------------------------------------------
di as text "{hline 60}"
* DECIDED S5 (owner 2026-11-12): keep the relevent behaviour, an undirected event network is fitted as directed
* (documented in the help): same numbers as the directed declaration
di as text "S5: an undirected event network is fitted as directed"
di as text "{hline 60}"
capture noisily {
	nwclear
	xt_w40
	nwset sender receiver, eventtime(t) undirected name(wund)
	nwrem wund, nodsnd nidrec seed(1)
	assert mreldif(e(b), XB) < 1e-10
	assert reldif(e(ll), XLL) < 1e-10
}
if _rc {
	local ++fails
	local failed "`failed' S5"
	di as error "  FAIL S5: undirected event network not fitted as directed"
}
else di as text "  PASS: S5"

* ---------------------------------------------------------------------------------------------------------------------
di as text "{hline 60}"
* CONFIRMED BUG S6 (refused, but as r(111) after 32 "initial values not feasible" lines and "simplex delta required";
* wanted: a clean refusal like covevent(), r(416))
di as text "S6: covsnd() with a missing value"
di as text "{hline 60}"
* covevent() refuses missing values (r(416), nwrem.ado:115-118); covsnd/covrec/covint are read with st_data and never
* checked. Mata's sum() skips missing cells, so the dyads of that actor silently leave the risk set.
capture noisily {
	nwclear
	xt_w40
	nwset sender receiver, eventtime(t) directed name(wcm)
	nwload wcm, xvars
	gen double x = _n
	replace x = . in 2
	capture noisily nwrem wcm, covsnd(x) seed(1)
	assert _rc == 416
}
if _rc {
	local ++fails
	local failed "`failed' S6"
	di as error "  FAIL S6: missing covariate value accepted"
}
else di as text "  PASS: S6"

* ---------------------------------------------------------------------------------------------------------------------
di as text "{hline 60}"
* CONFIRMED BUG S7 (r(198) "covsnd_<name> invalid name" for any name longer than 25 characters)
di as text "S7: covariate with a 32-character name (column name covsnd_<name> has 39 characters)"
di as text "{hline 60}"
* closed form for x01 = (0,0,1,1): theta = -0.302280871873 (xt_rem_closedform.do)
capture noisily {
	nwclear
	xt_w40
	nwset sender receiver, eventtime(t) directed name(wln)
	nwload wln, xvars
	gen double abcdefghijabcdefghijabcdefghij12 = (_n >= 3)
	gen double abcdefghijabcdefghijabcdefghij13 = (_n >= 3)
	nwrem wln, covsnd(abcdefghijabcdefghijabcdefghij12) covrec(abcdefghijabcdefghijabcdefghij13) seed(1)
	assert colsof(e(b)) == 2
	local names : colnames e(b)
	local n1 : word 1 of `names'
	local n2 : word 2 of `names'
	assert "`n1'" != "`n2'"
	nwrem wln, covsnd(abcdefghijabcdefghijabcdefghij12) seed(1)
	assert abs(el(e(b),1,1) - (-0.302280871873)) < 1e-4
}
if _rc {
	local ++fails
	local failed "`failed' S7"
	di as error "  FAIL S7 (r(`=_rc')): long covariate names"
}
else di as text "  PASS: S7"

* ---------------------------------------------------------------------------------------------------------------------
di as text "{hline 60}"
* CONFIRMED BUG S8 (minor: seed(-1) is silently unseeded)
di as text "S8: seed(-1) is the internal 'not given' value"
di as text "{hline 60}"
* nwrem.ado:15 SEED(integer -1), line 131: -1 means 'no seed'. seed(-1) is either refused or (help: 'the seed makes the
* fit reproducible') reproducible; today it silently uses the current random-number state.
capture noisily {
	nwclear
	xt_w40
	nwset sender receiver, eventtime(t) directed name(wsd)
	set seed 5
	capture noisily nwrem wsd, nodsnd nidrec frpsndsnd seed(-1)
	local rc1 = _rc
	if `rc1' == 0 {
		matrix XS1 = e(b)
		set seed 6
		nwrem wsd, nodsnd nidrec frpsndsnd seed(-1)
		assert mreldif(e(b), XS1) == 0
	}
}
if _rc {
	local ++fails
	local failed "`failed' S8"
	di as error "  FAIL S8: seed(-1) is ignored"
}
else di as text "  PASS: S8"

* ---------------------------------------------------------------------------------------------------------------------
di as text "{hline 60}"
* CONFIRMED BUG S9 (owner 2026-11-12: covariates must be matched via _nwnode when present, not by row)
di as text "S9 (DESIGN): covariate dataset not in actor order although _nwnode is there"
di as text "{hline 60}"
* the covariate is read by row position (help: 'one row per actor, in actor order'). After nwload, xvars the data
* carry _nwnode; a sort silently misaligns the covariate. Wanted: align by _nwnode, or refuse when _nwnode is out of
* order. Closed form for x01 aligned: -0.302280871873.
capture noisily {
	nwclear
	xt_w40
	nwset sender receiver, eventtime(t) directed name(wso)
	nwload wso, xvars
	gen double x01 = (_n >= 3)
	gsort -_nwnode
	capture noisily nwrem wso, covsnd(x01) seed(1)
	if _rc == 0 assert abs(el(e(b),1,1) - (-0.302280871873)) < 1e-4
}
if _rc {
	local ++fails
	local failed "`failed' S9"
	di as error "  FAIL S9: covariate read by row position from a re-sorted dataset"
}
else di as text "  PASS: S9"

* ---------------------------------------------------------------------------------------------------------------------
* CONFIRMED BUG N2 (found in triage): a self-loop event is refused in RemState::init (unw_rem.do:79) with a message of
* about 130 characters; Mata _error(errtxt) fails on texts over ~110 characters with r(3300) "argument out of range"
* and the message is lost. Wanted: r(3498) with the self-loop message.
di as text "{hline 60}"
di as text "N2: self-loop event gives r(3498) with its message"
di as text "{hline 60}"
capture noisily {
	nwclear
	clear
	quietly set obs 4
	gen long sender = cond(_n == 3, 3, _n)
	gen long receiver = cond(_n == 3, 3, mod(_n, 3) + 1)
	gen double t = _n
	nwset sender receiver, eventtime(t) directed name(wloop)
	capture noisily nwrem wloop, nodsnd seed(1)
	assert _rc == 3498
}
if _rc {
	local ++fails
	local failed "`failed' N2"
	di as error "  FAIL N2: self-loop refusal loses its message (r(3300))"
}
else di as text "  PASS: N2"

* ---------------------------------------------------------------------------------------------------------------------
di as text "{hline 60}"
di as text "N1: replay (nwrem alone, nwrem, level(90), estimates replay)"
di as text "{hline 60}"
capture noisily {
	nwclear
	xt_w40
	nwset sender receiver, eventtime(t) directed name(wrp)
	nwrem wrp, nodsnd nidrec seed(1)
	matrix XR = e(b)
	estimates store xtrp
	nwrem
	nwrem, level(90)
	ereturn clear
	estimates replay xtrp
	estimates restore xtrp
	nwrem
	assert mreldif(e(b), XR) == 0
	ereturn clear
	capture nwrem
	assert _rc == 301
	estimates drop xtrp
}
if _rc {
	local ++fails
	local failed "`failed' N1"
	di as error "  FAIL N1: replay"
}
else di as text "  PASS: N1"

if `fails' > 0 {
	di as error "suspected problems confirmed: `failed'"
	exit 9
}
di "ALL PASS"
