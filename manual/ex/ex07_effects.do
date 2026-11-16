do setup.doh
do buildnet.doh
quietly nwwebuse manufacturing, nwclear
quietly keep if t < 5
* the 12 most active employees (senders and receivers together) and the e-mails among them
preserve
quietly contract sender, freq(ns)
rename sender actor
tempfile osend
quietly save `osend'
restore
preserve
quietly contract receiver, freq(nr)
rename receiver actor
quietly merge 1:1 actor using `osend', nogenerate
quietly replace ns = 0 if ns == .
quietly replace nr = 0 if nr == .
gen tot = ns + nr
gsort -tot actor
quietly keep in 1/12
quietly levelsof actor, local(top) clean
global allact "`top'"
restore
quietly gen byte ok = 0
quietly gen byte ok2 = 0
foreach x of local top {
    quietly replace ok = ok + (sender == "`x'")
    quietly replace ok2 = ok2 + (receiver == "`x'")
}
quietly keep if ok & ok2
*# ef_top
count
display "actors: $allact"
quietly levelsof sender, local(sn) clean
quietly levelsof receiver, local(rn) clean
local nsend : list global(allact) - sn
local nrec : list global(allact) - rn
display "never send: `nsend'   never receive: `nrec'"
nwbuild core12
nwsummarize core12
*# ef_triad
nwrem core12, nodsnd otpsnd itpsnd ospsnd ispsnd
*# ef_recency
nwrem core12, nodsnd nidrec frpsndsnd rsndsnd
*# ef_fe
nwrem core12, fesnd
*# ef_fepost
nwrem core12, fesnd postmode priorscale(2) priordf(.)
*# ef_feint
nwrem core12, ferec nodsnd
*# ef_ps
nwrem core12, psabba psabby psabxa psabxb psabxy psabay
