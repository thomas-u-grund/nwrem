import csv, statistics as st, sys, collections, io
B=sys.argv[1]
def rows(f):
    try: return list(csv.reader(open(B+'/'+f)))
    except FileNotFoundError: return []
R=collections.defaultdict(list); Rc={}
for r in rows('R_times_all.csv')[1:]:
    size,sn,hess,rep,secs,ok,coef,names=r
    if hess=='TRUE' and ok=='TRUE':
        R[(size,sn)].append(float(secs)); Rc[(size,sn)]=dict(zip([x.lower().split(".")[0] for x in names.split()],map(float,coef.split())))
RT={}
for f in ['R_times_big.csv']:
    for r in rows(f):
        if len(r)<6: continue
        size,sn,rep,secs,coef,names=r[:6]
        if secs.startswith('TIMEOUT'): RT[(size,sn)]='timeout'; continue
        R[(size,sn)].append(float(secs)); Rc[(size,sn)]=dict(zip([x.lower().split(".")[0] for x in names.split()],map(float,coef.split())))
N=collections.defaultdict(list); Nc=collections.defaultdict(list); NT={}
for f in ['nw_times_s17_partial.csv','nw_times_e20k17.csv']:
    for r in rows(f):
        if len(r)<7: continue
        size,sn,rep,secs,coef,names=r[:6]
        if secs.startswith('TIMEOUT'):
            if size=='e20000' and f.startswith('nw_times_s17'): continue
            NT[(size,sn)]='timeout'; continue
        N[(size,sn)].append(float(secs))
        Nc[(size,sn)].append(dict(zip([x.split('_')[0] for x in names.split()],map(float,coef.split()))))
out=[]
for size in ['e200','e1000','e5000','e20000']:
    for sn in ['S1_nodsnd_nidrec','S2_degree4','S3_degree4_inertia','S4_recency','S5_covariates']:
        k=(size,sn)
        rt=R.get(k); nt=N.get(k)
        rs = ('%.2f (n=%d)'%(st.median(rt),len(rt))) if rt else RT.get(k,'-')
        ns = ('%.2f (n=%d)'%(st.median(nt),len(nt))) if nt else NT.get(k,'-')
        ratio = '%.2f'%(st.median(rt)/st.median(nt)) if rt and nt else ('>%.1f'%(600/st.median(nt)) if nt and RT.get(k)=='timeout' else '-')
        dif='-'
        if k in Rc and Nc.get(k):
            d=0
            for c in Nc[k]:
                for nm,v in c.items(): d=max(d,abs(v-Rc[k][nm]))
            dif='%.1e'%d
        out.append((size,sn,rs,ns,ratio,dif))
print('size set R_median_s nwrem_median_s ratio(R/nwrem) max|coef diff|')
for o in out: print(*o)
