# Gotchas of nwrem

Known, already diagnosed pitfalls. Entries copied from the nwcommands notes at the time of the split; some mention the core package.

## Attaching a covariate to an `eventtime()`-declared network needs `_nwnode`, not a fresh merge

After `nwset sender receiver, eventtime(t) name(netname)` declares an event network (found while
building the `socialevolution` example dataset, 2026-09-12), the dataset left in memory is **not**
the original sender/receiver/t rows anymore — it's one row per actor who appears in at least one
event, with columns `_nwnode` (the actor's own label) and `_nwinclude`. A `merge 1:1 label using
covariates.dta` fails outright (`variable label not found`) because there is no `label` variable to
merge on at that point; the actor identifier is `_nwnode`.

The fix is a rename-merge-rename:

```
rename _nwnode label
merge 1:1 label using covariates.dta, keep(master match) nogen
rename label _nwnode
```

This is unrelated to how covariates work on an already-`nwsave()`d panel dataset (`glasgow`, `s50`,
etc.), where attributes like `smoke1`/`alcohol1` are baked into the saved network file itself and
just show up as ordinary variables on load — no merge needed there at all. The rename-merge-rename
dance is specific to attaching a covariate *after the fact* onto a freshly `nwset`-declared event
network built from a plain, not-pre-declared dataset.

## Mata functions and programs defined inside an .ado file are private to that file

`mata: nwergm_estat_bridge_from_netobj(...)` called from a *different* .ado file fails with "not found" (3499): functions
(and `program`s) defined in an .ado are namespaced `file.name` and only callable from programs of the same file. Anything two
helper files need (observed-network bridge, summary functions) belongs in `unw_ergm.do` (the Mata library), as
`ergm_bridge_obs()`. Likewise `estat gof` plots call `_nwergm_gofplot`, a file of its own.

## Stata `syntax` flag options that start with "no" lose the prefix

`syntax [, NOMPLECHECK]` creates the local `mplecheck`, not `nomplecheck`; testing `"`nomplecheck'" == ""` is then always true.
Use a string option (`mplecheck(on|off)`) or a name that does not start with "no".

## `mata mlib index` does not persist: a library installed by net install can be missing from a session's Mata library list

Stata builds its list of Mata libraries (.mlib) once, early in a session; `mata mlib index` rebuilds it for the running session only
and nothing is saved. A library that `net install` put into PLUS/l/ can be absent from the list (`mata mlib query` shows `lnwcommands`
but not `lnwrem`). The first Mata call then stops with r(3499) "<function>() not found", and a Mata block that mentions a class of
the library stops the whole ado file with r(3000) "class ... undefined (error occurred while loading ...)". Running `mata mlib index`
by hand "fixes" it for that session only, which hid the bug in every manual test.
- Every entry program starts with `_nwrem_libcheck` (which runs `mata mlib index` once when a library function is not visible); do not
  call Mata before it.
- A **file-scope** `mata:` block that mentions a class of a library would be compiled when the file is auto-loaded, before any program
  runs (see nwergm); neither package has one today.
- Reproduce: `SMOKE_STALE=1 tools/smoke_fresh_install.sh <core> <models>` in the core repo builds exactly this state (the session's Mata
  index is made while only the core library is visible). Without `SMOKE_STALE` a plain new session usually finds all libraries,
  which is why a simple "install, restart, run" test passes.
