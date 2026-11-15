# nwrem

<!--version-->**Version 1.2.0** (released 15 November 2026)<!--/version-->

`nwrem` fits relational event models (REM) to a sequence of timed events between actors (who sends to whom, when), declared as an event-type temporal network with `nwset ..., eventtime()`. It estimates degree, inertia, recency and covariate effects by (partial) likelihood.

Part of the nwcommands family of Stata packages for network analysis. nwrem is a separate package with its
own repository; it needs the core package nwcommands but no other model package.

## Install

1. Install the core package first (Stata): `net install nwcommands, from(https://nwcommands.org/net/) replace`
   (alternative: `from(https://raw.githubusercontent.com/thomas-u-grund/nwcommands/main/)`). Required: nwcommands (core), version 3.24.0 or later.
2. Install this package from the core: `nwinstall, modelpkg(nwrem)`.
   `nwinstall, everything` installs the core and all four model packages in one step; `nwinstall, all` installs the core only and `nwinstall, models` adds the model packages to it.

`nwinstall` installs the latest release (the state of the main branch). Without `nwinstall`, the package can be installed directly from GitHub:

       net install nwrem, from(https://raw.githubusercontent.com/thomas-u-grund/nwrem/main/) replace

To install a specific version, point `from()` at the release tag (GitHub serves every tag under its own raw URL), for example version 1.0.8:

       net install nwrem, from(https://raw.githubusercontent.com/thomas-u-grund/nwrem/v1.2.0/) replace

`net describe nwrem` shows the version and distribution date, `nwrem version` the package, core and plugin versions, and `e(version)`
holds the package version in the stored results. Release history: `CHANGELOG.md`; how releases are made: `RELEASING.md`.


## Requirements

* Stata 17 or later. Tested on macOS with Stata 17, 18 and 19 and on Windows with Stata 19 (Stata/BE is enough). The Mata libraries are built with Stata 17, the oldest tested version, because a library built by a newer Stata is ignored by older ones; Stata 16 and older have not been tested and are not expected to work.
* The core nwcommands package (see above), including its Mata library `lnwcommands.mlib`.

## Speed

`nwrem` runs in Mata (no compiled plugin). Timed against `relevent::rem.dyad()` 1.2-1 (ordinal likelihood) on simulated event streams of 200 to 20,000 events and 20 to 100 actors, with five effect sets (two degree effects; four degree effects; four degree plus two inertia effects `frpsndsnd frrecsnd`; two degree plus two recency effects `rsndsnd rrecsnd`; two degree plus three covariate effects). `nwrem` 1.2.0 was run in Stata 17 on 15 November 2026, the times of relevent (R 4.6.0) are from 26 and 27 October 2026, both on the same Apple M5 Pro. `nwrem` always computes the covariance matrix, so the like-for-like setting of relevent is `hessian=TRUE`; with `hessian=FALSE` relevent is 1.1 to 2.2 times faster than that. Both were timed.

`nwrem` was faster than relevent in every cell in which both programs finished: the time of relevent divided by the time of `nwrem` ranged from 3.3 to 213 with the Hessian and from 2.1 to 96 without. The smallest ratios (3.3 to 15) are with the recency effects, the largest (84 to 213) with the inertia effects. `nwrem` needed 0.009 seconds at 200 events and 20 actors (two degree effects), 0.4 seconds at 5,000 events and 50 actors and 3.7 seconds at 20,000 events and 100 actors; the largest fits (20,000 events, 100 actors) took 97 seconds with the recency effects and 43 seconds with the inertia effects. With 20,000 events relevent did not finish within 600 seconds with the Hessian for the four degree effects, the recency effects and the covariate effects (ratios above 98, 6.2 and 47). The peak memory of the Stata process was 0.2 GB with 200 events and 0.6 GB with 20,000 events and 100 actors (the memory of relevent was not measured). The coefficients agree to about three significant digits (largest absolute difference 0.016). Medians of 7 fits each in its own process after an untimed warm-up fit (fewer in the largest cells); the first call in a Stata session takes about 0.1 seconds longer for loading the Mata library. Timings depend on the machine, the data and the effects. Details and caveats are in `help nwrem`; the timing scripts and recorded times are in `dev/speed/`.

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

## If the Mata library does not load

The Mata library (lnwrem.mlib) is built with Stata 17. A library built by an older Stata loads in every later Stata; one built by a newer Stata is ignored by an older one (r(3499), "too new to be run by this version of Stata"). Build it with your own Stata: `nwinstall, buildmata(nwrem)` (or `nwinstall, buildmata(all)` for the core and every installed package). The command fetches the Mata source from this repository, compiles it, installs the library and keeps the old file as `.prev`. It clears the data and the Mata objects in memory, so save first; restart Stata afterwards. Needs nwcommands 3.14 or later.
