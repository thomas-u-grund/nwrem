do setup.doh
do buildnet.doh
* employees: division and level
quietly nwwebuse manufacturing_nodes, nwclear
quietly keep label division
rename label actor
tempfile staff
quietly save `staff'
quietly nwwebuse manufacturing, nwclear
quietly levelsof sender, local(a) clean
quietly levelsof receiver, local(b) clean
global allact : list a | b
quietly keep if t < 5
rename sender actor
quietly merge m:1 actor using `staff', keep(master match) nogenerate
rename actor sender
rename division divs
rename receiver actor
quietly merge m:1 actor using `staff', keep(master match) nogenerate
rename actor receiver
rename division divr
sort t
tempfile ev
quietly save `ev'
*# rs_cross
count
count if divs == divr
nwbuild mail
*# rs_within
quietly use `ev', clear
keep if divs == divr
nwbuild within
quietly nwload within, xvars
quietly gen actor = _nwnode
quietly gen long row = _n
quietly merge m:1 actor using `staff', keep(master match) nogenerate
quietly sort row
list _nwnode division in 1/3
*# rs_mask
mata:
D = st_sdata(., "division")
n = rows(D)
M = J(n, n, 0)
for (i = 1; i <= n; i++) {
    for (j = 1; j <= n; j++) M[i, j] = (i != j) & (D[i] == D[j])
}
end
nwset, mat(M) name(samediv) directed
mata: printf("ordered pairs that can be events: %g of %g\n", sum(M), n * (n - 1))
*# rs_fit
nwrem within, nodsnd nidrec frpsndsnd
nwrem within, nodsnd nidrec frpsndsnd riskset(samediv)
*# rs_error
capture noisily nwrem mail, nodsnd nidrec riskset(samediv)
display "return code: " _rc
*# rs_exit
quietly use `ev', clear
count if t > 4 & (divs == "E85" | divr == "E85")
count if t < 3.6 & (divs == "E70" | divr == "E70")
quietly nwload mail, xvars
quietly gen actor = _nwnode
quietly gen long row = _n
quietly merge m:1 actor using `staff', keep(master match) nogenerate
quietly sort row
quietly gen double leave = 4 if division == "E85"
quietly gen double join = 3.6 if division == "E70"
capture noisily nwrem mail, nodsnd nidrec exit(leave)
display "return code: " _rc
*# rs_window
quietly use `ev', clear
quietly drop if t > 4 & (divs == "E85" | divr == "E85")
quietly drop if t < 3.6 & (divs == "E70" | divr == "E70")
count
nwbuild mailw
quietly nwload mailw, xvars
quietly gen actor = _nwnode
quietly gen long row = _n
quietly merge m:1 actor using `staff', keep(master match) nogenerate
quietly sort row
quietly gen double leave = 4 if division == "E85"
quietly gen double join = 3.6 if division == "E70"
nwrem mailw, nodsnd nidrec frpsndsnd
nwrem mailw, nodsnd nidrec frpsndsnd entry(join) exit(leave)
