do setup.doh
quietly do mail.doh
*# pm_fits
nwrem mail, nodsnd nidrec frpsndsnd frrecsnd
estimates store mle
nwrem mail, nodsnd nidrec frpsndsnd frrecsnd postmode
estimates store weak
display "prior: mean " e(priormean) ", scale " e(priorscale) ", df " e(priordf)
nwrem mail, nodsnd nidrec frpsndsnd frrecsnd postmode priordf(.) priorscale(2)
estimates store normal2
nwrem mail, nodsnd nidrec frpsndsnd frrecsnd postmode priormean(3) priordf(.) priorscale(0.5)
estimates store normal05
*# pm_table
estimates table mle weak normal2 normal05, b(%9.3f) se(%9.3f) stats(ll N)
