do setup.doh
* the employees (reporting hierarchy), kept aside in a file
quietly nwwebuse manufacturing_nodes, nwclear
tempfile staff
quietly save `staff'
quietly do mail.doh
*# cv_attr
nwload mail, xvars
describe, short
list in 1/4
*# cv_merge
gen str4 label = _nwnode
gen long row = _n
merge m:1 label using `staff', keep(master match) nogenerate
sort row
gen byte junior = (level >= 4)
list _nwnode level junior supervisor division in 1/4
tabulate level
*# cv_covsnd
nwrem mail, frpsndsnd frrecsnd covsnd(level) covrec(level)
*# cv_covint
nwrem mail, frpsndsnd covint(level)
*# cv_several
nwrem mail, frpsndsnd covsnd(level junior) covrec(level junior)
*# cv_pairs
mata:
V = st_sdata(., "supervisor")
D = st_sdata(., "division")
n = rows(V)
S = J(n, n, 0)
T = J(n, n, 0)
for (i = 1; i <= n; i++) {
    for (j = 1; j <= n; j++) {
        S[i, j] = (i != j) & (V[i] != "") & (V[i] == V[j])
        T[i, j] = (i != j) & (D[i] != "") & (D[i] == D[j])
    }
}
end
nwset, mat(S) name(samesup) directed
nwset, mat(T) name(samediv) directed
nwrem mail, frpsndsnd covevent(samesup)
estimates store one
nwrem mail, frpsndsnd covevent(samesup samediv)
estimates store two
estimates table one two, b(%9.3f) stats(ll N)
*# cv_collinear
nwrem mail, covsnd(level) covrec(level) covint(level)
*# cv_missing
replace level = . in 1
capture noisily nwrem mail, frpsndsnd covsnd(level)
display "return code: " _rc
