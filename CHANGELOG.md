# Changelog

All notable changes to nwrem are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the
project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Changed
- Coefficient tables show the coefficient names in full by default: the confidence intervals are left out, as with `noci`, at a `linesize` below 100 (where names of up to 32 characters do not fit next to them); before, long names were cut (e.g. `covevent_sa~p`). The new option `ci`, or `level(#)` given explicitly, shows the intervals as before. The display options of Stata's estimation commands (`noci`, `nopvalues`, `cformat()`, `pformat()`, `sformat()` and the others of `ereturn display`) are accepted in fits and in the replay (`nwrem` alone, `estimates replay`). Tables whose names all fit, and all output outside the coefficient tables, are unchanged.

## [1.4.0] - 2026-11-16

### Added
- **Waiting-time (interval) likelihood**, `interval`, with `starttime()` and `endtime()` (the last interval, from the last event to the end of the observation, enters as a survival term). Event times must be strictly increasing (ties: r(459), as in relevent). Together with `condition(#)` (the first events only build the history, for both likelihoods).
- **Triadic and shared-partner effects** `otpsnd`, `itpsnd`, `ospsnd`, `ispsnd`; **fixed effects** `fesnd`, `ferec`, `feint` (one coefficient per actor except the first); **participation shifts** `psabba`, `psabby`, `psabxa`, `psabxb`, `psabxy`, `psabay` (the six of the 13 shifts of relevent that are not always zero). All are evaluated in the plugin. `ospsnd` is the intended symmetric statistic; relevent 1.2-1 counts shared out-partners for one direction of a pair twice and for the other direction not at all, so its estimates for this effect differ (documented in `help nwrem`).
- **Risk sets**: `riskset(netname)` (ties of 0 are pairs that can never be an event), `entry(varname)` and `exit(varname)` (per-actor windows). An event outside the risk set is an error (r(459)).
- **Posterior mode**, `postmode` with `priormean()`, `priorscale()`, `priordf()` (independent Student t priors, as relevent's `fit.method="BPM"`; `priordf(.)` is a normal prior).
- **Several covariates per option**: `covsnd(varlist)`, `covrec(varlist)`, `covint(varlist)`, `covevent(netlist)`; coefficients `covsnd_<variable>`, `covevent_<network>`.
- New stored results `e(ll_0)`, `e(df_m)`, `e(deviance)`, `e(aic)`, `e(aicc)`, `e(bic)`, `e(N_cond)`, `e(lik)`, `e(starttime)`, `e(endtime)`, `e(priormean)`, `e(priorscale)`, `e(priordf)`.
- New tests: `test_nwrem_relevent14` (60 event logs and models against reference values computed with relevent 1.2-1: the exact maximum from `rem()` on the statistics of relevent, 1e-5 in coefficients and standard errors and 1e-9 in the log likelihood, and `rem.dyad()` itself where it can fit the model, 2e-4; `dev/rem_relevent14_gen.R` makes `cscripts/ref14/`), `test_nwrem_collinear14` (the omitted coefficients of 39 tiny networks, found from relevent's statistics), `test_nwrem_options14` (error paths, stored results, identities).

### Changed
- **Collinearity check for all effects.** The check for effects that are exact functions of others now also examines `frpsndsnd`, `frrecsnd`, `rsndsnd` and `rrecsnd` and the new effects; before, those four were never omitted.
- **Fewer plugin evaluations.** The evaluation at theta = 0 of the collinearity check serves as the null model and as the first Newton step: two likelihood evaluations fewer per fit. The row-wise sum over the sparse dyads of the evaluator was restructured. At 20,000 events and 100 actors (simulated, same machine and data, Stata 17, one fit run alone; version 1.3.0 before, 1.4.0 after): `nodsnd nidrec` 0.19 s, 0.20 s; plus `frpsndsnd` 4.5 s, 3.0 s; plus `rsndsnd` 4.5 s, 3.0 s; four degree effects plus `frpsndsnd frrecsnd` 17.5 s, 11.4 s; four degree effects plus `rsndsnd rrecsnd` 17.5 s, 11.5 s; plus a dense `covevent()` network (a third of the dyads) 3.2 s, 1.9 s. The cost per dyad of the state-dependent effects is about the same as before (6 to 7 ns per dyad and event with four degree and two state-dependent effects); the gain is the saved evaluations. Results for all earlier models are unchanged to round-off.
- Plugin protocol 2: a plugin of version 1.3.0 is refused (r(3495)). The coefficients of dependent state-dependent effects that were previously estimated along a flat ridge are now 0 (omitted).
- `nwrem` has no `covsnd()` error 103 for more than one variable any more (several variables are allowed).

### Not implemented
Bayesian simulation (`fit.method` MCMC and BSIR: random output that cannot be validated against R's random numbers), `sample.size` (sampling of the risk set), `simulate`, goodness-of-fit residuals and covariates that change over time (they need an event-wise data structure).

Tested on macOS with Stata 17 BE, Stata 18 BE and StataNow 19.5 MP (the full test suite; 60 random event logs compared with relevent). Windows and Linux: not yet tested; the plugins are built by the build workflow, and until they are rebuilt those platforms stop with return code 3495.

## [1.3.0] - 2026-11-16

### Changed
- **Every fit runs in a native plugin.** The likelihood, its gradient and its exact Hessian are evaluated by the compiled plugin `rem_sim` (macOS, Linux, Windows; C source in `native/`, built by `.github/workflows/build-plugins.yml`). There is no Mata fall-back: when the plugin file of the platform is missing the command stops with r(601), when the installed plugin does not speak the protocol of this version (or cannot be loaded) with r(3495); both with a message. All 14 effects, `covevent()` networks (valued; missing or non-zero diagonal read as before), tied event times and repeated dyads are handled natively. The normaliser of an event costs O(n) plus the number of dyads that are in contact so far (or have a non-zero `covevent()` cell): the sparse dyadic terms (`frpsndsnd`, `frrecsnd`, `rsndsnd`, `rrecsnd`, `covevent()`) are kept as a list that is updated at the rows of the sender and the receiver after each event. When exp() overflows, a normaliser underflows or the sparse correction cancels more than six digits, the plugin evaluates that likelihood densely (O(n^2) per event) instead.
- **Newton-Raphson on the exact Hessian.** The model is maximised with damped Newton steps on the plugin's gradient and Hessian (Mata's `optimize()` with a BFGS multi-start and Nelder-Mead stay as fall-backs when no maximum is reached). Coefficients and standard errors are those of the exact maximum and the exact observed information; values of earlier versions, which stopped where BFGS met its default tolerances with a numerical Hessian, differ in the fourth to fifth digit (for example nodsnd 10.6498 instead of 10.6488 at `t < 5`). `seed()` now matters only for the random starts of the fall-backs.
- **Speed.** Measured on the manufacturing e-mails, `t < 14` (2,738 events, 129 actors), Apple M5 Pro, Stata 17 (version 1.2.0 before, 1.3.0 after): `nodsnd nidrec` 0.76 s, 0.03 s; plus `frpsndsnd` 4.6 s, 0.27 s; plus `rsndsnd` 9.9 s, 0.18 s; plus `covevent()` 1.4 s, 0.14 s; plus `frrecsnd rrecsnd` 9.5 s, 0.22 s. At 20,000 events and 100 actors: `nodsnd nidrec` 3.7 s, 0.16 s; plus `frpsndsnd` 25 s, 5.1 s; plus `rsndsnd` 46 s, 4.5 s; four degree plus `frpsndsnd frrecsnd` 46 s, 12 s; plus `covsnd covrec covint` 13 s, 0.33 s; plus a dense `covevent()` network (a third of the dyads) 6.8 s, 7.0 s (about as fast as before). The timings against R's `relevent` in `help nwrem` and `README.md` are those of this version.
- **Mata evaluators are reference code.** The dense and the fast Mata evaluators of version 1.2.0, the dependence check and the unit-1 fit moved from `unw_rem.do` to `cscripts/ref_rem_mata.do`; the package's Mata library holds only the glue (event sorting, plugin lookup, the Newton loop, the collinearity check). The check for exactly dependent effects (version 1.2.0) is done by the plugin at theta = 0 and gives the same result.
- `nwrem version` reports the plugin file in use in `r(plugin)`; the files of the plugin are listed in `nwrem.pkg`.

### Added
- New tests: `test_nwrem_plugin` (plugin against the Mata reference: every effect, every pair, random subsets, all 16,383 subsets of a small system, tied times, repeated dyads, valued `covevent()`, n = 2 and n = 3, extreme coefficients with the dense evaluator taking over, the Hessian against the numerical derivative of the reference gradient, the dependence check), `test_nwrem_noplugin` (r(601), r(3495), no frame left behind) and `test_nwrem_oldplugin` (a plugin with another protocol number is refused). `cscripts/run_tests.sh` sets a clean PLUS and runs the `xt_rem_*` tests as well. `test_nwrem_fast` now holds only the fits of the manufacturing e-mails.

Tested on macOS with Stata 17 BE, Stata 18 BE and StataNow 19.5 MP (the full test suite). Windows and Linux: not yet tested; the plugins are built by the build workflow.

## [1.2.0] - 2026-11-15

### Changed
- **Fits are much faster.** The likelihood and its gradient are no longer computed from an n x n softmax per event. The log-rate of a dyad is a sum of a sender term, a receiver term and (for `frpsndsnd`, `frrecsnd`, `covevent()`, `rsndsnd`, `rrecsnd`) a dyadic term; the normaliser of every risk set follows from sums over senders and receivers, for all events at once, and the dyadic terms are updated only at the rows of the sender and the receiver after each event. Measured on the manufacturing e-mails, `t < 14` (2,738 events, 129 actors), Apple M5 Pro, Stata 17: `nodsnd nidrec` 20.3 s before, 0.9 s now; plus `frpsndsnd` 38.9 s, 7.5 s; plus `rsndsnd` 61.2 s, 10.7 s; plus `covevent()` 35.4 s, 1.3 s; plus `frpsndsnd` and `covevent()` 67.6 s, 12.2 s; `nodsnd nidsnd ntdegsnd` 280 s, 0.5 s (collinear effects, see below). The models with state-dependent dyadic effects gain a factor of about 5, the others a factor of 24 to 27. 50,000 events and 170 actors need less than 1 second per likelihood evaluation for the sender, receiver and covariate effects (peak memory about 620 MB with all event data held) and about 5 seconds with `frpsndsnd` and `rsndsnd`.
- **Same estimates.** The new evaluator returns the likelihood and gradient of the previous one to about 1e-12 (relative), the coefficients of the fits above agree to about 1e-11 and the standard errors to about 1e-9. A fit that the fast evaluator cannot do safely (a missing or underflowing normaliser, an overflowing `exp()` at an extreme coefficient, a state too large for its matrices) falls back to the previous evaluator for that evaluation.
- **Collinear effects are found before the optimizer runs.** An effect that is an exact linear function of the effects before it (plus a term that is constant over every risk set), for example `ntdegsnd` together with `nodsnd` and `nidsnd`, or `covint()` together with `covsnd()` and `covrec()` of one variable, is left out of the estimation: its coefficient is 0, its variance 0, it is listed in `e(unidentified)` and the same note is printed as before. The remaining coefficients and the log likelihood are those of the model without it. The previous version ran the optimizer on the flat ridge (about 500 likelihood evaluations, 5 minutes for `nodsnd nidsnd ntdegsnd` at `t < 14`). The state-dependent dyadic effects (`frpsndsnd`, `frrecsnd`, `rsndsnd`, `rrecsnd`) are not examined.
- A `covevent()` network with a missing or non-zero diagonal is read as before (the diagonal is not part of the risk set).
- New test `test_nwrem_fast` (fast against dense evaluator for every effect, every pair, random subsets and all 16,383 subsets of a small system, with tied event times, repeated dyads and valued dyadic covariates, in one block and in small blocks of events; extreme coefficients and the fall-back; the dependence check; fits of the manufacturing e-mails against values of the previous evaluator).

Tested on macOS with Stata 17 BE, Stata 18 BE and StataNow 19.5 MP (the full test suite) and on Linux (Ubuntu 22.04) with StataNow 19.5 MP. Windows: not yet tested in Stata.

## [1.1.2] - 2026-11-13

### Changed
- Rebuilt for nwcommands 3.24.0; requires core 3.24.0 or later. No other change.

Tested on macOS with Stata 17 BE, Stata 18 BE and StataNow 19.5 MP (the full test suite), on Windows 11 with StataNow 19.5 MP and on Linux (Ubuntu 22.04) with StataNow 19.5 MP.

## [1.1.1] - 2026-11-13

### Changed
- **Help:** `covsnd()`, `covrec()` and `covint()` are described as numeric covariates (a string variable was already refused with r(109)). nwrem has no effect that compares categories, so it does not take string variables.
- **Help: directed and undirected declarations.** The help says that `nwrem` takes the plain directed `nwset ..., eventtime()` declaration (an undirected declaration is not required), that every event is read as directed from the first variable (sender) to the second (receiver) whatever the declaration says, and that `undirected` changes only the network summary built by `nwset`, not the estimates. New test `test_nwrem_direction`.

### Changed
- Rebuilt for nwcommands 3.23.0; requires core 3.23.0 or later.

Tested on macOS with Stata 17 BE, Stata 18 BE and StataNow 19.5 MP (the full test suite), on Windows 11 with StataNow 19.5 MP and on Linux (Ubuntu 22.04) with StataNow 19.5 MP.

## [1.1.0] - 2026-11-13

### Results that change (read before you re-run old analyses)
- Covariate effects on a dataset whose rows are not in actor order but carry `_nwnode`: the covariate is now matched to the right actors.

### Fixed
- Per-actor covariates (`covsnd()`, `covrec()`, `covint()`) are matched to the actors by their node labels (variable `_nwnode`, as after `nwload, xvars`) instead of by row position; a re-sorted dataset no longer misaligns them. Without `_nwnode` the data must still have one row per actor in actor order. An actor without a row, or with more than one, is refused (r(198)).
- A missing covariate value is refused with a clear message (r(416)); before, the fit failed with r(111) after many "initial values not feasible" lines.
- Events with a missing time, or with a sender or receiver that is not an actor of the network (for example a missing id), are refused (r(416)); before, an event without a time was silently used as the last event and a missing id gave a raw Mata error.
- A self-loop event gives its message and r(3498); the message was lost (Mata r(3300)) because it was too long for Mata's `_error()`.
- Covariate names longer than 25 characters no longer fail (r(198)): coefficient names longer than 32 characters are cut to 32.
- `seed()` accepts integers from 0 to 2147483647 only; `seed(-1)` used to be ignored silently.
- `nwrem` without arguments (or with `level()` only) redisplays the last fit, and `estimates replay` works; new option `level()`.
- Help: an undirected event network is fitted as directed, like relevent's `rem.dyad()`, which has no undirected variant; the event-data rules and the covariate matching are documented.

### Changed
- Rebuilt for nwcommands 3.22.0; requires core 3.22.0 or later.

Mata library `lnwrem.mlib` rebuilt with Stata 17 (new function `rem_node_rows()`, self-loop message).

Tested on macOS with Stata 17 BE, Stata 18 BE and StataNow 19.5 MP (the full test suite) and on Windows 11 with StataNow 19.5 MP. Linux: not tested in Stata.

## [1.0.13] - 2026-11-12

### Fixed
- The note after a fit with effects that have no usable standard error said that the total-degree share `ntdegsnd` is the sum of `nodsnd` and `nidsnd`; it is half the sum (the average of the two shares, as in relevent's `NTDegSnd`). The statistic itself is unchanged.

## [1.0.12] - 2026-11-12

### Fixed
- **Help file checked against the code.** `seed()` makes the fit reproducible (all starting values are random); stored results completed.
- **Help file layout.** Stored results wrap at the window width; very long source lines are broken up.
- The help file lists the effects that are not implemented in plain words.

Results do not change.

## [1.0.11] - 2026-11-11

Patch release. No change of the Mata library or the estimators.

### Fixed
- **Long notes, warnings and messages wrap at word boundaries instead of being cut in the middle of a word.** Stata breaks a displayed line that is longer than the line size at exactly that column (for example in the error "nwrem requires a network declared via nwset's eventtime() option ..." and the note on effects that are not identified); these messages are now SMCL paragraphs, which wrap between words. The wording is unchanged. Results do not change. Tested in `cscripts/test_nwrem_msgwrap.do` at line size 80.

### Added
- Documentation of `nwinstall, buildmata(nwrem)` (nwcommands 3.14 and later): a Mata library that does not load in the user's Stata (built by a newer Stata, r(3499)) is rebuilt from the source in this repository with the Stata that runs. README and help file describe it. No change of the Mata library, the plugin or the estimators.

## [1.0.10] - 2026-10-26

Patch release. Works with nwcommands 3.6.0 and later; no change of the Mata library.

### Changed
- Help text corrected: speed claim re-timed. The earlier statement that nwrem is 2 to 12 times faster than relevent rested on old timings of two models; it is replaced by timings of 26 October 2026 for five effect sets at 200 to 20,000 events (relevent/nwrem time ratio 0.75 to 36; nwrem is slower for recency effects at up to 1,000 events). README: new Speed section. No change in code or results.

## [1.0.9] - 2026-10-26

Patch release. Works with nwcommands 3.6.0 and later; no change of the Mata library.

### Changed
- Help text corrected: references to development scripts and to an internal roadmap removed from the help; the AI-assistance paragraph of NOTICE.md no longer mentions C (the package has no plugin); the README install lines start with nwinstall. No change in code or results; the Mata library is unchanged.

## [1.0.8] - 2026-10-26

Patch release. Works with nwcommands 3.6.0 and later; no change of the Mata library.

### Fixed
- `covevent()` with a two-mode network (missing cells between nodes of the same mode) ended in repeated "initial values not feasible" messages; it is now refused with the common message and error 6088. A covariate network with missing tie values stops with error 416.
- The error message of `nwrem` without an effect no longer refers to internal development notes.

## [1.0.7] - 2026-10-26

### Changed
- Rebuilt for nwcommands (core) 3.6.0: the Mata library is compiled against the core library of 3.6.0 (built with Stata 17) and the package needs nwcommands 3.6.0 or later. No change in results.
- Install lines and the README: `nwinstall, everything` installs the core and the four model packages in one step. Supported Stata versions: 17 or later, tested with Stata 17 and 18.

## [1.0.6] - 2026-10-25

### Fixed
- The Mata library was built with Stata 18 and could not be used in Stata 17; it is now built with Stata 17 (works in Stata 17 and 18). Needs nwcommands 3.5.1 or later.

### Changed
- Requirements stated plainly: Stata 17 or later; tested with Stata 17 and Stata 18.


## [1.0.5] - 2026-10-25

### Results that change (read before you re-run old fits)
- Events with the same time keep the order in which they stand in the network. Earlier versions ordered tied events by chance (it depended on the random-number generator), so estimates for data with tied event times change and now repeat exactly. Data without tied times are unchanged.

### Fixed
- Events with the same time (ties) keep the order in which the network lists them. Before, they were sorted with a tie order that depended on the state of the random-number generator, so the same data could give a different likelihood and slightly (or, with many ties, strongly) different estimates from run to run. Data without tied times were not affected.

## [1.0.4] - 2026-10-25

### Changed
- Rebuilt for nwcommands 3.4.0; requires core 3.4.0 or later.
- A fit with effects that are not identified (an exactly collinear effect such as `ntdegsnd` together with `nodsnd` and `nidsnd`, or a standard error above 100) now prints a note under the table and returns the effect names in `e(unidentified)`. Before, the table showed a missing standard error without a warning.

## [1.0.3] - 2026-10-25

### Fixed
- Works right after a fresh install: the Mata library is indexed automatically. Before, the first call in a new Stata session could stop with r(3499) "... not found" (or, for nwergm, "class ErgmGraph undefined") until `mata mlib index` was run by hand.

## [1.0.2] - 2026-10-25

### Changed
- The version is shown at the bottom of each help file.

## [1.0.1] - 2026-10-24

### Changed
- The help file documents the `nwrem version` subcommand and the stored results `r(version)`, `r(date)`, `r(core)`, `r(license)` and `e(version)`.

## [1.0.0] - 2026-10-24

First release of nwrem as a package of its own.

### Added
- Relational event models (Butts 2008) for event-time networks declared with `nwset ..., eventtime()`, estimated by (partial) likelihood.
- Degree effects (sender and receiver activity, total-degree effects), inertia (repeated and reciprocal events: FRP effects), recency effects, sender/receiver/interaction covariate effects and event-level covariates.
- `nwrem version`: package and core versions; `e(version)` in the results.
- Compared with and validated against R relevent 1.2-1 (`rem.dyad`).
