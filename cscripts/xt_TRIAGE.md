# nwrem extended tests: triage (2026-11-12, Stata 17 BE, nwrem 1.0.13 + core of the same date)

Repro do-files and logs: `$S/xtrun/models/repro/nwrem/rem_repro.do` (+ `rem_repro2.do`, `mataerr.do`), 8-event toy
network on 4 actors. Test logs: `$S/xtrun/models/nwrem_xt_rem_*.log`.

## Suspects

| Id | Verdict | Severity | One-line repro | Cause |
|---|---|---|---|---|
| S4 | CONFIRMED | wrong results silently | `replace t = . in 2` then `nwset s r, eventtime(t) directed name(d)`; `nwrem d, nodsnd` fits all 8 events, the timeless one as the last event (e(N) = 8, no message) | core nwset.ado:322-323 stores missing times; RemState::init sorts them last (unw_rem.do:89). Wanted: refusal or row dropped with a note |
| S1 | CONFIRMED | error only (raw Mata error) | numeric ids >= 10,000,000 (8+ digits, e.g. 10000001): `nwrem a, nodsnd` -> `_error(): 3300 argument out of range` | core nwset.ado:285-286 (two-mode 132-133) labels events `"n"+strofreal(id)` = %9.0g ("n1.00e+07"); node names use %18.0g (nwfromedge.ado:246 / fast route 197). Events get index 0/0, hit the self-loop guard, which then fails as N2. Threshold is 10^7, not 2^24 as the notes said. Static `nwset ..., edgelist` with the same ids is fine. Affects nwdynam too |
| S2 | CONFIRMED | error only | ids 1e9..4e9 (double): same r(3300) | same as S1 |
| S3 | CONFIRMED | error only (raw Mata error) | extra row with missing sender: `nwrem c, nodsnd` -> `rem_loglik_grad_multi(): 3301 subscript invalid` | build_eventlist (core unw_core.do:484) gives index 0 for label "n."; nwrem never checks for index 0 |
| S6 | CONFIRMED | error only (misleading) | `nwload f, xvars`, x with one missing value, `nwrem f, covsnd(x)` -> 32 x "initial values not feasible", "simplex delta required", r(111) | nwrem.ado:99 reads covsnd/covrec/covint without a missing check (covevent() has one, r(416), nwrem.ado:115-118) |
| S7 | CONFIRMED | error only | `nwrem f, covsnd(<26+ character name>)` -> "covsnd_<name> invalid name", r(198) | nwrem.ado:52-53 builds `covsnd_<var>` (also covevent_<net>), matrix colnames limit 32 (nwrem.ado:152-153) |
| S8 | CONFIRMED | cosmetic/minor | `set seed 5; nwrem f, nodsnd frpsndsnd seed(-1)`, then `set seed 6`, same call: e(b) differ (mreldif 1.5e-5) | nwrem.ado:16 `SEED(integer -1)`, :131 -1 = not given. seed(-2) is accepted too |
| S5 | DECIDED: document (owner 2026-11-12: keep the relevent behaviour, fit as directed, say so in the help) | cosmetic (help text) | `nwset s r, eventtime(t) undirected`; nwrem fits the directed model, same numbers as directed | nwrem.ado never reads `directed`. relevent itself has no undirected variant; nwdynam refuses |
| S9 | CONFIRMED (owner 2026-11-12: covariates must be matched to the network's nodes via `_nwnode` when present, not by row position) | wrong results silently | after `nwload, xvars`, `gsort -_nwnode` flips the sign of covsnd (-.511 -> +.511) | nwrem.ado:99 reads by row; the help file still says "one row per actor, in actor order"; fix together with the S6 missing-value check |
| 9 (stale comment) | CONFIRMED | cosmetic (comment only) | `nwset p o, twomode eventtime(t) name(tm)` works; `nwrem tm, nodsnd` reaches the guard (r(198)) | nwrem.ado:24-35 says the guard is unreachable; same in cscripts/test_nwrem_ado.do |
| 10 (core) | CONFIRMED | cosmetic (message) | `nwrem g h, nodsnd` -> "Network g h not found", r(482) | core _nwsyntax.ado:70; wanted "one network only" |
| N2 (new) | CONFIRMED | error only (message lost) | self-loop event (3 -> 3): `nwrem loop, nodsnd` -> `_error(): 3300 argument out of range`, no message | unw_rem.do:79: Mata `_error(errtxt)` fails with r(3300) when the text is longer than about 110 characters (checked: 100 ok, 120 fails). Shorten the text or `errprintf()` + `_error(3498)`. Is also what S1/S2 show |
| N1 (new) | DECIDED: fix (owner 2026-11-12: add estimates replay to all four packages, low priority) | error only | `estimates store m; estimates replay m` -> "nwrem requires at least one effect", r(198) | nwrem has no replay branch (`nwrem` alone). None of nwsaom/nwergm/nwdynam/nwrem replays; help does not promise it |

Counts: CONFIRMED 11 (S1-S4, S6-S9, item 9, item 10, N2), NOT A BUG 0, DECIDED: document 1 (S5), DECIDED: fix 1 (N1, replay).

## Test-code fixes

- xt_rem_edges.do: the id map `10000000 + 2*@ - 1` hits S1; now recorded as `CONFIRMED BUG S1`, the file goes on.
- xt_rem_estimation.do: `estimates replay` made non-fatal (N1, recorded as NOTE); `gen double x` twice (x left from
  Block A, `nwload, xvars` keeps it) -> `capture drop x` / `capture drop x2` first.
- xt_rem_errors.do: the r(3498) self-loop checks became a `CONFIRMED BUG N2` record (gets r(3300)).
- xt_rem_closedform.do: TODO-R done; relevent 1.2-1 references added for nidsnd, ntdegsnd, ntdegrec, nidsnd+nodrec
  (relevent names NTDegSnd/NTDegRec, not NTDEGSnd as in the notes). All four agree.
- xt_rem_suspected.do: verdict markers; S6 now asserts r(416) (clean refusal); new check N2.

## Remaining failures per file

| File | Result |
|---|---|
| xt_rem_edges.do | ALL PASS apart from CONFIRMED BUG S1 |
| xt_rem_closedform.do | ALL PASS |
| xt_rem_clogit.do | ALL PASS |
| xt_rem_estimation.do | ALL PASS (N1 replay noted; owner decided to add it) |
| xt_rem_options.do | ALL PASS |
| xt_rem_errors.do | ALL PASS apart from CONFIRMED BUG N2 |
| xt_rem_suspected.do | ends r(9) by design: S1 S2 S3 S4 S5 S6 S7 S8 S9 N2 fail (S5 = decided: document; check kept until the help says so or the owner drops it) |
