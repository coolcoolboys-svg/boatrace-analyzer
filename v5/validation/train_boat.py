import json, numpy as np
from scipy.optimize import minimize

raw=json.load(open('boat_training_sample.json'))
priors=np.array([[55,13.5,12.8,10.6,6.1,1.9],[17.5,25.1,21.8,17,12.6,6.3],[8.8,18.7,19.9,20.2,18.5,13.9]])
grade=np.array([1.16,1.07,.97,.82])
def num(x,default):
    return float(x) if x is not None and np.isfinite(float(x)) else default
def features(b):
    g=int(num(b[1],0)); nat=num(b[2],30); motor=num(b[3],35); st=num(b[4],.15); ex=num(b[5],6.85)
    # Keep zero as supplied to match the existing v4.2 data handling.
    if ex<=0: ex=6.85
    return [np.log(grade[g-1]) if 1<=g<=4 else 0,np.clip((nat-30)*.012,-.55,.55),np.clip((motor-35)*.012,-.4,.4),np.clip((.15-st)*2.5,-.35,.35),np.clip((6.85-ex)*2.2,-.4,.4)]
def prepare(r):
    b=sorted(r['b'],key=lambda x:x[0]); y=np.array([int(n)-1 for n in r['y'].split('-')]);
    if len(b)!=6 or [x[0] for x in b]!=list(range(1,7)) or len(set(y))!=3: return None
    return np.array([features(x) for x in b]),y
rows=[(r['d'],prepare(r)) for r in raw]; rows=[(d,x,y) for d,z in rows if z is not None for x,y in [z]]
train=[r for r in rows if r[0]<'20260000']; valid=[r for r in rows if '20260000'<r[0]<'20260900']; test=[r for r in rows if r[0]>='20260900']
def prepare_stage(rows,stage):
    x=np.array([r[1] for r in rows]); y=np.array([r[2][stage] for r in rows]); mask=np.ones((len(rows),6),bool)
    for p in range(stage): mask[np.arange(len(rows)),np.array([r[2][p] for r in rows])]=False
    return x,y,mask
def fit(rows,reg):
    params=[]
    for stage in range(3):
        x,y,mask=prepare_stage(rows,stage); offsets=np.log(priors[stage]); ids=np.arange(len(rows))
        def objective(coef):
            a=offsets+np.einsum('nif,f->ni',x,coef);a=np.where(mask,a,-1e6);mx=a.max(axis=1,keepdims=True);e=np.exp(a-mx);p=e/e.sum(axis=1,keepdims=True)
            loss=np.mean(np.log(e.sum(axis=1))+mx[:,0]-a[ids,y])+reg*np.sum(coef**2)/2
            p[ids,y]-=1; grad=np.einsum('ni,nif->f',p,x)/len(rows)+reg*coef
            return loss,grad
        fit=minimize(objective,np.ones(5),jac=True,method='L-BFGS-B');params.append(fit.x.tolist())
    return np.array(params)
def evaluate(rows,coef):
    N=len(rows); sums=0.;hits=0; top1=0
    for _,x,y in rows:
        score=np.exp(np.log(priors)+np.einsum('if,pf->pi',x,coef)); probs=[]; actual=0
        for a in range(6):
            for b in range(6):
                if a==b:continue
                for c in range(6):
                    if c in (a,b):continue
                    p=score[0,a]/sum(score[0])*score[1,b]/(sum(score[1])-score[1,a])*score[2,c]/(sum(score[2])-score[2,a]-score[2,b]);probs.append(p)
                    if (a,b,c)==tuple(y): actual=p
        rank=1+sum(v>actual for v in probs);hits+=rank<=10;top1+=rank==1;sums-=np.log(max(actual,1e-15))
    return {'n':N,'logloss':sums/N,'top10':hits/N,'top1':top1/N}
baseline=np.ones((3,5)); candidates=[]
for reg in [.001,.01,.1]:
    model=fit(train,reg); candidates.append((evaluate(valid,model)['logloss'],reg,model))
_,reg,model=min(candidates,key=lambda x:x[0]);out={'counts':{'train':len(train),'validation':len(valid),'test':len(test)},'reg':reg,'coefficients':model.tolist(),'validation':{'baseline':evaluate(valid,baseline),'learned':evaluate(valid,model)},'test':{'baseline':evaluate(test,baseline),'learned':evaluate(test,model)}}
open('boat_validation.json','w').write(json.dumps(out,ensure_ascii=False,indent=2));print(json.dumps(out,ensure_ascii=False,indent=2))
