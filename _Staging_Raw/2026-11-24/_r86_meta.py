import json,urllib.request,urllib.parse,time
TOK=open(r"C:\Library\_tools\.gh_token").read().strip()
H={"User-Agent":"daoli/1.0","Authorization":"Bearer "+TOK,"Accept":"application/vnd.github+json"}
def get(u):
    try: return json.loads(urllib.request.urlopen(urllib.request.Request(u,headers=H),timeout=25).read().decode())
    except urllib.error.HTTPError as e: return {"err":e.code}
    except Exception as e: return {"err":str(e)}
REPOS=["mod-bee/modbee-openplc","Chenjie1002/Lee_Workshop","brentjm/chemical-process-digital-twin","simatic-ax/LAxisCtrl","DavidWenzler/reAM250","Aneesh495/gantry"]
out={}
for r in REPOS:
    m=get("https://api.github.com/repos/"+r)
    if m.get("err"): out[r]={"err":m["err"]}; print(r,"ERR",m["err"]); continue
    lic=(m.get("license") or {}).get("spdx_id")
    t=get("https://api.github.com/repos/%s/git/trees/%s?recursive=1"%(r,m.get("default_branch","HEAD")))
    files=[x["path"] for x in t.get("tree",[]) if x.get("type")=="blob" and x["path"].lower().endswith((".st",".scl",".tcpou",".tcdut",".iecst",".exp"))]
    out[r]={"spdx":lic,"branch":m.get("default_branch"),"stars":m.get("stargazers_count"),"n_st":len(files),"st":files[:40],"size":m.get("size")}
    print("%-45s spdx=%-14s stars=%-4s st=%d"%(r,lic,m.get("stargazers_count"),len(files)))
    time.sleep(1)
json.dump(out,open("_r86_meta.json","w",encoding="utf-8"),ensure_ascii=False,indent=1)
