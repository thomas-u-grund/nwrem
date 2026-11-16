{smcl}
{* *! version 1.4.0  16nov2026 author: Thomas Grund}{...}
{marker topic}
{helpb nwtopical##analysis_dynamicmodels:[NW-2.6.8] Dynamic & Event-Based Models}

{title:Title}

{p2colset 9 15 22 2}{...}
{p2col :nwrem  {hline 2}}Relational event model (ordinal or waiting-time likelihood, maximum likelihood or posterior mode){p_end}
{p2colreset}{...}


{title:Syntax}

{p 8 17 2}
{cmdab: nwrem}
[{it:{help netname}}]
{cmd:,}
[{opt nodsnd}
{opt nidrec}
{opt nidsnd}
{opt nodrec}
{opt ntdegsnd}
{opt ntdegrec}
{opt frpsndsnd}
{opt frrecsnd}
{opth covsnd(varlist)}
{opth covrec(varlist)}
{opth covint(varlist)}
{opth covevent(netlist)}
{opt rsndsnd}
{opt rrecsnd}
{opt otpsnd}
{opt itpsnd}
{opt ospsnd}
{opt ispsnd}
{opt fesnd}
{opt ferec}
{opt feint}
{opt psabba}
{opt psabby}
{opt psabxa}
{opt psabxb}
{opt psabxy}
{opt psabay}
{opt int:erval}
{opt start:time(#)}
{opt end:time(#)}
{opt cond:ition(#)}
{opth risk:set(netname)}
{opth entry(varname)}
{opth exit(varname)}
{opt postmode}
{opt priormean(#)}
{opt priorscale(#)}
{opt priordf(#)}
{opt seed(#)}
{opt ci}
{opt level(#)}
{it:display_options}]


{synoptset 20 tabbed}{...}
{synopthdr}
{synoptline}
{syntab:Degree effects}
{synopt:{opt nodsnd}}sender's normalized out-degree affects the sending rate (share of all prior events in which this actor was the sender){p_end}
{synopt:{opt nidrec}}receiver's normalized in-degree affects the receiving rate (share of all prior events in which this actor was the receiver){p_end}
{synopt:{opt nidsnd}}sender's normalized in-degree affects the sending rate{p_end}
{synopt:{opt nodrec}}receiver's normalized out-degree affects the receiving rate{p_end}
{synopt:{opt ntdegsnd}}sender's normalized total degree (in+out, averaged) affects the sending rate{p_end}
{synopt:{opt ntdegrec}}receiver's normalized total degree (in+out, averaged) affects the receiving rate{p_end}
{syntab:Inertia effects}
{synopt:{opt frpsndsnd}}"inertia": the fraction of the sender's own past sends that went specifically to this receiver affects the sending rate to that receiver{p_end}
{synopt:{opt frrecsnd}}"reciprocity of receipt": the fraction of the sender's own past receipts that came specifically from this receiver affects the sending rate to that receiver{p_end}
{syntab:Covariate effects}
{synopt:{opth covsnd(varlist)}}numeric per-actor covariates (one coefficient each) affect the sending rate (an "ego" effect - the variables are read from the CURRENT dataset, one row per actor,
matched to the actors by their node labels - see {help nwload}'s {opt xvars} option below){p_end}
{synopt:{opth covrec(varlist)}}numeric per-actor covariates affect the receiving rate (an "alter" effect){p_end}
{synopt:{opth covint(varlist)}}numeric per-actor covariates affect both the sending and the receiving rate together (the same variable, one shared coefficient){p_end}
{synopt:{opth covevent(netlist)}}one or several pairwise (dyad-level) covariates, each affects the rate of the event from sender to receiver directly - {it:netname} must already be a loaded network with the SAME actors
as the event network, one value per ordered (sender,receiver) pair (read from its own tie values, exactly like {help nwergm}'s {opt edgecov()}); a two-mode network is refused (error 6088) and so is a
network with missing tie values{p_end}
{syntab:Recency effects}
{synopt:{opt rsndsnd}}"recency of sending": how RECENTLY (not how often) the sender previously sent to this receiver affects the sending rate to that receiver again (1/rank among the sender's own past
receivers, most recent = rank 1; 0 if never sent to before){p_end}
{synopt:{opt rrecsnd}}"recency of receipt": how RECENTLY (not how often) the sender previously received from this receiver affects the sending rate back to that receiver (1/rank among the sender's own
past senders, most recent = rank 1; 0 if never received from before) - a recency-based reciprocity effect{p_end}
{syntab:Triadic and shared-partner effects}
{synopt:{opt otpsnd}}outbound two-paths: the number of actors {it:k} to whom the sender has sent and who have sent to the receiver (as the sum over {it:k} of the smaller of the two counts) affects the sending rate{p_end}
{synopt:{opt itpsnd}}inbound two-paths: the same count for the paths from the receiver through some {it:k} to the sender{p_end}
{synopt:{opt ospsnd}}outbound shared partners: the number of actors to whom both sender and receiver have sent (sum over the partners of the smaller of the two counts){p_end}
{synopt:{opt ispsnd}}inbound shared partners: the same for the actors who have sent to both sender and receiver{p_end}
{syntab:Fixed effects}
{synopt:{opt fesnd}}one coefficient for the sending rate of every actor except the first (the reference actor); {bf:fesnd_2}, {bf:fesnd_3} ...{p_end}
{synopt:{opt ferec}}the same for the receiving rate{p_end}
{synopt:{opt feint}}one coefficient per actor (except the first) that applies to the actor both as sender and as receiver{p_end}
{syntab:Participation shifts (the previous event is A to B)}
{synopt:{opt psabba}}the next event is the reply, B to A{p_end}
{synopt:{opt psabby}}B sends to someone other than A{p_end}
{synopt:{opt psabxa}}someone other than A and B sends to A{p_end}
{synopt:{opt psabxb}}someone other than A and B sends to B{p_end}
{synopt:{opt psabxy}}neither actor of the next event is A or B{p_end}
{synopt:{opt psabay}}A sends again, to someone other than B{p_end}
{syntab:Likelihood and estimation}
{synopt:{opt interval}}waiting-time (interval) likelihood: the times between events enter the likelihood, so the model describes the rate of events and not only their order; requires strictly increasing event times{p_end}
{synopt:{opt starttime(#)}}start of the observation, with {opt interval}; default 0{p_end}
{synopt:{opt endtime(#)}}end of the observation, with {opt interval}; the last interval, from the last event to the end, enters as a survival term; default the time of the last event{p_end}
{synopt:{opt condition(#)}}the first {it:#} events only build the history of the statistics and do not enter the likelihood{p_end}
{synopt:{opth riskset(netname)}}network with the same actors; a tie value of 0 means that the ordered pair can never be an event, any other value that it can; the pairs that are not possible leave the risk set at every event{p_end}
{synopt:{opth entry(varname)}}per-actor time of entry: before it the actor is not in the risk set (as sender or receiver); missing means present from the start{p_end}
{synopt:{opth exit(varname)}}per-actor time of exit: after it the actor leaves the risk set; missing means present until the end{p_end}
{synopt:{opt postmode}}posterior mode instead of maximum likelihood: independent Student t priors on all coefficients (R {cmd:relevent}'s {cmd:fit.method="BPM"}){p_end}
{synopt:{opt priormean(#)}}location of the prior; default 0{p_end}
{synopt:{opt priorscale(#)}}scale of the prior; default 100{p_end}
{synopt:{opt priordf(#)}}degrees of freedom of the prior; default 4; {cmd:priordf(.)} is a normal prior{p_end}
{syntab:}
{synopt:{opt seed(#)}}set the random-number seed before estimation; the fit starts from zero and uses random starting values only when the Newton iteration
does not reach a maximum (no maximum exists, or effects are not identified), so the seed makes such fits reproducible; different seeds give the same MLE up to the
convergence tolerance, except along the flat likelihood ridges described in the note on precision below; {it:#} is an integer between 0 and 2147483647{p_end}
{synopt:{opt ci}}Show the confidence intervals in the coefficient table. By default the table shows the coefficient names in full, and the intervals are left out (as with {opt noci}) at a {cmd:set linesize} below 100, where names of up to 32 characters do not fit next to them. With {opt ci} the intervals are shown and long names are cut (e.g. {cmd:covevent_sa~p}){p_end}
{synopt:{opt level(#)}}confidence level of the intervals; giving it also shows them, as {opt ci}; default {cmd:level(95)} or as set by {cmd:set level}{p_end}
{synopt:{it:{help estimation_options##display_options:display_options}}}{opt noci}, {opt nopvalues}, {opt cformat(%fmt)}, {opt pformat(%fmt)}, {opt sformat(%fmt)} and the other display options of Stata's estimation commands{p_end}
{synoptline}
{p2colreset}{...}
{pstd}At least one effect must be specified. Typed without arguments (or with display options only: {opt ci}, {opt level()}, ...),
{cmd:nwrem} redisplays the results of the last {cmd:nwrem} fit; {cmd:estimates replay} works as well.{p_end}


{title:Description}

{pstd}
{cmd:nwrem} fits a relational event model (Butts 2008, "A Relational Event Framework for Social
Action," {it:Sociological Methodology} 38(1), 155-200) to a timestamped sequence of dyadic
events. By default it uses the ordinal partial likelihood: at each event, the model asks "given that some event
happened next, which of the {it:n}({it:n}-1) possible ordered actor pairs was it," and estimates
which actor-level effects make the realized event more likely relative to every other pair that
could have happened instead - the same conditional-likelihood logic Cox proportional-hazards
models use.

{pstd}
Unlike {help nwergm} (static structure) and {help nwsaom} (discrete panel-wave evolution),
{cmd:nwrem} works directly on a raw, continuous-time event stream - no snapshot or aggregation
step. It requires {it:netname} to already be declared as an {bf:event}-type temporal network via
{help nwset}'s {opt eventtime(varname)} option:

	{cmd:. nwset sender receiver, eventtime(t) name(mynet)}
	{cmd:. nwrem mynet, nodsnd nidrec}

{pstd}
{bf:Direction.} {cmd:nwrem} accepts a directed and an undirected declaration alike, and no option
is needed: the plain declaration above (directed, {help nwset}'s default) is the usual one; an
{bf:undirected} declaration is not required. Every event is read as a directed event from the
first variable (the sender) to the second (the receiver), and the risk set at each event is the
{it:n}({it:n}-1) ordered pairs, whatever the declaration says. Adding {opt undirected} to
{cmd:nwset} changes only the network summary that {cmd:nwset} builds from the events (for example
in {cmd:nwsummarize}), not the events or the estimates of {cmd:nwrem}. The sender and receiver
effects ({bf:nodsnd}, {bf:nidrec}, {bf:frrecsnd} ...) depend on the order of the two variables, so
put the actor who starts the event first. Events between two actors without a sender (undirected
events) are not modeled as such; {cmd:nwrem} treats the first actor as the sender.

{pstd}
{bf:Speed}: {cmd:nwrem} evaluates the likelihood, its gradient and its Hessian in a compiled plugin and maximises the likelihood
with Newton steps. It was timed against R's
{cmd:relevent::rem.dyad()} 1.2-1 ({cmd:ordinal=TRUE}, maximum likelihood) on simulated event streams of 200 to
20,000 events among 20 to 100 actors, with five effect sets: {bf:nodsnd nidrec}; {bf:nodsnd nidrec nidsnd nodrec};
these four with {bf:frpsndsnd frrecsnd}; {bf:nodsnd nidrec rsndsnd rrecsnd}; and {bf:nodsnd nidrec} with
{bf:covsnd covrec covint}. {cmd:nwrem} always computes the covariance matrix, so the like-for-like setting of
{cmd:relevent} is {cmd:hessian=TRUE}; with {cmd:hessian=FALSE} (the default of {cmd:relevent}) it is 1.1 to 2.2
times faster than that. Both settings were timed. {cmd:nwrem} 1.3.0 was run in Stata 17 on 16 November 2026, the
times of {cmd:relevent} (R 4.6.0) are from 26 and 27 October 2026, both on the same Apple M5 Pro; every fit ran in
its own process after an untimed warm-up fit; the ratios are ratios of medians (7 fits of {cmd:nwrem};
5, 3 or 1 fits of {cmd:relevent} in the cells where it needed more than a minute). The first call in a
Stata session takes about 0.05 seconds longer, because the Mata library and the plugin are loaded; it is not in the times.

{pstd}
{cmd:nwrem} was faster than {cmd:relevent} in every cell in which both programs finished: the ratio of the time of
{cmd:relevent} to the time of {cmd:nwrem} ranged from 33 to 4,130 with {cmd:hessian=TRUE} and from 23 to 2,544 with
{cmd:hessian=FALSE}. By effect set (with the Hessian): 33 to 2,511 for the two degree effects, 43 to 3,129 for the four
degree effects, 616 to 1,856 with the inertia effects added, 50 to 249 with the recency effects ({bf:rsndsnd rrecsnd}; the
smallest ratios) and 68 to 4,130 with the covariate effects. {cmd:nwrem} needed 0.006 seconds for the two-effect model at
200 events and 20 actors, 0.02 seconds at 5,000 events and 50 actors, and 0.16 seconds at 20,000 events and 100 actors;
the largest fits were 20,000 events and 100 actors with the inertia effects (12 seconds, median of 7 fits) and with the
recency effects (7.8 seconds). With 20,000 events {cmd:relevent} did not finish within 600 seconds with the Hessian
for the four degree effects, the recency effects and the covariate effects (ratios above 2,600, 77 and 1,700);
without the Hessian it needed 575 seconds for the four degree effects and 588 seconds for the recency effects (ratios
2,544 and 75) and again more than 600 seconds with the covariate effects. With the inertia effects {cmd:relevent}
did not finish within 600 seconds at 5,000 events and 50 actors ({cmd:nwrem}: 0.7 seconds, ratio above 880) and was
not run for the larger models. The peak memory of the Stata process was 0.21 GB with 200 events, 0.25 GB with 5,000 events
and 50 actors and 0.29 GB with 20,000 events and 100 actors; the memory of {cmd:relevent} was not measured. The
coefficients of the two programs agree to about three significant digits, not to six (largest absolute difference
0.005, for coefficients of about 10 to 50; at most 0.007 standard errors of {cmd:relevent}); {cmd:relevent} stops at its
own convergence tolerance, {cmd:nwrem} at the maximum of the likelihood. Timings depend on the machine, the data and the
effects, and the times of {cmd:relevent} come from a different day than those of {cmd:nwrem}.

{pstd}
{bf:Direction}: the model is always fitted for directed events, the first variable of {help nwset}
being the sender and the second the receiver, and the risk set holds all {it:n}({it:n}-1) ordered
pairs. A network declared {opt undirected} is fitted in the same way and gives the same results as
the directed declaration; this follows {cmd:relevent::rem.dyad()}, which has no undirected variant.

{pstd}
{bf:Event data}: every event must have a time, a sender and a receiver that are actors of the
network, and a sender different from the receiver. Events without a time or with a missing actor
are refused (error 416), and so are self-loops (error 3498); drop such rows before {help nwset}.
Two-mode event networks are refused (error 198).

{pstd}
{cmd:nwrem} fits any combination of the effects above (at least one required). There is
deliberately no intercept option - a term constant across every candidate pair at a given event
cancels out exactly in the ordinal likelihood's own normalization (the same reason Cox
proportional-hazards models have no identifiable baseline intercept), and {cmd:relevent} has none
in its waiting-time model either, so one is never estimable here regardless of what is requested.
Not implemented: Bayesian simulation (MCMC and sampling importance resampling), sampling of the risk set,
simulation of event sequences, goodness-of-fit residuals and covariates that change over time.

{pstd}
{bf:Waiting-time likelihood.} With {opt interval} the model is the full continuous-time model of Butts (2008): the
rate of the pair (sender,receiver) is {it:exp}(the linear predictor), the contribution of an event is the log rate minus
the length of the interval since the previous event times the sum of the rates over the risk set, and the time from the last
event to {opt endtime()} contributes the corresponding survival term. The first interval starts at {opt starttime()}. Events must
have strictly increasing times; ties are refused (error 459), as {cmd:relevent} refuses them. With {opt condition(#)}
the first events only build the history; for the waiting-time likelihood the interval after the last of them is the
first one that counts.

{pstd}
{bf:Risk sets.} By default every ordered pair of actors can be an event at every time. {opt riskset()} restricts the pairs
that can occur at all (for example, only pairs within the same department), {opt entry()} and {opt exit()} restrict the actors
that are present. An actor is present at an event whose time lies between its entry and its exit time (both ends included).
An event of a pair that is not in the risk set is an error (459). The statistics of the effects (degrees, counts, shares,
recency) are computed from all events as before; only the pairs over which the likelihood normalises are restricted.

{pstd}
{bf:Triadic effects.} {bf:otpsnd}, {bf:itpsnd} and {bf:ispsnd} are the statistics of {cmd:relevent}. {bf:ospsnd} is the intended
symmetric statistic (for the sender {it:a} and the receiver {it:b}, the sum over all actors {it:l} of the smaller of the
numbers of past events {it:a} to {it:l} and {it:b} to {it:l}). The statistic of {cmd:relevent} 1.2-1 is not symmetric: for a
pair of actors it counts twice for one direction and not at all for the other, depending on the order in which the actors first
appear as senders; its estimates therefore differ from those of {bf:ospsnd}.

{pstd}
{bf:Fixed effects.} {bf:fesnd}, {bf:ferec} and {bf:feint} add one coefficient per actor minus one (the first actor, in the
order of the network, is the reference). Because they are evaluated for every pair at every event, they are slower for large
networks; models with more than about 600 fixed-effect coefficients are refused.

{pstd}
{bf:Posterior mode.} {opt postmode} maximises the log likelihood plus the log density of independent Student t priors
(centre {opt priormean()}, scale {opt priorscale()}, {opt priordf()} degrees of freedom), as {cmd:relevent}'s {cmd:fit.method="BPM"};
the reported standard errors are those of the curvature of the posterior at the mode, and {cmd:e(ll)} is the log likelihood
without the prior. With the defaults the prior is very weak.

{pstd}
{bf:rsndsnd}/{bf:rrecsnd} are different from {bf:frpsndsnd}/{bf:frrecsnd}: the latter measure HOW
OFTEN a sender has contacted a given partner relative to their total activity (a fraction);
{bf:rsndsnd}/{bf:rrecsnd} measure HOW RECENTLY, via reciprocal RANK among that sender's own past
contacts, ignoring how many times contact happened before or since. A sender who contacted a
partner once, very recently, scores as high on {bf:rsndsnd} for that partner as one who contacted
them constantly and most recently - only the ordering matters, not the count.

{pstd}
{bf:Covariate effects} are read from the current Stata dataset at the time {cmd:nwrem} is called - NOT
the event-level dataset {it:netname} itself was declared from. When the dataset has the node-label
variable {bf:_nwnode} (as after {help nwload}'s {opt xvars} option), each actor of {it:netname} is
matched to its row by label, whatever the sort order of the data; every actor must have exactly
one row. Without {bf:_nwnode} the dataset must have exactly one row per actor, in {it:netname}'s
own actor order. A missing covariate value is refused (error 416). Use {help nwload}'s {opt xvars}
option first to load the per-node dataset:

	{cmd:. nwload mynet, xvars}
	{cmd:. gen seniority = ...}
	{cmd:. nwrem mynet, nodsnd covsnd(seniority)}

{pstd}
The coefficient of a covariate effect is named after the effect and the variable ({bf:covsnd_}{it:varname});
names longer than 32 characters are cut to 32.

{pstd}
{bf:covevent()} is different: it is a per-{it:pair} (not per-actor) covariate, so it is read
from ANOTHER already-loaded network's own tie values rather than from a Stata variable - the same
convention {help nwergm}'s {opt edgecov()} already uses for dyadic covariates. Declare the
pairwise covariate as its own network first, then reference it by name - {bf:nwset}'s
{opt edgelist} option is required here ({cmd:nwset} otherwise reads three bare variables as a
wide affiliation matrix, not an edgelist):

	{cmd:. nwset i j value, name(seatdist) edgelist}
	{cmd:. nwrem mynet, nodsnd covevent(seatdist)}

{pstd}
{cmd:covevent(seatdist)} must have the same actors as {cmd:mynet}; its tie value for the ordered
pair (sender,receiver) enters the sending rate directly for that pair (no ego/alter broadcasting,
unlike {opt covsnd()}/{opt covrec()}/{opt covint()}). Because the effect reads (sender,receiver)
values directly, {bf:nwset does not auto-symmetrize} an edgelist declaration: an ordered pair with
no explicit row gets value 0, even if its reverse pair {it:was} given a value. For a covariate
that is genuinely symmetric (e.g. physical distance), supply BOTH ordered pairs (i,j) and (j,i)
explicitly; for one that is genuinely directional (e.g. "i reports to j"), that asymmetry is
exactly what {bf:covevent()} is for.

{pstd}
{bf:A note on precision}: {cmd:nodsnd}/{cmd:nidrec}/{cmd:nidsnd}/{cmd:nodrec}/{cmd:ntdegsnd}/
{cmd:ntdegrec} are each a running average - the fraction of {it:all prior events} in which an
actor sent/received - and that fraction's cross-actor spread narrows as the event sequence grows
(it converges toward 1/{it:n} for every actor). This means, unlike an ordinary regression
covariate, point estimates from these effects can remain noisy even with several thousand events,
a genuine property of the effects themselves (verified against a real reference
relational-event-model implementation on identical data, not a limitation of this command).
Combining several of these degree-type effects in the same model (e.g. {cmd:nodsnd} with
{cmd:nidsnd} and {cmd:ntdegsnd} together) can also produce a nearly flat ridge in the likelihood
surface along some combination of their coefficients - different starting values can then
converge to visibly different individual coefficients while fitting the data almost equally
well; check whether the overall model fit (log likelihood) is what actually matters for your
question before over-interpreting any single coefficient in that situation. An effect that is
an exact function of the effects before it in the model (the sender and receiver effects and
{cmd:covsnd()}, {cmd:covrec()}, {cmd:covint()}, {cmd:covevent()} and all other effects are examined; for example
{cmd:ntdegsnd} with {cmd:nodsnd} and {cmd:nidsnd}, or any of {bf:frpsndsnd}, {bf:rsndsnd} and the fixed effects in a very small network)
cannot change the likelihood: {cmd:nwrem} leaves it out of the
estimation, reports its coefficient as 0 without a standard error and lists it in {bf:e(unidentified)}. The fitted model
reliably improves on the no-effect baseline even when a single point estimate is imprecise;
interpret standard errors accordingly and prefer larger event counts where possible.


{pstd}
{marker native}{...}
{pstd}
Every fit runs in the compiled plugin of the package ({cmd:rem_sim}): the log likelihood, the gradient and the exact
Hessian of all effects are evaluated natively, and Mata maximises the likelihood with Newton-Raphson steps on them.
There is no slower fallback. If the plugin file of your platform is not installed, {cmd:nwrem} stops with return code 601
and says which file is missing; if the installed plugin is older than the {cmd:.ado} files (or cannot be loaded), it stops
with return code 3495. Reinstall the package with {bf:net install nwrem, replace} (and restart Stata) in both cases.

{pstd}
If the Mata library of nwrem (lnwrem.mlib) does not load in your Stata (for example r(3499) because it was built by a newer Stata than yours), build it with your own Stata:
{cmd:nwinstall, buildmata(nwrem)} fetches the Mata source, compiles it and installs the library; restart Stata afterwards.
The build clears the data and the Mata objects in memory. See {help nwinstall##buildmata:nwinstall}.

{pstd}
The C source of the plugin comes with the package: {cmd:net get nwrem, from(https://raw.githubusercontent.com/thomas-u-grund/nwrem/main)}
copies it into the current directory, together with a file that explains how to build the plugin; it is also in the folder
{cmd:native/} of the repository at {browse "https://github.com/thomas-u-grund/nwrem"}. {cmd:net install} installs the compiled plugins only.


{title:Examples}

{pstd}Fit a relational event model on a small event log:{p_end}

	{cmd:. clear}
	{cmd:. input sender receiver t}
	{cmd:. 1 2 1}
	{cmd:. 1 3 2}
	{cmd:. 2 1 3}
	{cmd:. 1 2 4}
	{cmd:. 3 2 5}
	{cmd:. 2 3 6}
	{cmd:. 1 3 7}
	{cmd:. 3 1 8}
	{cmd:. 2 1 9}
	{cmd:. 1 3 10}
	{cmd:. end}
	{cmd:. nwset sender receiver, eventtime(t) name(chat)}
	{cmd:. nwrem chat, nodsnd nidrec}

{pstd}
(a handful of events on very few actors, as above, has too little information to pin down either
coefficient precisely - the wide confidence intervals in this toy example are expected, not a
sign of a problem; see this help file's own note on precision above){p_end}

{pstd}Add an inertia effect (does a sender tend to keep sending to the same recent partner) alongside a degree effect:{p_end}

	{cmd:. nwrem chat, nidrec frpsndsnd}

{pstd}Add an actor-attribute covariate effect - does a per-actor variable affect the sending rate:{p_end}

	{cmd:. nwload chat, xvars}
	{cmd:. gen seniority = _n}
	{cmd:. nwrem chat, nodsnd covsnd(seniority)}

{pstd}Add a pairwise covariate effect - does a variable specific to the (sender,receiver) pair
itself, not to either actor alone, affect the sending rate (seat distance is symmetric, so both
ordered pairs are given explicitly - see the note on symmetry above):{p_end}

	{cmd:. clear}
	{cmd:. input i j value}
	{cmd:. 1 2 5}
	{cmd:. 2 1 5}
	{cmd:. 1 3 2}
	{cmd:. 3 1 2}
	{cmd:. 2 3 8}
	{cmd:. 3 2 8}
	{cmd:. end}
	{cmd:. nwset i j value, name(seatdist) edgelist}
	{cmd:. nwrem chat, nodsnd covevent(seatdist)}

{pstd}Add a triadic effect (do the partners of my partners become my partners?), and the fixed effects of the senders:{p_end}

	{cmd:. nwrem chat, nodsnd otpsnd}
	{cmd:. nwrem chat, fesnd}

{pstd}Use the times between the events (the waiting-time likelihood), conditioning on the first five events, with the end of the
observation at time 12:{p_end}

	{cmd:. nwrem chat, nodsnd nidrec interval endtime(12) condition(5)}

{pstd}Allow only some pairs to be events, here the pairs given by the ties of a network {cmd:allowed}; {opt entry()} and {opt exit()} name per-actor variables with the times at which an actor joins and leaves:{p_end}

	{cmd:. nwrem chat, nodsnd riskset(allowed)}

{pstd}A posterior mode with a normal prior of scale 2 around 0:{p_end}

	{cmd:. nwrem chat, nodsnd nidrec postmode priordf(.) priorscale(2)}

{pstd}Add a recency effect - does a sender tend to return to whoever they contacted most recently,
regardless of how often (contrast with {cmd:frpsndsnd} above, which is about frequency):{p_end}

	{cmd:. nwrem chat, nodsnd rsndsnd}


{title:Stored results}

{synoptset 20 tabbed}{...}
{p2col 5 20 24 2: Scalars}{p_end}
{synopt:{bf:e(N)}}number of events{p_end}
{synopt:{bf:e(nodes)}}number of actors{p_end}
{synopt:{bf:e(ll)}}log likelihood at the estimates (without the prior with {opt postmode}){p_end}
{synopt:{bf:e(ll_0)}}log likelihood of the model without effects (ordinal likelihood; with {opt interval} the model of a constant rate over the complete risk set){p_end}
{synopt:{bf:e(df_m)}}number of estimated coefficients{p_end}
{synopt:{bf:e(deviance)}}{bf:-2*e(ll)}{p_end}
{synopt:{bf:e(aic)}, {bf:e(aicc)}, {bf:e(bic)}}information criteria{p_end}
{synopt:{bf:e(N_cond)}}number of events that only build the history ({opt condition()}){p_end}
{synopt:{bf:e(starttime)}, {bf:e(endtime)}}observation window with {opt interval}{p_end}
{synopt:{bf:e(priormean)}, {bf:e(priorscale)}, {bf:e(priordf)}}the prior with {opt postmode}{p_end}

{p2col 5 20 24 2: Macros}{p_end}
{synopt:{bf:e(cmd)}}{bf:nwrem}{p_end}
{synopt:{bf:e(version)}}release of {cmd:nwrem} that produced the results{p_end}
{synopt:{bf:e(title)}}"Relational event model (" likelihood and estimator ")"{p_end}
{synopt:{bf:e(lik)}}{bf:ordinal} or {bf:interval}{p_end}
{synopt:{bf:e(depvar)}}name of the event network fit{p_end}
{synopt:{bf:e(unidentified)}}effects without a usable standard error (left out because they are exactly collinear with others: coefficient 0; or a standard error above 100); empty when all are identified{p_end}

{p2col 5 20 24 2: Matrices}{p_end}
{synopt:{bf:e(b)}}coefficient vector{p_end}
{synopt:{bf:e(V)}}variance-covariance matrix (observed information){p_end}


{title:Version}

{p 8 17 2}
{cmd:nwrem version}
{p_end}

{pstd}
{cmd:nwrem version} displays the installed release of {cmd:nwrem}, the version of the {cmd:nwcommands} core, the license and the version of the R package that the results were compared with. It stores
the release in {cmd:r(version)} and {cmd:r(date)}, the core version in {cmd:r(core)}, the native plugin in use in {cmd:r(plugin)},
the R package it was compared with in {cmd:r(reference)}, and the license in {cmd:r(license)}. After estimation, the release that produced the results is in
{cmd:e(version)}; quote it when reporting an analysis. {cmd:nwversion} lists the core and all installed model packages.
{p_end}


{title:Also see}

{p 4 14 2}Help: {help nwset}, {help nwattime}, {help nwergm}, {help nwsaom}{p_end}

{hline}
{pstd}{it:nwrem version 1.4.0, 16 November 2026}{p_end}{* nwversion}
