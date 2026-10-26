#!/bin/zsh
export BENCH
RES=$BENCH/R_times_$1.csv; : > $RES
for size in ${(s:,:)2}; do
 for set in S1_nodsnd_nidrec S2_degree4 S3_degree4_inertia S4_recency S5_covariates; do
  reps=5; [[ $size == e20000 ]] && reps=3
  for rep in $(seq 1 $reps); do
   out=$(cd $BENCH && perl -e 'alarm 600; exec @ARGV' /usr/local/bin/Rscript R_one.R $size $set $rep 2>/dev/null)
   if [[ -z $out ]]; then echo "$size,$set,$rep,TIMEOUT600,," >> $RES; echo "$size $set $rep TIMEOUT load $(sysctl -n vm.loadavg)"; break; fi
   echo $out >> $RES; t=$(echo $out | cut -d, -f4); echo "$size $set $rep $t load $(sysctl -n vm.loadavg)"
   if (( $(echo $t | awk '{print ($1>200)?1:0}') )); then break; fi
  done
 done
done
