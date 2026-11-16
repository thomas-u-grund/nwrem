# Build of the manual.  make pdf     : the tables are regenerated (comparison with relevent from the log of ex/ex09_validate.do, run times from timing_linux.csv), the PDF is built (3 passes)
#                      make examples: reruns the do-files of ex/ in Stata 17 (needs NWCORE=/path/to/nwcommands and Stata; about 5 minutes)
#                      make check   : undefined references, overfull boxes, glued words
# The PDF is committed with git add -f (the LaTeX build files and the Stata logs are ignored).
all: pdf

tables:
	python3 build_valid.py
	python3 build_timing.py

pdf: tables
	pdflatex -interaction=nonstopmode nwrem_manual.tex
	pdflatex -interaction=nonstopmode nwrem_manual.tex
	pdflatex -interaction=nonstopmode nwrem_manual.tex

examples:
	./run_examples.sh

check:
	python3 check_layout.py

clean:
	rm -f *.aux *.log *.toc *.out *.bbl *.blg *.lof *.lot
