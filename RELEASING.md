# Releasing nwrem

## Master procedure: https://github.com/thomas-u-grund/nwcommands/blob/main/RELEASING.md

All release procedures and policies of the five packages (steps, order, test launch, tags, GitHub release, website update, Zenodo, lockstep with the core
Mata library, building libraries with Stata 17, known traps) are in the master document above. Follow it; this file only holds what is specific to nwrem.
Two rules from there that are easy to miss: push the release tag by name (`git push origin vX.Y.Z`), never `git push origin main --tags`
(old local tags of this clone never existed on GitHub); and build `lib/*.mlib` with Stata 17, not 18.

## Version files and checks

- Single source of truth: `VERSION` (line 1 the version, line 2 the release date in Stata format, e.g. `25oct2026`). Semantic versioning (master B.4, C4).
- `python3 tools/set_version.py X.Y.Z [date]` writes it into every display (first line of every `.ado`, help headers and the footer of every help file, `nwrem.pkg`, `stata.toc`,
  `README.md`, `NOTICE.md`, `CITATION.cff`, the `e(version)` / `nwrem version` literals); `--check` changes nothing.
- Add `## [X.Y.Z] - YYYY-MM-DD` to `CHANGELOG.md` (Added / Changed / Fixed / Removed); its text is the GitHub release notes.
- `NWCORE=/path/to/nwcommands python3 tools/check_version.py` = version check plus the core-library hash check (below).
- Install lines: latest `net install nwrem, from(https://raw.githubusercontent.com/thomas-u-grund/nwrem/main/) replace`; a given release `.../nwrem/vX.Y.Z/`.
  `nwrem.pkg` states `Requires nwcommands (core), version A.B.C or later`; raise it (and `README.md`) only when this release needs a newer core.

## Library and lockstep with the core

`lib/build.do` builds `lib/lnwrem.mlib` from `unw_rem.do`; it does not load the core and the sources do not mention `nw_def` (verified 2026-10-25). The package still carries `lib/core_mlib.sha256` and `check_version.py` fails when it differs from `$NWCORE/lib/lnwcommands.mlib`.
In a lockstep batch (master C3): rebuild with Stata 17 (`<Stata 17> -e do lib/build.do` from the repository root), `NWCORE=/path/to/nwcommands python3 tools/record_core_lib.py`, test, patch release. Whether a record-only update is enough is an open decision (master B.5).

## Tests

`NWCORE=/path/to/nwcommands cscripts/run_tests.sh [jobs]` (first step: `tools/check_version.py`; each test runs in its own `-e` Stata process; set `STATA` to the Stata 17 binary, then repeat with 18).
Most tests print no PASS marker: failure is an `r()` error and a missing log is NOT RUN (master C0).

## No plugin, no workflow, no manual

nwrem has no native code, no `.github/workflows/`, no `lib/plugins/`; releasing it is: version, tests, commit, push, tag, GitHub release, website. There is no nwrem manual and no Zenodo record; the package is cited by repository and version.
The model follows Butts (2008), cross-checked with R `relevent` (master B.8).
