cscript

* Long messages wrap at word boundaries (1.0.11). Stata cuts a display line that is longer than the linesize at exactly that
* column, in the middle of a word ("... temporal netw" / "> ork) ..."); the messages are now SMCL paragraphs. The test sets
* linesize 80 (as in the book), triggers an error and the note on unidentified effects, and checks the log text.

local nwcore : env NWCORE
if `"`nwcore'"' == "" {
	di as error "set the environment variable NWCORE to the directory of the nwcommands (core) package"
	exit 198
}
adopath ++ `"`nwcore'"'
adopath ++ `"`c(pwd)'"'
quietly do `"`nwcore'/unw_core.do"'
do unw_rem.do
global nwwebpath `"`nwcore'/data"'

* _mw_check logfile "message": the message must appear in the log, joined from its output lines (trimmed, joined with one
* space) exactly as written, on at least two lines, none longer than the linesize and none a hard-wrap continuation ("> ").
capture program drop _mw_check
program _mw_check
	args logf msg
	local start = substr(`"`macval(msg)'"', 1, 30)
	tempname fh
	local found 0
	local nl 0
	local hard 0
	local toolong 0
	local joined ""
	file open `fh' using `"`logf'"', read text
	file read `fh' line
	while r(eof) == 0 {
		if `found' == 1 & strlen(`"`macval(joined)'"') < strlen(`"`macval(msg)'"') {
			if substr(`"`macval(line)'"', 1, 2) == "> " local hard 1
			if strlen(`"`macval(line)'"') > 80 local toolong 1
			local t = trim(`"`macval(line)'"')
			local joined `"`macval(joined)' `macval(t)'"'
			local ++nl
		}
		if `found' == 0 & strpos(trim(`"`macval(line)'"'), `"`macval(start)'"') == 1 {
			local found 1
			if strlen(`"`macval(line)'"') > 80 local toolong 1
			local joined = trim(`"`macval(line)'"')
			local nl 1
		}
		file read `fh' line
	}
	file close `fh'
	di as text "  lines: `nl'  hard wrap: `hard'  too long: `toolong'"
	assert `found' == 1
	assert `nl' >= 2
	assert `hard' == 0
	assert `toolong' == 0
	assert `"`macval(joined)'"' == `"`macval(msg)'"'
	di as text "  PASS: wraps at word boundaries: " substr(`"`macval(msg)'"', 1, 50) "..."
end

set linesize 80
tempfile l1 l2

* 1. error: a network that is not an event network
nwclear
clear
mata: rseed(4); R = runiform(10, 10) :< 0.2; R = R :* (1 :- I(10)); st_matrix("A", R)
nwset, mat(A) name(static) nooutput
log using `l1', text replace name(mw1)
capture noisily nwrem static, nodsnd
local rc = _rc
log close mw1
assert `rc' == 198
_mw_check `l1' "nwrem requires a network declared via nwset's eventtime() option (an event-type temporal network) - see nwset."

* 2. note: effects that are not identified (ntdegsnd = (nodsnd + nidsnd)/2)
nwclear
nwwebuse socialevolution, nwclear
nwset sender receiver, eventtime(t) directed name(ev)
log using `l2', text replace name(mw2)
nwrem ev, nodsnd nidsnd ntdegsnd seed(1)
log close mw2
_mw_check `l2' "These effects are not identified: typically an effect is an exact function of others in the model (the total-degree share ntdegsnd is half the sum of nodsnd and nidsnd). Its estimate is arbitrary; drop one of the effects."

di as result "ALL TESTS PASSED"
