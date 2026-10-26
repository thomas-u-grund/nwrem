#!/bin/zsh
# usage: run_nwrem.sh <stata> <tag> <sizes csv> ; env NWCORE NWTREE BENCH
STATA=$1; TAG=$2; SIZES=${3:-e200,e1000,e5000,e20000}
export BENCH NWTREE
RES=$BENCH/nw_times_$TAG.csv; : > $RES
P=$(mktemp -d /private/tmp/claude-501/plusb.XXXX)
for size in ${(s:,:)SIZES}; do
 reps=5; [[ $size == e20000 ]] && reps=3
 for set in S1_nodsnd_nidrec S2_degree4 S3_degree4_inertia S4_recency S5_covariates; do
  for rep in $(seq 1 $reps); do
   export SIZE=$size SET=$set REP=$rep OUT=$BENCH/one_$TAG.csv
   rm -f $OUT
   cat > $P/d.do <<DO
capture program drop nwinstall
sysdir set PLUS "$P"
adopath ++ "$NWCORE"
adopath ++ "$NWCORE/lib"
adopath ++ "$NWCORE/lib/plugins/macos"
do $BENCH/nwrem_one.do
DO
   cd $BENCH
   t0=$(date +%s)
   perl -e 'alarm 600; exec @ARGV' "$STATA" -e do $P/d.do > /dev/null 2>&1
   rc=$?
   if [[ -s $OUT ]]; then cat $OUT >> $RES; else echo "$size,$set,$rep,TIMEOUT_OR_ERROR,,,,\"\"" >> $RES; fi
   echo "$size $set $rep $(tail -1 $RES | cut -d, -f4) load: $(sysctl -n vm.loadavg)"
   last=$(tail -1 $RES | cut -d, -f4)
   if [[ $last == TIMEOUT* ]]; then break; fi
   if (( $(echo "$last" | awk '{print ($1>200)?1:0}') )) && (( rep >= 3 )); then break; fi
  done
 done
done
