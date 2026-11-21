# The nwrem manual

`nwrem_manual.pdf` is the user manual and reference of nwrem. The LaTeX source is `nwrem_manual.tex` with one file per chapter (`ch*.tex`, `app_translation.tex`).

## Bumping the version (one-line change)

The manual's title and citation carry no version number; the title page states the series it describes (`\manualseries`, valid for 1.7.x). The exact version and date of the release that produced the listings are further macros in `nwrem_manual.tex`:

    \newcommand{\manualseries}{1.7}
    \newcommand{\pkgversion}{1.7.0}
    \newcommand{\pkgdate}{21 November 2026}
    \newcommand{\corever}{3.33.0}

Change `\manualseries` only for a new minor or major release whose documented behaviour changed. For a patch release change `\pkgversion`, `\pkgdate` and `\corever`, rerun the examples (`make examples`, see below), rebuild (`make pdf`) and check the pages that show version strings. The tag in the installation example of `ch01_intro.tex` (`nwrem/v1.7.0/`, inside a listing, so it cannot use the macro) is the only other place with the number.

## The DOI


## Building

    make -C manual pdf        # regenerates the two generated tables, then pdflatex (3 passes)
    make -C manual check      # undefined references, overfull boxes, glued words
    NWCORE=/path/to/nwcommands make -C manual examples   # reruns the do-files of ex/ in Stata 17 (a few minutes)

`build_valid.py` reads the log of `ex/ex09_validate.do` (the repository's comparison test with relevent) and `cscripts/ref14/results.csv` and writes `gen_valid.tex` and `gen_validnums.tex` (Chapter 8). `build_timing.py` reads `timing_linux.csv` (the cells of the run-time comparison with relevent on Linux, 16 November 2026, copied from the speed page of the website) and writes `gen_timing.tex` (Chapter 10). Do not edit the `gen_*.tex` files by hand.

## The examples

The listings in `ex/out/*.txt` are cut from the Stata logs by `ex/mklistings.py`: a do-file marks a piece with a line `*# name`, and the log text up to the next marker becomes `ex/out/name.txt`. `run_examples.sh` runs the do-files `ex/ex*.do` with Stata 17 (`-e`, each in its own process; the default binary is `/Applications/Stata 17.0/StataBE.app/Contents/MacOS/StataBE`, set `STATA` to change it), with an empty scratch directory as PLUS and the repository's plugin first on the adopath (`ex/setup.doh`), then runs `mklistings.py`. The data come from the core package: `setup.doh` sets `$nwwebpath` to the `data` folder of `NWCORE`, so no internet connection is needed. `ex/mail.doh` and `ex/buildnet.doh` hold the shared data preparation. `ex/ex10_estat.do` runs the diagnostics of Chapter 7 (`estat rank`, `estat actors`, `estat time`) and exports the figures of that chapter to `fig/` (PDF, written by `estat ..., export()`); `fig/rank_demo.*` are the files of the `saving()`/`export()` demonstration and are not used in the text. The graphs need the core 3.29.0 or later.

The Stata logs (`ex/ex*.log`) are not committed: they contain the licence header of the Stata that ran them and the paths of the scratch machine. `mklistings.py` replaces the path of the plugin in the version listing by the usual place of an installed package.

`ex/ex09_validate.do` runs two test scripts of the repository (`cscripts/test_nwrem_relevent14.do` and `cscripts/test_nwrem_collinear14.do`) from the root of the repository; they need the reference values in `cscripts/ref14`, which were made with R and relevent 1.2-1 (`dev/rem_relevent14_gen.R`). Running R is not needed for the manual.

## Archiving


The PDF is published on the package website (https://nwcommands.org/nwrem/nwrem_manual.pdf) and on Zenodo (all-versions DOI 10.5281/zenodo.24398012, `\manualdoi`). A new minor series is uploaded as a new file version of the existing record.
