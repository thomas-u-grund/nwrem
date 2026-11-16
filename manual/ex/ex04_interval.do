do setup.doh
do buildnet.doh
* all 144 actors of the data
quietly nwwebuse manufacturing, nwclear
quietly levelsof sender, local(a) clean
quietly levelsof receiver, local(b) clean
global allact : list a | b
*# iv_ties
keep if t < 5
duplicates report t
tempfile ev
quietly save `ev'
nwbuild mail
capture noisily nwrem mail, nodsnd nidrec frpsndsnd interval
display "return code: " _rc
*# iv_ordinal
use `ev', clear
duplicates drop t, force
nwbuild mail1
nwrem mail1, nodsnd nidrec frpsndsnd
estimates store ordinal
*# iv_days
nwrem mail1, nodsnd nidrec frpsndsnd interval starttime(3.2) endtime(5)
display "log likelihood " %9.1f e(ll) ", of the null model " %9.1f e(ll_0)
*# iv_unit
* the time unit in which the null model has a rate of 1 per ordered pair: the length of the window times n(n-1) / N
scalar unit = (5 - 3.2) * 144 * 143 / 628
display "one time unit = " %5.1f unit " days"
quietly use `ev', clear
quietly duplicates drop t, force
quietly replace t = (t - 3.2) / unit
quietly nwbuild mail2
nwrem mail2, nodsnd nidrec frpsndsnd interval starttime(0) endtime(`=(5 - 3.2) / unit')
estimates store interval
display "likelihood: " e(lik) "   window: " e(starttime) " to " %6.4f e(endtime) "   log likelihood of the null model: " %9.2f e(ll_0)
*# iv_default
nwrem mail2, nodsnd nidrec frpsndsnd interval
display "window: " e(starttime) " to " %6.4f e(endtime)
*# iv_cond
nwrem mail2, nodsnd nidrec frpsndsnd interval starttime(0) endtime(`=(5 - 3.2) / unit') condition(100)
display "events: " e(N) "   conditioned: " e(N_cond)
nwrem mail2, nodsnd nidrec frpsndsnd condition(100)
*# iv_table
estimates table ordinal interval, b(%9.3f) se(%9.3f) stats(ll N)
