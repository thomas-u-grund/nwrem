do setup.doh
do mail.doh
nwrem mail, nodsnd nidrec frpsndsnd frrecsnd
*# es_rank
estat rank, noplot
*# es_rank5
estat rank, topk(5) noplot
display "mean rank " %6.2f r(mean_rank) ", median " r(median_rank) ", share in the top 10: " %5.3f r(hit) " (null " %5.3f r(hit_null) ")"
*# es_actors
estat actors, role(sender) noplot
*# es_actors_list
estat actors, role(sender) noplot
matrix A = r(actors)
matrix B = A[1..6,1..4]
matrix list B, format(%9.2f)
*# es_time
estat time, bins(8) noplot
*# es_timeret
matrix list r(bins), format(%9.2f)
*# es_graphs
quietly {
estat rank, name(rk) export(../fig/es_rank.pdf) title("") xsize(4.2) ysize(3.2)
estat rank, plot(hist) bins(20) name(rkh) export(../fig/es_rankhist.pdf) title("") xsize(4.2) ysize(3.2)
estat actors, role(sender) name(acs) export(../fig/es_actors.pdf) title("") xsize(3.6) ysize(2.8)
estat actors, name(acb) export(../fig/es_actors2.pdf) title("") xsize(6.4) ysize(3.4)
estat time, bins(8) name(tm) export(../fig/es_time.pdf) title("") xsize(4.2) ysize(3.2)
}
graph dir
*# es_conv
quietly estat rank, name(rk2) saving(../fig/rank_demo) export(../fig/rank_demo.png, width(1200)) scheme(s2color)
*# es_err
capture noisily estat rank, noplot name(x)
display "return code " _rc
capture noisily estat rank, noplot title("x")
display "return code " _rc
*# es_pre
quietly nwwebuse manufacturing, nwclear
quietly levelsof sender, local(a) clean
quietly levelsof receiver, local(b) clean
global allact : list a | b
quietly keep if t < 5
quietly duplicates drop t, force
scalar unit = (5 - 3.2) * 144 * 143 / 628
quietly replace t = (t - 3.2) / unit
quietly do buildnet.doh
quietly nwbuild mail2
quietly nwrem mail2, nodsnd nidrec frpsndsnd interval starttime(0) endtime(`=(5 - 3.2) / unit')
*# es_interval
estat time, bins(8) noplot
quietly estat time, bins(8) name(tmi) export(../fig/es_timeint.pdf) title("") xsize(4.2) ysize(3.2)
*# end
