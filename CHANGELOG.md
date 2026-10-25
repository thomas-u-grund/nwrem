# Changelog

All notable changes to nwrem are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the
project uses [Semantic Versioning](https://semver.org/).

## [1.0.3] - not yet released

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
