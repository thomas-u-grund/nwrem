do setup.doh
*# ml_data
nwwebuse manufacturing, nwclear
list in 1/5
count
quietly levelsof sender, local(a) clean
quietly levelsof receiver, local(b) clean
local all : list a | b
display "actors in the log: " `: word count `all''
keep if t < 5
count
display "span in days: " %5.2f (t[_N] - t[1])
quietly levelsof sender, local(a) clean
quietly levelsof receiver, local(b) clean
local present : list a | b
local miss : list all - present
display "actors in the window: " `: word count `present'' ", added as isolates: " `: word count `miss''
nwset sender receiver, directed eventtime(t) name(mail)
local miss : subinstr local miss " " ",", all
nwaddnodes mail, nodenames(`miss')
nwset
*# ml_m1
nwrem mail, nodsnd nidrec
*# ml_m2
nwrem mail, frpsndsnd frrecsnd
display "events: " e(N) ", actors: " e(nodes) ", log likelihood: " %9.2f e(ll)
*# ml_m3
nwrem mail, nodsnd nidrec frpsndsnd frrecsnd
*# ml_replay
nwrem, level(90)
*# ml_ereturn
ereturn list
*# ml_ic
estimates stats
display "likelihood ratio against the model without effects: " %7.2f 2*(e(ll) - e(ll_0)) " on " e(df_m) " d.f."
*# ml_seed
nwrem mail, nodsnd nidrec frpsndsnd frrecsnd seed(1)
matrix b1 = e(b)
nwrem mail, nodsnd nidrec frpsndsnd frrecsnd seed(2)
matrix b2 = e(b)
display "largest difference between the two fits: " %9.2e mreldif(b1, b2)
*# ml_compare
quietly nwrem mail, nodsnd nidrec
estimates store m1
quietly nwrem mail, frpsndsnd frrecsnd
estimates store m2
quietly nwrem mail, nodsnd nidrec frpsndsnd frrecsnd
estimates store m3
estimates stats m1 m2 m3
lrtest m3 m1
lrtest m3 m2
