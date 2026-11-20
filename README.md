# nwrem

<!--version-->**Version 1.6.0** (released 20 November 2026)<!--/version-->

`nwrem` fits relational event models (REM) to a sequence of timed events between actors (who sends to whom, when), declared as an event-type temporal network with `nwset ..., eventtime()`. It estimates degree, inertia, recency, covariate, triadic and shared-partner effects, fixed effects and participation shifts, by the ordinal partial likelihood or the waiting-time (interval) likelihood, by maximum likelihood or posterior mode, optionally with restricted risk sets (dyads that cannot occur, actors that enter and leave). The likelihood, its gradient and its exact Hessian are evaluated in a native plugin; the results agree with the exact maximum of the R package relevent (1.2-1), computed from its own statistics, to at least five digits (the shared out-partner statistic `ospsnd` is the intended symmetric statistic, not the asymmetric one of relevent 1.2-1; see `help nwrem`).

Part of the nwcommands family of Stata packages for network analysis. nwrem is a separate package with its
own repository; it needs the core package nwcommands but no other model package.

## Install

1. Install the core package first (Stata): `net install nwcommands, from(https://nwcommands.org/net/) replace`
   (alternative: `from(https://raw.githubusercontent.com/thomas-u-grund/nwcommands/main/)`). Required: nwcommands (core), version 3.29.0 or later.
2. Install this package from the core: `nwinstall, modelpkg(nwrem)`.
   `nwinstall, everything` installs the core and all four model packages in one step; `nwinstall, all` installs the core only and `nwinstall, models` adds the model packages to it.

`nwinstall` installs the latest release (the state of the main branch). Without `nwinstall`, the package can be installed directly from GitHub:

       net install nwrem, from(https://raw.githubusercontent.com/thomas-u-grund/nwrem/main/) replace

To install a specific version, point `from()` at the release tag (GitHub serves every tag under its own raw URL), for example version 1.0.8:

       net install nwrem, from(https://raw.githubusercontent.com/thomas-u-grund/nwrem/v1.6.0/) replace

`net describe nwrem` shows the version and distribution date, `nwrem version` the package, core and plugin versions, and `e(version)`
holds the package version in the stored results. Release history: `CHANGELOG.md`; how releases are made: `RELEASING.md`.


## Requirements

* Stata 17 or later. Tested on macOS with Stata 17, 18 and 19 and on Linux with Stata 19; Windows has not been tested yet (Stata/BE is enough). The Mata libraries are built with Stata 17, the oldest tested version, because a library built by a newer Stata is ignored by older ones; Stata 16 and older have not been tested and are not expected to work.
* The core nwcommands package (see above), including its Mata library `lnwcommands.mlib`.
* Platform plugins are shipped for macOS, Linux and Windows.

## Speed

`nwrem` evaluates the likelihood, its gradient and its Hessian in a compiled plugin and maximises the likelihood with Newton steps. Timed against `relevent::rem.dyad()` 1.2-1 (ordinal likelihood) on simulated event streams of 200 to 20,000 events and 20 to 100 actors, with five effect sets (two degree effects; four degree effects; four degree plus two inertia effects `frpsndsnd frrecsnd`; two degree plus two recency effects `rsndsnd rrecsnd`; two degree plus three covariate effects). `nwrem` 1.3.0 was run in Stata 17 on 16 November 2026, the times of relevent (R 4.6.0) are from 26 and 27 October 2026, both on the same Apple M5 Pro. `nwrem` always computes the covariance matrix, so the like-for-like setting of relevent is `hessian=TRUE`; with `hessian=FALSE` relevent is 1.1 to 2.2 times faster than that. Both were timed.

`nwrem` was faster than relevent in every cell in which both programs finished: the time of relevent divided by the time of `nwrem` ranged from 33 to 4,130 with the Hessian and from 23 to 2,544 without. The smallest ratios (50 to 249) are with the recency effects, the largest (above 2,500) with the covariate effects and the degree effects. `nwrem` needed 0.006 seconds at 200 events and 20 actors (two degree effects), 0.02 seconds at 5,000 events and 50 actors and 0.16 seconds at 20,000 events and 100 actors; the largest fits (20,000 events, 100 actors) took 12 seconds with the inertia effects and 7.8 seconds with the recency effects. With 20,000 events relevent did not finish within 600 seconds with the Hessian for the four degree effects, the recency effects and the covariate effects. The peak memory of the Stata process was 0.21 GB with 200 events and 0.29 GB with 20,000 events and 100 actors (the memory of relevent was not measured). The coefficients agree to about three significant digits (largest absolute difference 0.005); relevent stops at its own convergence tolerance, `nwrem` at the maximum of the likelihood. Medians of 7 fits each in its own process after an untimed warm-up fit; the first call in a Stata session takes about 0.05 seconds longer for loading the Mata library and the plugin. Timings depend on the machine, the data and the effects. Details and caveats are in `help nwrem`; the timing scripts and recorded times are in `dev/speed/`.

## Tests

The tests run against an installed or checked-out core. Point the environment variable NWCORE to the
directory of the nwcommands (core) package (the directory that contains `unw_core.do` and the core `.ado`
files) and run, from the root of this repository:

    NWCORE=/path/to/nwcommands cscripts/run_tests.sh

Each test is a do-file in `cscripts/` that prints `PASS` or `ALL OK` lines; the runner prints the number of PASS
lines and any Stata error per test. Stata is run with `-e`. Validation scripts that compare with the R
reference implementation are in `dev/`.

## Native plugin

The package ships a native Stata plugin (rem_sim.c) for macOS (universal), Linux and Windows (built by the GitHub Actions workflow `.github/workflows/build-plugins.yml`; the macOS build can be reproduced with `make -C native macos`). Every fit needs the plugin; a platform without one stops with r(601) and a plugin that does not fit the `.ado` files with r(3495) (see the help file). The C source is part of the package (`net get nwrem, from(https://raw.githubusercontent.com/thomas-u-grund/nwrem/main)` copies it into the current directory, with `nwrem_native_readme.txt` explaining the build) and is in `native/` of this repository.

## Rebuilding the Mata library

`lib/build.do` rebuilds `lib/lnwrem.mlib` from `unw_rem.do` (run it from the repository root: `StataBE -e do lib/build.do`).

## Manual

A user manual (PDF in `manual/`, with the LaTeX source and the do-files of its examples) is archived at Zenodo: <https://doi.org/10.5281/zenodo.24398012> (all versions). Cite the manual by that address together with the package version printed by `nwrem version`.

## License

GNU General Public License version 3 (see `LICENSE`); see `NOTICE.md` for what the package is derived from and
how to cite it.

## If the Mata library does not load

The Mata library (lnwrem.mlib) is built with Stata 17. A library built by an older Stata loads in every later Stata; one built by a newer Stata is ignored by an older one (r(3499), "too new to be run by this version of Stata"). Build it with your own Stata: `nwinstall, buildmata(nwrem)` (or `nwinstall, buildmata(all)` for the core and every installed package). The command fetches the Mata source from this repository, compiles it, installs the library and keeps the old file as `.prev`. It clears the data and the Mata objects in memory, so save first; restart Stata afterwards. Needs nwcommands 3.14 or later.
