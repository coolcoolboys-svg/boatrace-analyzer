import json,time,urllib.request,datetime
BASE='https://boatraceopenapi.github.io'
records=[]; failures=[]
for year in range(2023,2027):
    for month in range(1,13):
        if (year==2023 and month<5) or (year==2026 and month>10): continue
        for day in (1,15):
            date=f'{year:04}{month:02}{day:02}'
            try:
                data=[]
                for source in ('programs','previews','results'):
                    url=f'{BASE}/{source}/v3/{year}/{date}.json'
                    req=urllib.request.Request(url,headers={'User-Agent':'boat-analysis-research/1.0'})
                    with urllib.request.urlopen(req,timeout=60) as response: data.append(json.load(response)[source])
                    time.sleep(.1)
                programs,previews,results=data
                prev={(p['stadium_number'],p['number']):p for p in previews}
                res={(p['stadium_number'],p['number']):p for p in results}
                for p in programs:
                    k=(p['stadium_number'],p['number']); t=prev.get(k); r=res.get(k)
                    if not t or not r or len(p.get('boats',[]))!=6 or len(t.get('boats',[]))!=6: continue
                    pay=r.get('payouts',{}).get('trifecta',[])
                    if len(pay)!=1: continue
                    combo=pay[0].get('combination',''); bits=combo.split('-')
                    if len(bits)!=3 or len(set(bits))!=3 or any(x not in '123456' for x in bits):continue
                    entries=[]
                    for b in p['boats']:
                        e=next((q for q in t['boats'] if q.get('racer_boat_number')==b.get('racer_boat_number')), {})
                        entries.append([b.get('racer_boat_number'),b.get('racer_class_number'),b.get('racer_national_top_2_percent'),b.get('racer_assigned_motor_top_2_percent'),b.get('racer_average_start_timing'),e.get('racer_exhibition_time'),e.get('racer_course_number')])
                    records.append({'d':date,'v':p['stadium_number'],'b':entries,'y':combo})
            except Exception as e:
                failures.append({'date':date,'error':str(e)})
            print(date,len(records),flush=True)
open('boat_training_sample.json','w',encoding='utf-8').write(json.dumps(records,ensure_ascii=False))
open('collection_errors.json','w',encoding='utf-8').write(json.dumps(failures,ensure_ascii=False,indent=2))
if failures: raise SystemExit(f'{len(failures)} dates failed; see collection_errors.json')
