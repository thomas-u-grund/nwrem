{smcl}
{* *! version 1.5.1  18nov2026 author: Thomas Grund}{...}
{helpb nwtopical##analysis_dynamicmodels:[NW-2.6.8] Dynamic & Event-Based Models}

{title:Title}

{p2colset 9 26 28 2}{...}
{p2col :nwrem postestimation {hline 2}}Postestimation diagnostics and graphs for nwrem: rank, actors, time{p_end}
{p2colreset}{...}


{title:Syntax}

{p 8 17 2}
{cmd:estat} {cmdab:rank} [{cmd:,} {opt topk(#)} {opt plot(cdf|hist)} {opt bins(#)} {opt nog:raph} {it:twoway_options}]

{p 8 17 2}
{cmd:estat} {cmdab:actors} [{cmd:,} {opt role(both|sender|receiver)} {opt lab:els} {opt lis:t} {opt nog:raph} {it:graph_options}]

{p 8 17 2}
{cmd:estat} {cmdab:time} [{cmd:,} {opt bins(#)} {opt topk(#)} {opt nog:raph} {it:twoway_options}]


{title:Description}

{pstd}
These {cmd:estat} subcommands check how well a fitted relational event model reproduces the data. Each one evaluates the
fitted linear predictor of {it:every} dyad of the risk set at {it:every} event, in the compiled plugin of the package,
at the coefficients stored in {cmd:e(b)}. R's {it:relevent} has no such diagnostics: they are extensions of {cmd:nwrem}.

{pstd}
The model is set up again exactly as for the fit: {cmd:estat} runs the data preparation of the command line stored in
{cmd:e(cmdline)}. The network and the covariate variables used in the fit must therefore still be in memory, unchanged.
Neither the estimation results nor the data in memory are changed. The effort is that of one evaluation of the likelihood
over all dyads of every risk set, so it grows with the number of events times the square of the number of actors; no
effect of the model needs to be refitted. Events that only build the history ({opt condition()}) are left out of all
quantities.

{pstd}
{cmd:estat rank} reports, for every event, the rank of the observed sender-receiver pair among all dyads of the risk set
by the fitted linear predictor (rank 1 = the pair the model finds most likely), the standard check of the predictive
accuracy of a relational event model. Dyads with exactly the same predictor share the mid-rank. The table gives
the mean and median rank, the mean percentile rank (rank divided by the size of the risk set), the share of events in
the top {it:k}, and the mean log probability of the observed dyad, each next to its value for a model without effects
(every dyad equally likely). The share of top-{it:k} hits is also shown as it is expected under the fitted model (the summed
probability of the {it:k} most likely dyads); ties at the border of the top {it:k} count fractionally.
The graph is the cumulative distribution of the percentile ranks (a curve above the diagonal means that the
observed dyads rank better than chance), or with {cmd:plot(hist)} their histogram against the uniform density.

{pstd}
{cmd:estat actors} compares, for every actor, the observed number of events as sender and as receiver with the number the
model expects: the sum over the events of the model probability that the actor is the sender (receiver) of the event; under
the waiting-time likelihood the summed rate integrals. The table reports the correlation of observed and expected counts and
the sum of squared Pearson residuals (describing the fit; not a test). The graph is a scatter plot with the 45 degree line.

{pstd}
{cmd:estat time} compares observed and expected quantities over the event sequence in {opt bins()} bins of equally many consecutive
events (deciles by default). With the waiting-time likelihood ({opt interval}) these are the number of events and the
integrated rate of the model over the intervals that end with those events (the last bin also carries the final
interval up to {opt endtime()}). The waiting-time model has no baseline rate: a level of the expected curve that is far
from the observed one says that the effects cannot reproduce the overall rate of events. The ordinal likelihood
has no time scale; there the bins show the number of events whose observed dyad is among the {it:k} most likely dyads
and the number expected under the model.


{title:Options}

{phang}{opt topk(#)} size {it:k} of the top set for the share of hits; default 10.

{phang}{opt plot(cdf|hist)} the graph of {cmd:estat rank}: {cmd:cdf} (default) or {cmd:hist}.

{phang}{opt bins(#)} number of bins: histogram bins of {cmd:estat rank, plot(hist)} (default 10) or time bins of
{cmd:estat time} (default 10; at most the number of events).

{phang}{opt role(string)} {cmd:both} (default; two panels), {cmd:sender} or {cmd:receiver}.

{phang}{opt labels} labels the points of {cmd:estat actors} with the actor names. {opt list} lists the table of all actors.

{phang}{opt nograph} shows the table only.

{phang}{it:twoway_options} are passed to the graph, for example {opt name()}, {opt saving()} or {opt scheme()}.


{title:Examples}

{pstd}Fit a model to an event network and check its predictive accuracy:{p_end}

	{cmd:. nwrem chat, nodsnd nidrec frpsndsnd rsndsnd}
	{cmd:. estat rank, topk(5)}
	{cmd:. estat rank, plot(hist) bins(20)}

{pstd}Activity of the individual actors and the course over time:{p_end}

	{cmd:. estat actors, labels}
	{cmd:. estat time, bins(8)}


{title:Stored results}

{pstd}{cmd:estat rank} stores in {cmd:r()}:{p_end}
{synoptset 22 tabbed}{...}
{synopt:{bf:r(N)}}number of events evaluated{p_end}
{synopt:{bf:r(topk)}}{it:k}{p_end}
{synopt:{bf:r(mean_rank)}, {bf:r(median_rank)}}mean and median (mid-)rank{p_end}
{synopt:{bf:r(mean_pct_rank)}}mean percentile rank{p_end}
{synopt:{bf:r(hit)}}share of events in the top {it:k}{p_end}
{synopt:{bf:r(hit_model)}}the same share expected under the fitted model{p_end}
{synopt:{bf:r(hit_null)}}the same share for a model without effects{p_end}
{synopt:{bf:r(mean_logp)}, {bf:r(mean_logp_null)}}mean log probability of the observed dyad, fitted and without effects{p_end}
{synopt:{bf:r(mean_risksize)}}mean size of the risk set{p_end}

{pstd}{cmd:estat actors} stores {cmd:r(n_actors)}, {cmd:r(corr_sender)}, {cmd:r(corr_receiver)}, {cmd:r(chi2_sender)}, {cmd:r(chi2_receiver)}
and the matrix {cmd:r(actors)} (one row per actor in the order of the network; columns {cmd:obs_sender},
{cmd:exp_sender}, {cmd:obs_receiver}, {cmd:exp_receiver}).

{pstd}{cmd:estat time} stores {cmd:r(n_bins)}, {cmd:r(topk)}, {cmd:r(obs_total)}, {cmd:r(exp_total)} and the matrix {cmd:r(bins)} (one row per bin;
columns {cmd:events}, {cmd:time_from}, {cmd:time_to}, {cmd:observed}, {cmd:expected}).


{title:Also see}

{p 4 14 2}Help: {help nwrem}{p_end}

{hline}
{pstd}{it:nwrem version 1.5.1, 18 November 2026}{p_end}{* nwversion}
