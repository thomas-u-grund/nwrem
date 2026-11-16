cscript

* There is no Mata fallback: when the plugin file is missing nwrem stops with r(601), when the installed plugin is too old for this
* version (or cannot be loaded) with r(3495); both with a message. With the plugin the model fits.
* The test works in a scratch copy of the ado files (without lib/plugins) and puts a file of the plugin's name first on the adopath:
*  (a) no plugin anywhere              -> r(601);
*  (b) a file that is not a plugin     -> r(3495);
*  (c) the plugin of this tree         -> fits.
* (A plugin with another protocol number is tested in test_nwrem_oldplugin.do: a plugin stays loaded for the rest of a Stata session.)
* Environment: NWCORE (core checkout, required).
local nwcore : env NWCORE
if `"`nwcore'"' == "" {
	di as error "set the environment variable NWCORE to the directory of the nwcommands (core) package"
	exit 198
}
local root `"`c(pwd)'"'
quietly do `"`nwcore'/unw_core.do"'
mata: mata mlib index

nwclear
clear
set obs 120
gen long sender = .
gen long receiver = .
gen eventtime = _n
mata:
mata set matastrict off
rseed(20261116)
n = 9
for (i=1; i<=120; i++) {
	pair = runiformint(1, 2, 1, n)
	while (pair[1] == pair[2]) pair = runiformint(1, 2, 1, n)
	st_store(i, "sender", pair[1])
	st_store(i, "receiver", pair[2])
}
end
nwset sender receiver, eventtime(eventtime) name(chk)
mata: st_local("pname", RemNativePluginFilename())
mata: st_local("plugsrc", RemNativePluginPath())
confirm file `"`plugsrc'"'

* scratch copy of the ado files, no plugin
tempfile __scx
local sc `"`__scx'_d"'
capture mkdir `"`sc'"'
capture erase `"`sc'/`pname'"'
foreach f in nwrem.ado _nwrem_libcheck.ado nwrem_version.ado {
	quietly copy `"`root'/`f'"' `"`sc'/`f'"', replace
}
capture adopath - `"`root'/lib/plugins/macos"'
capture adopath - `"`root'/lib/plugins/unix"'
capture adopath - `"`root'/lib/plugins/windows"'
capture adopath - `"`root'"'
adopath ++ `"`sc'"'
capture program drop nwrem
capture program drop _nwrem_libcheck

* (a) no plugin
foreach cmd in "nwrem chk, nodsnd nidrec" "nwrem chk, frpsndsnd rsndsnd" {
	capture noisily `cmd'
	assert _rc == 601
}
* the frame of the fit does not stay behind, the current frame is unchanged
assert "`c(frame)'" == "default"
di as text "  PASS: no plugin file -> r(601)"

* (b) a file that is no plugin
file open fh using `"`sc'/`pname'"', write text replace
file write fh "this is not a plugin" _n
file close fh
capture noisily nwrem chk, nodsnd nidrec
assert _rc == 3495
assert "`c(frame)'" == "default"
capture frame __nwrem_native: describe
assert _rc != 0
di as text "  PASS: a file that cannot be loaded -> r(3495), no frame left behind"
erase `"`sc'/`pname'"'

* (c) the plugin of this tree
local sc2 `"`sc'/new"'
capture mkdir `"`sc2'"'
quietly copy `"`plugsrc'"' `"`sc2'/`pname'"', replace
capture shell chmod +x "`sc2'/`pname'"
adopath ++ `"`sc2'"'
nwrem chk, nodsnd nidrec
assert e(N) == 119 | e(N) == 120
nwrem chk, nodsnd nidrec frpsndsnd rsndsnd
di as text "  PASS: with the plugin the models fit"
di "test_nwrem_noplugin: ALL OK"
