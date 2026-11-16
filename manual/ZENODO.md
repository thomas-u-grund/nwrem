# Zenodo record for the nwrem manual

Metadata ready to paste into a new Zenodo upload. Nothing has been uploaded, and no DOI exists yet.

**DOI.** TO BE REPLACED: the owner creates the record (a reserved DOI can be obtained before publishing) and tells the all-versions ("Cite all versions") DOI. It goes into `\manualdoi` in `nwrem_manual.tex` (the only place where it is defined) and into the citation texts below. The citation always uses the all-versions DOI (master RELEASING.md B.10). Until then the PDF prints the placeholder `TO-BE-REPLACED`.

**Labelling.** The title and the citation of the manual contain no version number. The Zenodo version label is the series "X.Y" (here "1.4"; internal to Zenodo, not part of the citation), and the description says that the manual describes nwrem X.Y.x. The PDF title page has one line saying which series it describes (`\manualseries`); the exact package version of the examples is `\pkgversion`. The software version is cited separately, as printed by `nwrem version`. A patch release of the package (1.4.1, ...) does not get a new Zenodo version; for a patch only `\pkgversion`, `\pkgdate` and `\corever` change and the PDF is rebuilt and committed.

## Metadata

**Title.** nwrem: Relational event models in Stata. Manual

**Version.** 1.4 (the series label, internal to Zenodo: the manual describes nwrem 1.4.x; not part of the citation)

**Publication date.** The day of the upload.

**Authors.** Grund, Thomas U. (RWTH Aachen University), ORCID 0000-0001-6751-5429 (as on the nwergm record; remove it in the form if the author does not want it).

**Description** (plain text, one paragraph):

> This is the user manual and reference of nwrem, series 1.4 (examples produced with version 1.4.0 and the nwcommands core 3.26.0), a Stata package for relational event models of a sequence of timed events between actors. nwrem builds on the nwcommands core package and implements the relational event framework of Butts (2008) with the R package relevent (version 1.2-1) as its reference. The manual explains the model (the ordinal partial likelihood and the waiting-time likelihood, risk sets, maximum likelihood and posterior mode), gives the syntax of every option, defines every effect (degree, inertia, recency, covariate, triadic and shared-partner effects, fixed effects of the actors and participation shifts), documents the stored results, shows worked examples with output on an e-mail log, compares the estimates with relevent (60 simulated event logs, agreement with the exact maximum of the likelihood of relevent to at least five digits) and states where the program deliberately differs, lists what is not implemented (Bayesian simulation, sampling of the risk set, simulation, goodness-of-fit residuals, covariates that change over time), describes the compiled plugin that evaluates the likelihood, its gradient and its exact Hessian, reports run times against relevent, and gives a translation table from relevent to nwrem. The do-files that produce every listing are in the repository. The package and the manual were prepared with the help of an AI coding assistant working under the author's direction, as stated in the manual.

**License.** Creative Commons Attribution 4.0 International (CC-BY-4.0), as on the nwsaom and nwergm manual records (owner to confirm). The code stays under GPL-3.0-only.

**Resource type.** Publication, sub-type Software documentation (as the nwsaom record).

**Creators.** As on the nwsaom record, with the ORCID (see Authors).

**Keywords.** Stata; nwcommands; nwrem; relational event model; REM; relational events; social network analysis; event history; dynamic networks; relevent

**Language.** English

**Related identifiers.** (relation, identifier, type)

| Relation | Identifier | Type |
|---|---|---|
| Is supplement to | https://github.com/thomas-u-grund/nwrem/releases/tag/v1.4.0 | URL |
| Is supplement to | https://github.com/thomas-u-grund/nwrem | URL |
| Requires | https://github.com/thomas-u-grund/nwcommands | URL |
| Is related to (the manual of the sibling package nwsaom) | 10.5281/zenodo.23623807 | DOI |
| Is related to (the manual of the sibling package nwergm) | 10.5281/zenodo.23661331 | DOI |

Confirm that the GitHub release v1.4.0 is published before the upload, because the first related identifier points to it. The links to the sibling manuals are optional.

**Other fields.** Funding: none. Communities: none. Access: open.

## Steps for the owner

1. Read the points marked `TODO(owner)` in the `.tex` files (`grep -n "TODO(owner)" manual/*.tex`): the test status on Linux and Windows (Sections 1.4 and 8.5 and Chapter 9) and the DOI.
2. On zenodo.org create the record, reserve the DOI, and put its all-versions DOI into `\manualdoi` in `nwrem_manual.tex`.
3. Rebuild (`make -C manual pdf check`) and commit the PDF (`git add -f manual/nwrem_manual.pdf`) on the branch that carries the manual.
4. Upload `manual/nwrem_manual.pdf` to the reserved record, fill the fields above, and publish.
5. Check that the all-versions DOI of the record is the one in `\manualdoi`.
6. For a later patch release (1.4.1, ...) nothing is uploaded. A new Zenodo version only for 1.5 or 2.0 with changed documented behaviour; then change `\manualseries` too.

## Suggested edits after the DOI exists (not made)

Let DOI stand for the all-versions DOI.

1. `README.md` (repository), add a section Manual: "Archived at Zenodo: https://doi.org/DOI".
2. `CITATION.cff`: add a `preferred-citation` as in nwsaom: type manual, title "nwrem: Relational event models in Stata. Manual", author Grund, Thomas U., year 2026, publisher Zenodo, doi DOI.
3. `NOTICE.md`, section How to cite: add the line "Grund, T. U. (2026). nwrem: Relational event models in Stata. Manual. Zenodo. https://doi.org/DOI".
4. Website `nwrem/citation.md`: replace "The package has no DOI" by a sentence giving the manual's citation and the DOI.
5. Website `citing.md`: nwrem leaves the list of packages without a DOI and gets its own entry with the manual citation, as nwsaom has.
6. Website: add the "Manual" menu entry for nwrem (a copy of `website/nwsaom/manual.md` with the nwrem DOI, its own `nav_order`, permalink `/nwrem/manual/`); a dated entry in `news.md`.
7. Master `RELEASING.md` B.10: the sentence "nwdynam and nwrem have no manual" and the C6 text need the nwrem manual.
