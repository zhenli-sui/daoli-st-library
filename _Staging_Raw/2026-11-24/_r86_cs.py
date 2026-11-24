import json,urllib.request,urllib.parse,time,os
TOK=open(r"C:\Library\_tools\.gh_token").read().strip()
def cs(q,per=20):
    u="https://api.github.com/search/code?q=%s&per_page=%d"%(urllib.parse.quote(q),per)
    r=urllib.request.Request(u,headers={"User-Agent":"daoli/1.0","Authorization":"Bearer "+TOK,"Accept":"application/vnd.github+json"})
    try:
        return json.loads(urllib.request.urlopen(r,timeout=25).read().decode())
    except urllib.error.HTTPError as e:
        return {"err":e.code,"q":q}
    except Exception as e:
        return {"err":str(e),"q":q}
QS=['"FUNCTION_BLOCK" valve AND seat AND stroke',
    '"FUNCTION_BLOCK" gear AND ratio AND sync',
    '"FUNCTION_BLOCK" flying AND shear',
    '"FUNCTION_BLOCK" reactor AND jacket',
    '"FUNCTION_BLOCK" unit AND conversion AND factor',
    '"FUNCTION_BLOCK" bit AND shift AND mask']
out={}
for q in QS:
    d=cs(q)
    if "err" in d: out[q]={"err":d["err"]}
    else:
        items=[{"repo":i["repository"]["full_name"],"path":i["path"]} for i in d.get("items",[])]
        out[q]={"total":d.get("total_count"),"items":items}
    print(q,"->",out[q].get("total",out[q].get("err")))
    time.sleep(7)
json.dump(out,open("_r86_cs.json","w",encoding="utf-8"),ensure_ascii=False,indent=1)
