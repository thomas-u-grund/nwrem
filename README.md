# nwrem

<!--version-->**Version 1.0.10** (released 26 October 2026)<!--/version-->

`nwrem` fits relational event models (REM) to a sequence of timed events between actors (who sends to whom, when), declared as an event-type temporal network with `nwset ..., eventtime()`. It estimates degree, inertia, recency and covariate effects by (partial) likelihood.

Part of the nwcommands family of Stata packages for network analysis. nwrem is a separate package with its
own repository; it needs the core package nwcommands but no other model package.

## Install

1. Install the core package first (Stata): `net install nwcommands, from(https://nwcommands.org/net/) replace`
   (alternative: `from(https://raw.githubusercontent.com/thomas-u-grund/nwcommands/main/)`). Required: nwcommands (core), version 3.6.0 or later.
2. Install this package from the core: `nwinstall, modelpkg(nwrem)`.
   `nwinstall, everything` installs the core and all four model packages in one step; `nwinstall, all` installs the core only and `nwinstall, models` adds the model packages to it.

`nwinstall` installs the latest release (the state of the main branch). Without `nwinstall`, the package can be installed directly from GitHub:

       net install nwrem, from(https://raw.githubusercontent.com/thomas-u-grund/nwrem/main/) replace

To install a specific version, point `from()` at the release tag (GitHub serves every tag under its own raw URL), for example version 1.0.8:

       net install nwrem, from(https://raw.githubusercontent.com/thomas-u-grund/nwrem/v1.0.10/) replace

`net describe nwrem` shows the version and distribution date, `nwrem version` the package, core and plugin versions, and `e(version)`
holds the package version in the stored results. Release history: `CHANGELOG.md`; how releases are made: `RELEASING.md`.


## Requirements

* Stata 17 or later. Tested with Stata 17 and Stata 18 (Stata/BE is enough). The Mata libraries are built with Stata 17, the oldest tested version, because a library built by a newer Stata is ignored by older ones; Stata 16 and older have not been tested and are not expected to work.
* The core nwcommands package (see above), including its Mata library `lnwcommands.mlib`.

## Speed

`nwrem` runs in Mata (no compiled plugin). Timed against `relevent::rem.dyad()` 1.2-1 (ordinal likelihood, covariance matrix computed by both) on simulated event streams of 200 to 20,000 events and 20 to 100 actors (Apple M5 Pro, Stata 17, R 4.6, 26 October 2026): the time of relevent divided by the time of `nwrem` ranged from 0.75 to 36. `nwrem` is faster with degree, covariate and inertia effects (1.3 to 36 times, except 0.92 for the two-effect model at 200 events) and slightly slower with the recency effects `rsndsnd rrecsnd` up to 1,000 events (0.75 to 0.9). The coefficients agree to about three significant digits. Details and caveats are in `help nwrem`; the timing scripts are in `dev/speed/`.

## Tests

The tests run against an installed or checked-out core. Point the environment variable NWCORE to the
directory of the nwcommands (core) package (the directory that contains `unw_core.do` and the core `.ado`
files) and run, from the root of this repository:

    NWCORE=/path/to/nwcommands cscripts/run_tests.sh

Each test is a do-file in `cscripts/` that prints `PASS` or `ALL OK` lines; the runner prints the number of PASS
lines and any Stata error per test. Stata is run with `-e`. Validation scripts that compare with the R
reference implementation are in `dev/`.

## Rebuilding the Mata library

`lib/build.do` rebuilds `lib/lnwrem.mlib` from `unw_rem.do` (run it from the repository root: `StataBE -e do lib/build.do`).

## License

GNU General Public License version 3 (see `LICENSE`); see `NOTICE.md` for what the package is derived from and
how to cite it.
