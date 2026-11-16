#!/usr/bin/env python3
"""Writes gen_timing.tex (the table of Chapter 10) from timing_linux.csv, which holds the cells of the run-time comparison of
nwrem 1.4.0 with relevent 1.2-1 on Linux (16 November 2026). A dash means that relevent did not finish within 600 seconds or was not run
because it had timed out in a smaller cell of the same effect set."""
import csv, os
here = os.path.dirname(os.path.abspath(__file__))
names = {"S1": "two degree effects", "S2": "four degree effects", "S3": "four degree and two inertia effects",
         "S4": "two degree and two recency effects", "S5": "two degree and three covariate effects"}
rows = list(csv.DictReader(open(os.path.join(here, "timing_linux.csv"))))
out = ["\\begin{longtable}{@{}llrrrrr@{}}", "\\toprule", "Set & Events, actors & \\nwrem{} (s) & \\relevent{}, Hessian (s) & \\relevent{}, no Hessian (s) & \\multicolumn{2}{c}{Ratio with / without}\\\\", "\\midrule\\endhead"]
last = None
def tex(x): return x.replace("n.r.", "n.r.")
for r in rows:
    ev = "{:,}".format(int(r["events"])).replace(",", "\\,")
    ratio = [t.strip() for t in r["ratio_with_without"].split("/")]
    ratio = [t.replace(",", "\\,") for t in ratio]
    s = r["set"] if r["set"] != last else ""
    if r["set"] != last and last is not None: out.append("\\addlinespace")
    last = r["set"]
    out.append("%s & %s, %s & %s & %s & %s & %s & %s\\\\" % (s, ev, r["actors"], r["nwrem_s"], r["relevent_hessian_s"].replace("-", "--"), r["relevent_nohessian_s"].replace("-", "--"), ratio[0], ratio[1]))
out += ["\\bottomrule", "\\end{longtable}"]
open(os.path.join(here, "gen_timing.tex"), "w").write("\n".join(out) + "\n")
