#!/usr/bin/env python3
"""Cuts the Stata logs of the example do-files into the listings that the manual includes.
A do-file marks a piece with a line  *# name ; the log text between that marker and the next one is written to out/name.txt.
Paths of the machine that ran the examples are replaced by the usual place of an installed package."""
import glob, os, re
here = os.path.dirname(os.path.abspath(__file__))
os.makedirs(os.path.join(here, "out"), exist_ok=True)
n = 0
for log in sorted(glob.glob(os.path.join(here, "ex*.log"))):
    cur, buf = None, []
    def flush():
        global n
        if cur and cur != "end":
            while buf and not buf[0].strip(): buf.pop(0)
            while buf and (not buf[-1].strip() or buf[-1].strip() == "."): buf.pop()
            with open(os.path.join(here, "out", cur + ".txt"), "w") as f:
                f.write("\n".join(buf) + "\n")
            n += 1
    for line in open(log, encoding="utf-8", errors="replace").read().split("\n"):
        m = re.match(r"^\. \*# (\w+)\s*$", line)
        if m:
            flush(); cur, buf = m.group(1), []
            continue
        if line.startswith("end of do-file"): continue
        buf.append(line)
    flush()
# the examples are run from a scratch checkout; show the usual place of an installed package where a listing prints the plugin path
fv = os.path.join(here, "out", "st_version.txt")
if os.path.exists(fv):
    t = open(fv).read()
    t = re.sub(r"native plugin\s+: .*?no separate version number\)", "native plugin           : ~/Library/Application Support/Stata/ado/plus/r/rem_sim_macos.plugin\n> (ships with the package, no separate version number)", t, flags=re.S)
    open(fv, "w").write(t)
# a short extract of the two validation logs: the first case lines and the summary lines
out = []
pat = re.compile(r"^\w+\s+exact: coef.*$")
for name in ("va_relevent", "va_collinear"):
    f = os.path.join(here, "out", name + ".txt")
    if not os.path.exists(f): continue
    t = open(f).read().replace("\n> ", "")
    cases = [l for l in t.split("\n") if pat.match(l)]
    pas = [l.strip() for l in t.split("\n") if "PASS" in l and "di as text" not in l] + [l for l in t.split("\n") if l.startswith("test_nwrem")]
    cols = [l for l in t.split("\n") if re.match(r"^col\d+\s+parameters", l)]
    def cols_(l):
        m = re.match(r"^(\w+)\s+exact: coef\s+(\S+)\s+se\s+(\S+)\s+ll\s+(\S+)\s+rem\.dyad: coef\s+(\S+)\s+se\s+(\S+)", l)
        return "%-6s %9s %9s %9s  |  %9s %9s" % m.groups()
    if name == "va_relevent": out += [". test_nwrem_relevent14   (the first 10 of the %d case lines, in columns)" % len(cases), "case   exact route: coef, se, log lik.  |  rem.dyad(): coef, se"] + [cols_(l) for l in cases[:10]] + [""] + pas + [""]
    else: out += [". " + "test_nwrem_collinear14  (the first 5 of the %d case lines)" % len(cols)] + cols[:5] + [""] + pas
open(os.path.join(here, "out", "va_summary.txt"), "w").write("\n".join(out) + "\n")
print("listings written:", n)
