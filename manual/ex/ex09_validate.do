do setup.doh
* the test scripts of the repository run from its root
local nwrem : env NWREM
quietly cd "`nwrem'"
*# va_relevent
do cscripts/test_nwrem_relevent14.do
*# va_collinear
do cscripts/test_nwrem_collinear14.do
