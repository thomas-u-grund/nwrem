cscript

* Fits of the manufacturing e-mails (core data) through nwrem, which runs in the compiled plugin, against the values that the
* dense Mata evaluator of nwrem 1.1.2 gave: t < 5 (631 events) and t < 14 (2,738 events); collinear effects are found before the
* optimizer. (The plugin against the Mata reference evaluators on random systems is test_nwrem_plugin.do.)
local nwcore : env NWCORE
if `"`nwcore'"' == "" {
	di as error "set the environment variable NWCORE to the directory of the nwcommands (core) package"
	exit 198
}
quietly do `"`nwcore'/unw_core.do"'
do unw_rem.do

global nwwebpath `"`nwcore'/data"'
capture program drop fx_check
* fx_check b1 se1 b2 se2 ... ll : coefficients and standard errors in the order of e(b), then the log likelihood
program fx_check
	local k = colsof(e(b))
	assert `: word count `0'' == 2 * `k' + 1
	forvalues j = 1/`k' {
		local b : word `=2 * `j' - 1' of `0'
		local se : word `=2 * `j'' of `0'
		assert reldif(el(e(b), 1, `j'), `b') < 5e-4
		assert reldif(sqrt(el(e(V), `j', `j')), `se') < 5e-4
	}
	* the reference values stop where BFGS met its default tolerances: the log likelihood of the plugin fit is at least as high
	assert e(ll) > `: word `=2 * `k' + 1' of `0'' - 1e-6 * abs(e(ll)) * 1e-3
	assert reldif(e(ll), `: word `=2 * `k' + 1' of `0'') < 1e-9
end

nwclear
nwwebuse manufacturing, nwclear
keep if t < 5
nwset sender receiver, eventtime(t) name(mail)
nwload mail, xvars
rename _nwnode label
merge 1:1 label using `"`nwcore'/data/manufacturing_nodes.dta"', keep(master match) nogen
nwexpand supervisor, name(samesup) replace

* reference values: the dense evaluator (nwrem 1.1.2), seed(1)
nwrem mail, nodsnd nidrec seed(1)
assert e(N) == 631
fx_check 10.64882306124531 1.31731033712525 20.73028624148009 1.11369268043664 -5645.075307669897
di as text "  PASS: nodsnd nidrec, t < 5"
nwrem mail, nodsnd nidrec frpsndsnd seed(1)
fx_check 10.30295972562383 1.51210053679934 13.15074665803199 1.27184441305766 3.79098865926030 0.13830188555596 -5425.429175266350
di as text "  PASS: + frpsndsnd, t < 5"
nwrem mail, nodsnd nidrec rsndsnd seed(1)
fx_check 7.10578989093174 1.36388956447462 10.33988522392113 1.26359423934455 3.65589437989141 0.10421383098377 -5252.617684989861
di as text "  PASS: + rsndsnd, t < 5"
nwrem mail, nodsnd nidrec covevent(samesup) seed(1)
fx_check 10.58507173891137 1.30253315152242 20.83310084586524 1.10922834273615 1.18022703180076 0.12312834738686 -5610.832551451944
di as text "  PASS: + covevent, t < 5"
nwrem mail, nodsnd nidrec frrecsnd rrecsnd seed(1)
fx_check 9.46998111817661 1.22568790937882 20.38789405029889 1.19352716176800 -0.40491274841219 0.21013347268920 4.51218646262584 0.14461893337039 -5044.169981016455
di as text "  PASS: + frrecsnd rrecsnd, t < 5"
nwrem mail, nidsnd nodrec ntdegrec frpsndsnd covevent(samesup) rsndsnd seed(1)
fx_check 7.50347041242392 1.38273846419740 -4.81899841616153 1.43910344771914 24.16805171703267 2.26366065823397 -0.28780248137577 0.23438452560943 0.71341274078179 0.12581291340925 3.72988657978465 0.15922683507044 -5231.713149577919
di as text "  PASS: six effects (state-dependent and static dyadic together), t < 5"

* collinear effects: found before the optimizer; the likelihood is the one of the model without the dependent effect
timer clear 1
timer on 1
nwrem mail, nodsnd nidsnd ntdegsnd seed(1)
timer off 1
quietly timer list 1
assert "`e(unidentified)'" == "ntdegsnd"
assert reldif(e(ll), -5778.042686824900) < 1e-9
assert el(e(b), 1, 3) == 0 & el(e(V), 3, 3) == 0
* the estimable combinations, nodsnd + ntdegsnd / 2 and nidsnd + ntdegsnd / 2, of the dense fit (its three coefficients are
* arbitrary along the flat ridge, and it stops before the ridge is explored: agreement to about 1e-4 only)
assert reldif(el(e(b), 1, 1), 7.64797196875559 + 6.29515027664899 / 2) < 1e-3
assert reldif(el(e(b), 1, 2), 4.84750666544571 + 6.29515027664899 / 2) < 1e-3
assert r(t1) < 30
di as text "  PASS: nodsnd nidsnd ntdegsnd: ntdegsnd unidentified, same log likelihood as the dense evaluator (" as result %5.2f r(t1) as text " s)"

* the whole t < 14 window (2,738 events, 129 actors): the dense evaluator needed 20 s for this fit
nwclear
nwwebuse manufacturing, nwclear
keep if t < 14
nwset sender receiver, eventtime(t) name(mail14)
timer clear 2
timer on 2
nwrem mail14, nodsnd nidrec seed(1)
timer off 2
quietly timer list 2
assert e(N) == 2738
fx_check 36.99530642404960 1.47878890471070 35.10519198237711 0.68826037436318 -25292.5437341
assert r(t2) < 60
di as text "  PASS: nodsnd nidrec, t < 14 (2,738 events) in " as result %5.2f r(t2) as text " s"

di as result "ALL TESTS PASSED"
