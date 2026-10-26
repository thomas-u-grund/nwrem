# Changelog

All notable changes to nwrem are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the
project uses [Semantic Versioning](https://semver.org/).

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
