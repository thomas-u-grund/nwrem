cscript

* xt_rem_edges.do -- DRAFT, not yet run.
* Event-data edge grid for nwrem: unsorted input, events at time 0 and negative times, monotone time transforms, tied
* times (nwrem reads tied events one after another, in the order the network lists them), string / numeric / mixed /
* offset / non-consecutive actor ids, label permutations. Every assertion is either an invariance that follows from
* the definition of the ordinal partial likelihood (only the ORDER of the events enters) or a reference value of
* R relevent 1.2-1 (rem.dyad, ordinal=TRUE, hessian=TRUE) on the 40-event toy sequence W40 listed in xt_NOTES.md.
* Expected runtime: about 30 seconds (Stata 17 BE).
* Run from the repository root; the test runner sets the adopath (core and this repository). No sysdir/adopath here.

capture program drop nwinstall
local nwcore : env NWCORE
if `"`nwcore'"' != "" quietly do `"`nwcore'/unw_core.do"'
quietly do unw_rem.do

* ---------------------------------------------------------------------------------------------------------------------
* W40: 4 actors, 40 events, times 1..40 (generated once in R with set.seed(42); listed in xt_NOTES.md)
mata: XT_W40 = (1,3 \ 1,3 \ 1,3 \ 1,3 \ 2,1 \ 4,2 \ 2,4 \ 2,4 \ 1,3 \ 4,3 \ 3,1 \ 4,2 \ 3,2 \ 4,2 \ 1,3 \ 1,3 \ 2,4 \ 4,2 \ 2,4 \ 2,4 \ 3,1 \ 3,1 \ 1,2 \ 1,3 \ 3,4 \ 4,1 \ 1,3 \ 3,1 \ 1,2 \ 1,3 \ 4,2 \ 2,1 \ 4,2 \ 4,2 \ 3,2 \ 2,3 \ 1,3 \ 2,4 \ 4,2 \ 2,3)

capture program drop xt_w40
program xt_w40
	* the W40 event list in memory: sender receiver (numeric 1..4), t = 1..40, row = 1..40
	clear
	quietly set obs 40
	quietly gen long sender = .
	quietly gen long receiver = .
	mata: st_store(., ("sender", "receiver"), XT_W40)
	quietly gen double t = _n
	quietly gen long row = _n
end

capture program drop xt_same
program xt_same
	* xt_same "label" tol: e(b) and e(ll) equal the saved reference fit XB / XLL (tol 0 = identical bits)
	args label tol
	assert colsof(e(b)) == colsof(XB)
	assert mreldif(e(b), XB) <= `tol'
	assert reldif(e(ll), scalar(XLL)) <= `tol'
	assert e(N) == scalar(XN)
	di as text "  PASS: `label' (mreldif " %9.2e mreldif(e(b), XB) ")"
end

* ---------------------------------------------------------------------------------------------------------------------
di as text "{hline 60}"
di as text "Block A: reference fit on W40 = relevent (nodsnd nidrec)"
di as text "{hline 60}"
nwclear
xt_w40
nwset sender receiver, eventtime(t) directed name(w40)
nwrem w40, nodsnd nidrec seed(1)
assert e(N) == 40
assert e(nodes) == 4
* relevent 1.2-1: NODSnd 0.7303189 (se 0.8178162), NIDRec 0.9508733 (se 0.7872408), log likelihood -98.11630985
assert abs(_b[nodsnd] - 0.7303189) < 2e-3 * (1 + 0.7303189)
assert abs(_b[nidrec] - 0.9508733) < 2e-3 * (1 + 0.9508733)
assert reldif(e(ll), -98.11630985) < 1e-6
assert reldif(_se[nodsnd], 0.8178162) < 1e-2
assert reldif(_se[nidrec], 0.7872408) < 1e-2
matrix XB = e(b)
scalar XLL = e(ll)
scalar XN = e(N)
di as text "  PASS: W40 nodsnd nidrec = relevent (ll " %12.6f e(ll) ")"

* ---------------------------------------------------------------------------------------------------------------------
di as text "{hline 60}"
di as text "Block B: unsorted input rows give the identical fit (events are sorted by time inside nwrem)"
di as text "{hline 60}"
nwclear
xt_w40
set seed 990
gen double u = runiform()
sort u
nwset sender receiver, eventtime(t) directed name(w40u)
nwrem w40u, nodsnd nidrec seed(1)
xt_same "rows in random order" 1e-12
nwclear
xt_w40
gsort -t
nwset sender receiver, eventtime(t) directed name(w40r)
nwrem w40r, nodsnd nidrec seed(1)
xt_same "rows in reverse order" 1e-12

* ---------------------------------------------------------------------------------------------------------------------
di as text "{hline 60}"
di as text "Block C: time 0, negative times, monotone transforms of time (ordinal likelihood uses the order only)"
di as text "{hline 60}"
local k 0
foreach texp in "t - 20" "t - 1" "t * 1000" "t^3" "exp(t/10)" "-1/t" "t + 1e9" {
	local ++k
	nwclear
	xt_w40
	quietly replace t = `texp'
	nwset sender receiver, eventtime(t) directed name(wt`k')
	nwrem wt`k', nodsnd nidrec seed(1)
	xt_same "time = `texp'" 1e-12
}
* t - 20 contains time 0 (event 20) and negative times; t - 1 starts at time 0

* ---------------------------------------------------------------------------------------------------------------------
di as text "{hline 60}"
di as text "Block D: tied times are read one after another in the listed order"
di as text "{hline 60}"
* ceil(t/4): 10 time points of 4 events each, rows in the original order -> the same sequence as W40
nwclear
xt_w40
quietly replace t = ceil(t/4)
nwset sender receiver, eventtime(t) directed name(wtie)
nwrem wtie, nodsnd nidrec seed(1)
xt_same "ties, rows in time order" 1e-12
* all 40 events at ONE time point, rows in the original order -> still the W40 sequence
nwclear
xt_w40
quietly replace t = 0
nwset sender receiver, eventtime(t) directed name(wone)
nwrem wone, nodsnd nidrec seed(1)
xt_same "all events at time 0" 1e-12
* ties listed in reverse order inside each time point: equals distinct times given in that listed order
nwclear
xt_w40
quietly replace t = ceil(t/4)
gsort t -row
quietly gen double t2 = _n
tempfile rev
quietly save `rev'
nwset sender receiver, eventtime(t2) directed name(wrev2)
nwrem wrev2, nodsnd nidrec seed(1)
matrix XB2 = e(b)
scalar XLL2 = e(ll)
nwclear
use `rev', clear
nwset sender receiver, eventtime(t) directed name(wrev)
nwrem wrev, nodsnd nidrec seed(1)
assert mreldif(e(b), XB2) < 1e-12
assert reldif(e(ll), scalar(XLL2)) < 1e-12
di as text "  PASS: reversed ties = distinct times in the listed order"

* ---------------------------------------------------------------------------------------------------------------------
di as text "{hline 60}"
di as text "Block E: actor ids - string, mixed, offset, non-consecutive, permuted labels"
di as text "{hline 60}"
* string ids A1..A4 sort in the same order as 1..4
nwclear
xt_w40
gen str3 ss = "A" + string(sender)
gen str3 rs = "A" + string(receiver)
nwset ss rs, eventtime(t) directed name(wstr)
assert e(N) == 40
nwrem wstr, nodsnd nidrec seed(1)
xt_same "string ids A1..A4" 1e-12
* string ids whose sort order reverses the actors (1 -> d, ..., 4 -> a): a relabelling of the actors
nwclear
xt_w40
gen str1 ss = word("d c b a", sender)
gen str1 rs = word("d c b a", receiver)
nwset ss rs, eventtime(t) directed name(wperm)
nwrem wperm, nodsnd nidrec seed(1)
xt_same "string ids in reversed sort order (actor permutation)" 1e-5
* mixed: numeric sender, string receiver with the same ids
nwclear
xt_w40
gen str1 rs = string(receiver)
nwset sender rs, eventtime(t) directed name(wmix)
nwrem wmix, nodsnd nidrec seed(1)
xt_same "numeric sender, string receiver" 1e-12
* offset and non-consecutive numeric ids (order preserved)
local k 0
foreach map in "100 + @" "cond(@==1,1,cond(@==2,5,cond(@==3,17,1000)))" "10000000 + 2*@ - 1" "-10 + @" {
	local ++k
	nwclear
	xt_w40
	local es = subinstr("`map'", "@", "sender", .)
	local er = subinstr("`map'", "@", "receiver", .)
	quietly replace sender = `es'
	quietly replace receiver = `er'
	nwset sender receiver, eventtime(t) directed name(wid`k')
	nwrem wid`k', nodsnd nidrec seed(1)
	xt_same "ids `map'" 1e-12
}
* a numeric permutation of the ids (1->3, 2->1, 3->4, 4->2)
nwclear
xt_w40
quietly replace sender = cond(sender==1,3,cond(sender==2,1,cond(sender==3,4,2)))
quietly replace receiver = cond(receiver==1,3,cond(receiver==2,1,cond(receiver==3,4,2)))
nwset sender receiver, eventtime(t) directed name(wnperm)
nwrem wnperm, nodsnd nidrec seed(1)
xt_same "numeric id permutation" 1e-5

* ---------------------------------------------------------------------------------------------------------------------
di as text "{hline 60}"
di as text "Block F: valued event network (third variable) - the values are not used"
di as text "{hline 60}"
nwclear
xt_w40
gen double w = mod(_n, 3) + 1
nwset sender receiver w, eventtime(t) directed name(wval)
nwrem wval, nodsnd nidrec seed(1)
xt_same "valued event network" 1e-12

* ---------------------------------------------------------------------------------------------------------------------
di as text "{hline 60}"
di as text "Block G: duplicate rows (the same event twice at the same time) count twice"
di as text "{hline 60}"
* W40 with every event duplicated in place equals W80 = each event listed twice in a row with distinct times
nwclear
xt_w40
expand 2
sort row
quietly gen double t2 = _n
tempfile dup
quietly save `dup'
nwset sender receiver, eventtime(t) directed name(wdup)
nwrem wdup, nodsnd nidrec seed(1)
assert e(N) == 80
matrix XB3 = e(b)
scalar XLL3 = e(ll)
nwclear
use `dup', clear
nwset sender receiver, eventtime(t2) directed name(wdup2)
nwrem wdup2, nodsnd nidrec seed(1)
assert mreldif(e(b), XB3) < 1e-12
assert reldif(e(ll), scalar(XLL3)) < 1e-12
di as text "  PASS: duplicated events at one time = the same events at distinct times"

di "ALL PASS"
