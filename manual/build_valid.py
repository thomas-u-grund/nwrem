#!/usr/bin/env python3
"""Reads the log of ex/ex09_validate.do (the comparison with relevent: one line per case) and the reference file of the
repository (cscripts/ref14/results.csv: which cases were also fitted by relevent's rem.dyad()), and writes gen_valid.tex
(the table of Chapter 9) and gen_validnums.tex (numbers used in the text)."""
import re, os, csv, collections
here = os.path.dirname(os.path.abspath(__file__))
log = open(os.path.join(here, "ex", "ex09_validate.log"), errors="replace").read().replace("\n> ", "")
pat = re.compile(r"^(\w+)\s+exact: coef\s+(\S+)\s+se\s+(\S+)\s+ll\s+(\S+)\s+rem\.dyad: coef\s+(\S+)\s+se\s+(\S+)", re.M)
cases = {m.group(1): [float(m.group(i)) for i in range(2, 7)] for m in pat.finditer(log)}
res = list(csv.DictReader(open(os.path.join(here, "..", "cscripts", "ref14", "results.csv"))))
routes = collections.defaultdict(set)
for r in res: routes[r["case"]].add(r["route"])
groups = [
 ("Original effects (degree, inertia, recency)", lambda c: c.startswith("a")),
 ("Waiting-time likelihood, conditioning", lambda c: c.startswith("b")),
 ("Triadic and shared-partner effects (without \\texttt{ospsnd})", lambda c: c.startswith("c_") and not c.startswith("c_osp") and c != "c_all2"),
 ("Symmetric \\texttt{ospsnd}", lambda c: c.startswith("c_osp") or c == "c_all2"),
 ("Fixed effects", lambda c: c.startswith("d_")),
 ("Participation shifts", lambda c: c.startswith("e_")),
 ("Several covariates and covariate networks", lambda c: c.startswith("f_")),
 ("Posterior mode", lambda c: c.startswith("g")),
 ("Risk sets, entry and exit", lambda c: c.startswith("h_")),
]
def fmt(x): return "--" if x is None else ("$<10^{-12}$" if x < 1e-12 else "$%s$" % ("%.1e" % x).replace("e-0", "\\cdot 10^{-").replace("e-", "\\cdot 10^{-") + "}")
rows = []
tot = 0; totd = 0
for name, f in groups:
    cs = sorted(c for c in cases if f(c))
    d = [c for c in cs if "dyad" in routes[c]]
    tot += len(cs); totd += len(d)
    mx = lambda idx, L: (max(cases[c][idx] for c in L) if L else None)
    # cases[c] = [coef, se, ll, dcoef, dse]
    rows.append("%s & %d & %.1e & %.1e & %.1e & %s \\\\" % (name, len(cs), mx(0, cs), mx(1, cs), mx(2, cs),
                ("%d: %.1e" % (len(d), max(max(cases[c][3], cases[c][4]) for c in d))) if d else "--"))
def tex(s): return re.sub(r"([0-9.]+)e-0?(\d+)", r"$\1\\cdot10^{-\2}$", s)
out = "\\begin{tabular}{@{}p{5.6cm}rrrrr@{}}\\toprule\n& & \\multicolumn{3}{c}{Exact route} & \\texttt{rem.dyad()}\\\\\n& Cases & coef. & s.e. & log lik. & cases: dev.\\\\\\midrule\n"
out += "\n".join(tex(r) for r in rows) + "\n\\bottomrule\\end{tabular}\n"
open(os.path.join(here, "gen_valid.tex"), "w").write(out)
open(os.path.join(here, "gen_validnums.tex"), "w").write("\\newcommand{\\nvalcases}{%d}\\newcommand{\\nvaldyad}{%d}\n" % (tot, totd))
print(tot, totd); print(out)
