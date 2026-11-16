# Gotchas of nwrem

Known, already diagnosed pitfalls. Entries copied from the nwcommands notes at the time of the split; some mention the core package.

## Mata libraries must be built with the OLDEST supported Stata (Stata 17), never a newer one

The 2026-10-25 releases (core 3.5.0, nwsaom 1.0.7, nwergm 1.2.0, nwdynam 1.1.0, nwrem 1.0.5) shipped `.mlib` files built with Stata 18.
A Stata 17 user got `nwwebuse florentine` -> `<istmt>: 3499 nws_create() not found`, even from a clean install: Stata 17 lists the
library (`mata mlib query`, `mata describe using lnwcommands` work) but silently ignores its contents. The only trace is
`mata which nws_create()`: "(nws_create() in lnwcommands, compiled by Stata 18.0, is too new to be run by this version of Stata and so
was ignored)". The reverse is fine: Stata 18 reads libraries built by Stata 17. So build with the oldest supported Stata (currently 17).
`lib/build.do` of every package stops when `c(stata_version)` is higher than 17 (`NW_ALLOW_NEWER_STATA=1` overrides, for libraries that
are never released). The only reliable check of a release candidate is to run a
command in Stata 17 against the built library. The core has `_nwlibcheck.ado` (called by `unw_defs` and the commands that do not call it) which turns the
failure into a readable message with exit 3499. An OLD library in the user's PLUS folder (for example from a Sep 2026 install) shadows
the new one and gives r(3021) or other class errors; the message tells the user to `ado uninstall nwcommands` first.

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

## `nwinstall, buildmata(nwrem)` compiles the source files listed in the core (2026-11-03)

The user-side rebuild of lnwrem.mlib lives in the core (`nwinstall_buildmata.ado`, table `nwinstall_buildmata_tab`): it lists the source files of this package, the library names and the `mata mlib add` patterns copied from `lib/build.do`. If this package gets a new Mata source file (as nwsaom did with `unw_saom_struct.do`, included by `unw_saom.do`) or another library, the table must change, or the rebuild fails with "file ... not found" (r(601)) or leaves functions out. The sources fetched are those on `main`.

## Mata `_error("long text")` loses the message (r(3300))

`_error(errtxt)` fails itself with r(3300) "argument out of range" when the text is longer than about 110 characters (100
works, 120 fails), and the intended message is never shown. Print long messages with `errprintf()` and leave with
`exit(rc)` (Mata `exit(3498)` returns r(3498) to Stata without a traceback).

## Replay and the optional network name

`nwrem, nodsnd` (no network name: the current network) also starts with a comma, so Stata's `replay()` is true for it.
The replay branch therefore only replays when `syntax [, Level(cilevel)]` accepts the options; any effect option falls
through to a fit.

## Event lists can hold actor index 0 or a missing time

The core's `build_eventlist()` gives index 0 to an event whose sender or receiver label is not a node name (missing id,
or core S1: numeric ids >= 1e7 are labelled with %9.0g in nwset but named with %18.0g), and `nwset` keeps missing event
times. `nwrem.ado` refuses both before the fit (r(416)).

## Fast evaluator (unw_rem.do, 1.2.0): traps found while writing it

- **Mata `exp()` overflow returns a missing value, and `sum()`, `rowsum()` and matrix products with it do not stop.** `exp(800)` is `.`; a sum that contains it silently skips it. The result looks like a legal number that is too small. `rem_loglik_grad_fast()` therefore tests every exponentiated matrix and every normaliser with `hasmissing()` and `Z < 1e-250`, and returns 0 so that `rem_loglik_grad_auto()` uses the dense evaluator (`rem_loglik_grad_multi()`, unchanged) for that evaluation. The dense evaluator shifts by one global maximum and cannot overflow; the fast one shifts the sender and the receiver terms separately and can underflow (both shifts at the same actor).
- **Cancellation:** the normaliser (sum e^a)(sum e^b) minus the diagonal subtracts a cell from a row sum; when one actor holds almost all the mass the difference is rounding noise. `rem_sumexcl()` recomputes the cell at the row maximum without the subtraction. Do not simplify it back to `rowsum(E) :- E`.
- **`covevent()` diagonal:** nwrem.ado accepts a missing diagonal and non-binary values. The dense evaluator overwrote the diagonal of the log-rate matrix with -1e300, so whatever the diagonal held did not matter. The fast evaluator must set the diagonal of the covariate to 0 before it forms `exp(theta * C)`. Leaving it missing makes the normaliser and the gradient silently wrong: prototype fits then needed 1,000 to 13,000 evaluations and returned wrong estimates.
- **The optimizer's random starts decide which point of a flat ridge is returned.** Collinear effects (for example `nodsnd nidsnd ntdegsnd`) have no unique maximum; the old code returned arbitrary coefficients for them and took about 500 evaluations. Since 1.2.0 `rem_dependent_effects()` removes exactly dependent effects before the optimizer (coefficient 0, variance 0; `nwrem.ado` flags them through the variance). Tests that compare such fits with an older engine can compare only the log likelihood and the identified combinations (here `nodsnd + ntdegsnd / 2`).
- **Mata at the top level of a do-file:** an `if (...) { ... }` block as the last statement before `end` makes Mata wait for a possible `else` and fail with "unexpected end of line"; end such a block with another statement. `external` declarations are not allowed at the top level (put them in a function).

## The fit needs the plugin: tests that read `lib/lnwrem.mlib` and `lib/plugins/macos` see the repo build only through the adopath

`nwrem` finds the plugin with `findfile("rem_sim_<platform>.plugin")` (what `net install` makes visible) and, for a checkout of the repository, at `lib/plugins/<platform>/` next to `nwrem.ado`. A stale `rem_sim_macos.plugin` in the real PLUS folder shadows the repo build: `cscripts/run_tests.sh` sets a scratch PLUS and puts `lib/plugins/macos` on the adopath. The fit tests use `lib/lnwrem.mlib`: rebuild it with Stata 17 (`lib/build.do`) after every change of `unw_rem.do`.

## Plugin protocol and loaded plugins

The probe `99 0 0 0 0 0 0` returns the protocol number (row 1 of variable 2). Within one Stata session the first plugin loaded for the program name `remnative` stays, even when another file of that name is put first on the adopath: that is why `test_nwrem_oldplugin.do` (builds a plugin with `-DREM_PROTOCOL=0` from `native/rem_sim.c`) and `test_nwrem_noplugin.do` are separate files.
The fit writes its model into the frame `__nwrem_native`; `nwrem.ado` restores the current frame and drops that frame after every fit, also after an error (an error inside Mata would otherwise leave the user in the plugin's frame).

## The exact Hessian makes the Newton fit converge to the true maximum: reference values of older versions are only BFGS-accurate

Fits of versions up to 1.2.0 stopped where `optimize()` (BFGS, numerical Hessian) met its default tolerances: coefficients and standard errors of the old reference values differ from the maximum in the fourth to fifth digit (the log likelihood in the tenth). `test_nwrem_fast` therefore compares coefficients and standard errors to 5e-4 and requires the new log likelihood to be at least as high.

## Plugin and Mata reference must agree: change a statistic in BOTH places

The statistics are defined in `native/rem_sim.c` (`part_A/B/S`, `sval_one`, the share formulas) and in `cscripts/ref_rem_mata.do` (`rem_loglik_grad_multi`). The plugin test compares log likelihood and gradient (1e-9 relative) and, on a sample of models, the Hessian with the numerical derivative of the reference gradient. A bug in a statistic that is changed only in the plugin shows up as a difference there; do not "fix" the test.

## The fast evaluator gives up in four cases and the plugin then evaluates densely (O(n^2) per event)

exp() overflow of a sparse dyadic term (sigma > 700), an underflowing normaliser, a correction that cancels more than six digits (a large negative coefficient of a dyadic effect on dyads that carry nearly all the mass) and a missing value. Result row `2 + P + P*P + P` of the plugin tells which evaluator ran (code 22 = fast only, 21 = dense only; tests use them). A fit whose iterations all take the dense route is slow at large n; nothing is wrong with it.

## Mata: `a :/ b / c` divides by `b / c` (the scalar `/` binds tighter than `:/`)

The prior gradient `(nu + 1) :* z :/ (nu :+ z :^ 2) / sc` was `... :/ ((nu :+ z^2) / sc)`: wrong by a factor of sc^2, the t prior then made the Newton iteration fail ("flat region", r(430)) only for scale 100 and not for the normal prior. Put parentheses round the whole vector expression before dividing by a scalar.

## relevent 1.2-1 `OSPSnd` is asymmetric: nwrem's `ospsnd` deliberately differs

For a pair (a,b) with a earlier in the order of first appearance as sender, relevent counts 2 * sum_l min(c[a,l], c[b,l]) and the reverse direction gets 0 (reproduced exactly by emulation). `ospsnd` of nwrem is the symmetric statistic, so the cross-check of this effect uses relevent's `rem()` (statistics supplied by us) and not `rem.dyad()`. OTP, ITP and ISP agree with relevent exactly.

## How the references of `cscripts/ref14/` are made (`dev/rem_relevent14_gen.R`)

`rem.dyad()` stops at BFGS tolerances (coefficients to the fifth to sixth digit, standard errors to the fourth), so the tight check is `rem()` of relevent (trust-region optimiser, analytic derivatives) on the statistics built with `rem.dyad.lambda()` and unit parameter vectors. `rem.dyad.lambda()` is 1-based in the iteration and takes the accumulated list of that iteration (`acl[[i]]`). `rem()` needs a 0/1 support matrix per event: that is how risk sets and entry/exit windows are cross-checked (rem.dyad has none). relevent numbers the covariates of an effect by position (`covsnd_x1`, `covsnd_x2`); the generator renames them to nwrem's `covsnd_<variable>`. Regenerate with `Rscript dev/rem_relevent14_gen.R` from the repository root (needs the R package relevent 1.2-1); the cases are fully determined by the seeds.

## The plugin's evaluation at theta = 0 is used three times

`rem_nat_dependent_par()` keeps the log likelihood, gradient and Hessian of the evaluation at theta = 0 (`RemNat.cy/cg/cH`); `RemFitX` uses them as `ll0` (ordinal) and `rem_newton()` as its first iterate when the start is 0 (the sub-block of the kept parameters, plus the prior's terms with `postmode`). If a change makes the first Newton step depend on anything else (a different start, a changed blob), clear `cached`.
