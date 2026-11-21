cscript
* nwrem 1.7.0: covmatch() (position / label matching of covevent() and riskset() networks), the matching note, the frpsndsnd
* convention, the estat actors note after interval. Run from the repository root with NWCORE set.
capture program drop nwinstall
local nwcore : env NWCORE
if `"`nwcore'"' == "" {
	di as error "set NWCORE"
	exit 198
}
adopath ++ `"`nwcore'"'
adopath ++ `"`nwcore'/lib"'
adopath ++ `"`c(pwd)'"'
adopath ++ `"`c(pwd)'/lib"'
adopath ++ `"`c(pwd)'/lib/plugins/macos"'

set linesize 250
* events among 8 actors with string labels a..h; covariate network built three ways
clear
set seed 20261121
set obs 300
gen str1 s = char(96 + ceil(8 * runiform()))
gen str1 r = char(96 + ceil(8 * runiform()))
drop if s == r
gen t = _n
nwset s r, eventtime(t) directed name(ev)

* dyadic covariate: value depends on the labels; networks from matrices so that the node order is under control
* cov_same: nodes in the order a..h (the order of the event network); cov_rev: the same values, nodes in the order h..a;
* cov_other: other labels
tempname M R
matrix `M' = J(8, 8, 0)
forvalues a = 1/8 {
	forvalues c = 1/8 {
		if `a' != `c' matrix `M'[`a', `c'] = 1 + (`a' < `c') + 2 * (`a' == 3)
	}
}
matrix `R' = J(8, 8, 0)
forvalues a = 1/8 {
	forvalues c = 1/8 {
		matrix `R'[9 - `a', 9 - `c'] = `M'[`a', `c']
	}
}
preserve
mata: nm_same = ("a","b","c","d","e","f","g","h"); nm_rev = nm_same[8..1]; nm_oth = "x" :+ nm_same
nwset, mat(`M') name(cov_same) nodenames(nm_same)
nwset, mat(`R') name(cov_R) nodenames(nm_same)
nwset, mat(`M') name(cov_rev) nodenames(nm_same)
* cov_rev: the matrix M with the node labels h..a (nwset aligns the labels of a new network to the existing ones, so they are set directly)
unw_defs
_nwsyntax cov_rev, max(1)
mata: `netobj'->set_nodenames(nm_rev)
nwset, mat(`M') name(cov_other) nodenames(nm_oth)
restore

* 1 position, labels agree
tempfile l2 l3 l4
nwrem ev, nodsnd covevent(cov_same)
tempname b0 b1
matrix `b0' = e(b)
assert "`e(covmatch)'" == "position"
* the numbers of version 1.6.0 (before covmatch() existed) with the same data
assert reldif(_b[nodsnd], -0.341499219247) < 1e-9 & reldif(_b[covevent_cov_same], 0.116355923544) < 1e-9
nwrem ev, nodsnd covevent(cov_same) covmatch(label)
matrix `b1' = e(b)
assert "`e(covmatch)'" == "label"
assert mreldif(`b0', `b1') < 1e-10
* the note texts
log using `l2', text replace name(b)
nwrem ev, nodsnd covevent(cov_same)
nwrem ev, nodsnd covevent(cov_same) covmatch(label)
nwrem ev, nodsnd covevent(cov_rev)
nwrem ev, nodsnd covevent(cov_other)
log close b
tempname fh
local txt ""
file open `fh' using `l2', read text
file read `fh' line
while r(eof) == 0 {
	local txt `"`txt' `line'"'
	file read `fh' line
}
file close `fh'
assert strpos(`"`txt'"', "matched to the event network by position (labels agree)")
assert strpos(`"`txt'"', "matched to the event network by label")
assert strpos(`"`txt'"', "DIFFERENT ORDER")
assert strpos(`"`txt'"', "labels DIFFER")

* 2 reversed label order: position gives other numbers than label; label reproduces the same-order fit
quietly nwrem ev, nodsnd covevent(cov_rev)
matrix `b1' = e(b)
* position matching ignores the labels: the numbers are those of cov_same, which has the same matrix
assert mreldif(`b0', `b1') < 1e-10
quietly nwrem ev, nodsnd covevent(cov_rev) covmatch(label)
matrix `b1' = e(b)
quietly nwrem ev, nodsnd covevent(cov_R)
assert mreldif(e(b), `b1') < 1e-8
assert mreldif(`b0', `b1') > 1e-3

* 3 different labels: label matching is an error, position runs with a warning
capture nwrem ev, nodsnd covevent(cov_other) covmatch(label)
assert _rc == 459
quietly nwrem ev, nodsnd covevent(cov_other)

* 4 option errors
capture nwrem ev, nodsnd covmatch(label)
assert _rc == 198
capture nwrem ev, nodsnd covevent(cov_same) covmatch(both)
assert _rc == 198

* 5 riskset by label
quietly nwrem ev, nodsnd riskset(cov_rev) covmatch(label)
quietly nwrem ev, nodsnd riskset(cov_R)
matrix `b0' = e(b)
quietly nwrem ev, nodsnd riskset(cov_rev) covmatch(label)
assert mreldif(`b0', e(b)) < 1e-10

* 6 estat after a label fit re-runs quietly and works
quietly nwrem ev, nodsnd covevent(cov_rev) covmatch(label)
estat rank, noplot
quietly nwrem ev, nodsnd covevent(cov_same) interval
log using `l3', text replace name(c)
estat actors, noplot
log close c
file open `fh' using `l3', read text
local txt ""
file read `fh' line
while r(eof) == 0 {
	local txt `"`txt' `line'"'
	file read `fh' line
}
file close `fh'
assert strpos(`"`txt'"', "waiting-time likelihood. The expected totals")
quietly nwrem ev, nodsnd covevent(cov_same)
log using `l4', text replace name(d)
estat actors, noplot
log close d
file open `fh' using `l4', read text
local txt ""
file read `fh' line
while r(eof) == 0 {
	local txt `"`txt' `line'"'
	file read `fh' line
}
file close `fh'
assert !strpos(`"`txt'"', "expected totals")

* 7 actor-level covariates: matched by label with _nwnode, whatever the row order
nwload ev, xvars
capture confirm variable _nwnode
assert !_rc
gen double z = strpos("abcdefgh", _nwnode) ^ 1.3
quietly nwrem ev, nodsnd covsnd(z)
matrix `b0' = e(b)
gsort -_nwnode
quietly nwrem ev, nodsnd covsnd(z)
* z is a function of the label, so the matching by label gives the same fit whatever the order of the rows
assert mreldif(`b0', e(b)) < 1e-10
di as result "test_nwrem_covmatch: done"
