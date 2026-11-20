cscript

* A plugin of an older package (protocol 2 as now, but without the diagnostics, code 40 / 98) is accepted for the fit and refused by
* estat rank / actors / time with r(3495) and a message. The test builds such a plugin from native/rem_sim.c with -DREM_NO_DIAG (macOS
* and Linux, needs a C compiler; skipped on Windows or when the compiler is missing). The protocol number is deliberately not raised for
* code 40: an older package keeps working with the new plugin, and the diagnostics probe the plugin (code 98).
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
set obs 60
gen long sender = .
gen long receiver = .
gen eventtime = _n
mata:
mata set matastrict off
rseed(20261116)
n = 7
for (i=1; i<=60; i++) {
	pair = runiformint(1, 2, 1, n)
	while (pair[1] == pair[2]) pair = runiformint(1, 2, 1, n)
	st_store(i, "sender", pair[1])
	st_store(i, "receiver", pair[2])
}
end
nwset sender receiver, eventtime(eventtime) name(chk)
mata: st_local("pname", RemNativePluginFilename())

tempfile __scx
local sc `"`__scx'_d"'
capture mkdir `"`sc'"'
capture erase `"`sc'/`pname'"'
foreach f in nwrem.ado _nwrem_libcheck.ado nwrem_version.ado nwrem_estat.ado {
	quietly copy `"`root'/`f'"' `"`sc'/`f'"', replace
}
capture adopath - `"`root'/lib/plugins/macos"'
capture adopath - `"`root'/lib/plugins/unix"'
capture adopath - `"`root'/lib/plugins/windows"'
capture adopath - `"`root'"'
adopath ++ `"`sc'"'
capture program drop nwrem
capture program drop _nwrem_libcheck
capture program drop nwrem_estat

if "`c(os)'" == "MacOSX" {
	quietly shell clang -bundle -o "`sc'/`pname'" "`root'/native/rem_sim.c" "`root'/native/spi/stplugin.c" -DSYSTEM=APPLEMAC -DREM_NO_DIAG -I "`root'/native/spi" 2>/dev/null
}
else if "`c(os)'" == "Unix" {
	quietly shell gcc -shared -fPIC -DSYSTEM=OPUNIX -DREM_NO_DIAG -I "`root'/native/spi" -o "`sc'/`pname'" "`root'/native/rem_sim.c" "`root'/native/spi/stplugin.c" -ldl 2>/dev/null
}
capture confirm file `"`sc'/`pname'"'
if _rc {
	di as text "  SKIPPED: no C compiler (or Windows): the plugin of another protocol could not be built"
	di "test_nwrem_estat_oldplugin: ALL OK (skipped)"
	exit 0
}
quietly shell chmod +x "`sc'/`pname'"
* the fit works (the protocol is the one of this package)
quietly nwrem chk, nodsnd nidrec
assert e(N) == 60
foreach cmd in "estat rank" "estat rank, noplot" "estat actors" "estat time, bins(3)" {
	capture noisily `cmd'
	assert _rc == 3495
}
assert "`c(frame)'" == "default"
capture frame __nwrem_dgev: describe
assert _rc != 0
di as text "  PASS: a plugin without code 40: the fit works, estat -> r(3495) with a message"
di "test_nwrem_estat_oldplugin: ALL OK"
