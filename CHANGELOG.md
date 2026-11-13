# Changelog

All notable changes to nwrem are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the
project uses [Semantic Versioning](https://semver.org/).

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
