local nwcore : env NWCORE
quietly do `"`nwcore'/unw_core.do"'
quietly do unw_rem.do
do /private/tmp/claude-501/-Users-tgrund-FILES-NEW-SOFTWARE-nwcommands/9d5243e9-ee49-4558-835d-02925b410730/scratchpad/rem_more_work/t/bench_data.do
scalar __nev = 0
quietly nwrem ev, nodsnd nidrec frpsndsnd
di "NEVALS " scalar(__nev)
scalar __nev = 0
quietly nwrem ev, nodsnd nidrec nidsnd nodrec frpsndsnd frrecsnd
di "NEVALS " scalar(__nev)
