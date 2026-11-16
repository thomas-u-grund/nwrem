* Common set-up of the example do-files of the manual. The environment variables
* NWCORE (directory of the nwcommands core), NWREM (directory of nwrem) and
* NWPLUS (an empty scratch directory used as PLUS) are set by run_examples.sh.
capture program drop nwinstall
local nwcore : env NWCORE
local nwrem : env NWREM
local nwplus : env NWPLUS
sysdir set PLUS "`nwplus'"
quietly adopath ++ "`nwcore'"
quietly adopath ++ "`nwcore'/lib"
quietly adopath ++ "`nwrem'/lib"
quietly adopath ++ "`nwrem'/lib/plugins/macos"
quietly adopath ++ "`nwrem'"
* the data sets of the core (nwwebuse reads them from here instead of from the web)
global nwwebpath "`nwcore'/data"
set more off
