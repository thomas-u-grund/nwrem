*! version 1.0.3  25oct2026 _nwrem_libcheck - make the nwrem Mata library visible
* Copyright (C) 2026 Thomas U. Grund
* This file is part of nwrem (GPL-3, see the file LICENSE).
* Stata indexes the Mata libraries (.mlib) once, early in a session. A library installed by net install can be missing from that
* index (then Mata stops with r(3499) "<function>() not found"). nwrem calls this program first: when a function of its library is
* not visible, it runs -mata mlib index- once.
capture program drop _nwrem_libcheck
program define _nwrem_libcheck
	version 14
	capture mata: mata which rem_rank_reciprocal()
	if _rc {
		capture mata: mata mlib index
	}
end
