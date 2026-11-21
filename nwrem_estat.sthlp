{smcl}
{* *! version 1.7.0  21nov2026 author: Thomas Grund}{...}
{helpb nwtopical##analysis_dynamicmodels:[NW-2.6.8] Dynamic & Event-Based Models}

{title:Title}

{p2colset 9 26 28 2}{...}
{p2col :nwrem postestimation {hline 2}}Postestimation diagnostics and graphs for nwrem: rank, actors, time{p_end}
{p2colreset}{...}


{title:Syntax}

{p 8 17 2}
{cmd:estat} {cmdab:rank} [{cmd:,} {opt topk(#)} {opt plot(cdf|hist)} {opt bins(#)} {opt nop:lot}
{opt name(name)} {opt sav:ing(filename)} {opt exp:ort(filename [, graph_export_options])} {it:twoway_options}]

{p 8 17 2}
{cmd:estat} {cmdab:actors} [{cmd:,} {opt role(both|sender|receiver)} {opt lab:els} {opt lis:t} {opt noe:qual} {opt nop:lot}
{opt name(name)} {opt sav:ing(filename)} {opt exp:ort(filename [, graph_export_options])} {it:graph_options}]

{p 8 17 2}
{cmd:estat} {cmdab:time} [{cmd:,} {opt bins(#)} {opt topk(#)} {opt nop:lot}
{opt name(name)} {opt sav:ing(filename)} {opt exp:ort(filename [, graph_export_options])} {it:twoway_options}]


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
After a fit with {opt interval} the expected counts are summed rate integrals of a model without a baseline rate: their total need not equal
the observed number of events (in a simulation 424.8 expected against 120 observed), and the table says so in a note. Judge such a fit by the
correlations and the pattern around the 45 degree line, not by the level.

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

{phang}{opt role(string)} {cmd:both} (default; two panels), {cmd:sender} or {cmd:receiver} (one panel only, in the graph and in the picture; the table and {cmd:r()} always hold both roles).

{phang}{opt labels} labels the points of {cmd:estat actors} with the actor names. {opt list} lists the table of all actors.

{phang}{opt noequal} ({cmd:estat actors}) lets the two axes of a panel have different ranges; by default both run from 0 to the same maximum and the panel is square, so that the 45 degree line is the diagonal.

{phang}{opt noplot} shows the table only. {opt name()}, {opt saving()}, {opt export()} and graph options need the graph and are errors with {opt noplot}.

{phang}{opt name(name)} names the graph in memory. The default names are {cmd:rank}, {cmd:actors} and {cmd:time}; an existing graph of that name is replaced. A trailing {cmd:, replace} is accepted and ignored.

{phang}{opt saving(filename)} saves the graph as a {cmd:.gph} file (extension added; an existing file is replaced).

{phang}{opt export(filename [, graph_export_options])} exports the graph with {cmd:graph export}; the extension sets the format ({cmd:.png}, {cmd:.pdf}, {cmd:.svg} ...), an existing file is replaced, and options such as {opt width()} are those of {helpb graph export}.

{phang}{it:twoway_options} are all other options. They go to {cmd:twoway} ({cmd:histogram} for {cmd:plot(hist)}; {cmd:graph combine} for the two panels of {cmd:estat actors}), appended last, so they override the defaults, for example {opt scheme()}, {opt title()} or {opt xlabel()}. The default titles are black; {cmd:title("")} removes the title.

{pstd}
The graph needs the core package nwcommands, version 3.29.0 or later; with an older core the graph stops with r(199) and a message ({opt noplot} works with any core).


{title:Examples}

{pstd}Fit a model to an event network and check its predictive accuracy:{p_end}

	{cmd:. nwrem chat, nodsnd nidrec frpsndsnd rsndsnd}
	{cmd:. estat rank, topk(5)}
	{cmd:. estat rank, plot(hist) bins(20)}

{pstd}Activity of the individual actors and the course over time:{p_end}

	{cmd:. estat actors, labels}
	{cmd:. estat time, bins(8)}
	{cmd:. estat actors, role(sender) labels}

{pstd}Name a graph, save it and export it as a picture, with a graph option:{p_end}

	{cmd:. estat rank, name(rk) saving(rank) export(rank.png, width(1200)) scheme(s2color)}


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
{pstd}{it:nwrem version 1.7.0, 21 November 2026}{p_end}{* nwversion}
