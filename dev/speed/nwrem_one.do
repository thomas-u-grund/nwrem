* one timed nwrem fit: env BENCH, SIZE, SET, REP, NWTREE, OUT
capture program drop nwinstall
local B : env BENCH
local size : env SIZE
local set : env SET
local rep : env REP
local out : env OUT
local tree : env NWTREE
adopath ++ `"`tree'"'
adopath ++ `"`tree'/lib"'
nwclear
import delimited "`B'/`size'_events.csv", clear varnames(1)
nwset sender receiver, eventtime(eventtime) name(bnet)
nwload bnet, xvars
local n = _N
import delimited "`B'/`size'_cov.csv", clear varnames(1)
tempfile cv
save `cv'
nwload bnet, xvars
merge 1:1 _n using `cv', nogenerate
local opts_S1_nodsnd_nidrec "nodsnd nidrec"
local opts_S2_degree4 "nodsnd nidrec nidsnd nodrec"
local opts_S3_degree4_inertia "nodsnd nidrec nidsnd nodrec frpsndsnd frrecsnd"
local opts_S4_recency "nodsnd nidrec rsndsnd rrecsnd"
local opts_S5_covariates "nodsnd nidrec covsnd(covsnd) covrec(covrec) covint(covint)"
timer clear 1
timer on 1
quietly nwrem bnet, `opts_`set'' seed(`rep')
timer off 1
quietly timer list 1
local secs = r(t1)
matrix b = e(b)
local cf ""
local nm : colnames b
forvalues j = 1/`=colsof(b)' {
	local cf "`cf' `=string(b[1,`j'], "%18.10g")'"
}
file open fh using "`out'", write text replace
file write fh `"`size',`set',`rep',`secs',"`cf'","`nm'",`=e(ll)',"`c(stata_version)'""' _n
file close fh
