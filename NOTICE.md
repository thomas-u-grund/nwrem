# NOTICE

<!--version-->**Version 1.0.0** (released 24 October 2026)<!--/version-->

nwrem is Copyright (C) 2026 Thomas U. Grund and is distributed under the GNU General Public License, version 3 (file `LICENSE`).

## What this package is derived from

`nwrem` implements the statistical model of Butts (2008) and was developed with the R package `relevent` as the reference implementation and as the cross-check target. Because the package follows the structure of `relevent`, it is distributed under the GNU General Public License, which is compatible with relevent's GPL (>= 2).
* **relevent** (R package, version compared: 1.2-1). Authors: Carter T. Butts. License: GPL (>= 2).
  https://cran.r-project.org/package=relevent
  Reference: Butts, C. T. (2008). A relational event framework for social action. Sociological Methodology 38(1), 155-200. doi:10.1111/j.1467-9531.2008.00203.x

## Validation

Estimates were compared with `relevent::rem.dyad()` (version 1.2-1) on identical simulated event sequences: coefficients and log-likelihoods agree to within the tolerances stated in the test and validation scripts (`cscripts/test_nwrem_*.do`, `dev/rem_*`). The degree-accumulator semantics are checked against output of `relevent::acl.deg()`.

## AI assistance (PLACEHOLDER: the owner confirms or rewrites this paragraph)

Parts of the code, tests, documentation and build tooling of this package were written with the help of an AI assistant (Claude, Anthropic) working under the direction of the author, who reviewed and is responsible for the result. [Wording to be confirmed by the author before release.]

## How to cite

Grund, T. U. (2026). nwrem: a Stata package (version 1.0.0). Zenodo. https://doi.org/10.5281/zenodo.XXXXXXX
(placeholder DOI; the owner replaces it when the Zenodo record exists).
Please also cite the core package (Grund, T. U., nwcommands) and the work this package is derived from (see above).
