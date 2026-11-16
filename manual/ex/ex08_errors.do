do setup.doh
quietly do mail.doh
*# er_noeffect
capture noisily nwrem mail
display "return code: " _rc
*# er_ridge
nwrem mail, nodsnd nidsnd ntdegsnd
display "unidentified: " e(unidentified)
*# er_options
capture noisily nwrem mail, nodsnd starttime(3)
display "return code: " _rc
capture noisily nwrem mail, nodsnd priorscale(2)
display "return code: " _rc
capture noisily nwrem mail, nodsnd condition(-1)
display "return code: " _rc
capture noisily nwrem mail, nodsnd seed(-1)
display "return code: " _rc
*# er_notevent
nwrandom 8, prob(.3) name(ordinary)
capture noisily nwrem ordinary, nodsnd
display "return code: " _rc
*# er_cov
capture noisily nwrem mail, covsnd(nosuchvar)
display "return code: " _rc
capture noisily nwrem mail, covevent(ordinary)
display "return code: " _rc
*# er_selfloop
clear
input sender receiver t
1 2 1
2 2 2
1 3 3
3 1 4
end
nwset sender receiver, directed eventtime(t) name(loop)
capture noisily nwrem loop, nodsnd
display "return code: " _rc
