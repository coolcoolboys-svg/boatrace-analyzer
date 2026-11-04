import json,itertools,numpy as np
from scipy.optimize import minimize
exec(open('train_boat.py').read().split('baseline=np.ones')[0])
P=np.array(list(itertools.permutations(range(6),3))); A,B,C=P.T
# One shared coefficient and one shrunk deviation for each boat number

def expand(x):
 n=len(x); return np.concatenate([x, (x[:,:,:,None]*np.eye(6)[None,:,None,:]).reshape(n,6,30)],2)
def fit_model(reg):
 out=[]
 for k in range(3):
  x,y,mask=prepare_stage(train,k); x=expand(x); ids=np.arange(len(y)); penalty=np.r_[np.repeat(.001,5),np.repeat(reg,30)]
  def fn(beta):
   z=np.einsum('nif,f->ni',x,beta)+np.log(priors[k]);z=np.where(mask,z,-1e6);mx=z.max(1,keepdims=True);e=np.exp(z-mx);p=e/e.sum(1,keepdims=True)
   loss=np.mean(np.log(e.sum(1))+mx[:,0]-z[ids,y])+np.dot(penalty,beta**2)/2
   p[ids,y]-=1; return loss,np.einsum('ni,nif->f',p,x)/len(y)+penalty*beta
  out.append(minimize(fn,np.r_[np.ones(5),np.zeros(30)],jac=True,method='L-BFGS-B',options={'maxiter':400}).x)
 return np.array(out)
def ev(rows,model):
 x=expand(np.array([r[1] for r in rows])); y=np.array([r[2] for r in rows]);scores=np.exp(np.log(priors)[None,:,:]+np.einsum('nif,pf->npi',x,model));s=scores
 p=s[:,0,A]/s[:,0,:].sum(1)[:,None]*s[:,1,B]/(s[:,1,:].sum(1)[:,None]-s[:,1,A])*s[:,2,C]/(s[:,2,:].sum(1)[:,None]-s[:,2,A]-s[:,2,B]);ai=(y[:,None,:]==P[None,:,:]).all(2).argmax(1);actual=p[np.arange(len(y)),ai];rank=1+(p>actual[:,None]).sum(1)
 return {'n':len(y),'hits':int((rank<=10).sum()),'top10':float((rank<=10).mean()),'logloss':float(-np.log(actual).mean())}
results=[]
for reg in [.001,.01,.1]:
 m=fit_model(reg);r={'reg':reg,'validation':ev(valid,m),'coef':m.tolist()};results.append(r); print(reg,r['validation'],flush=True)
# select using validation logloss only, preserve holdout until choice
best=min(results,key=lambda r:r['validation']['logloss']); baseline=np.array(json.load(open('boat_validation.json'))['coefficients']); base=np.concatenate([baseline,np.zeros((3,30))],axis=1)
summary={'candidates':[{'reg':r['reg'],'validation':r['validation']} for r in results],'selected':best['reg'],'coefficients':best['coef'],'baseline_test':ev(test,base),'candidate_test':ev(test,np.array(best['coef']))}
open('course_comparison.json','w').write(json.dumps(summary,ensure_ascii=False,indent=2));print('holdout',summary['baseline_test'],summary['candidate_test'])
