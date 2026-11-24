# -*- coding: utf-8 -*-
import os,re,json
LIB=r"C:\Library"
rows=json.load(open(os.path.join(LIB,"_tmp_r84","dedup_raw.json"),encoding="utf-8"))
def strip_comments(s):
    s=re.sub(r"\(\*.*?\*\)","",s,flags=re.S)
    s=re.sub(r"//[^\n]*","",s)
    return s
for r in rows:
    p=os.path.join(LIB,r["cat"],r["name"]+".st")
    src=open(p,encoding="utf-8",errors="replace").read()
    raw=src.split("\n")
    body=strip_comments(src)
    lines=body.split("\n")
    flags=[]
    # divisions
    for i,l in enumerate(lines,1):
        for m in re.finditer(r"[^/]/[^/*]",l):
            # get context window previous 3 lines
            ctx=" ".join(lines[max(0,i-4):i])
            if re.search(r"ABS\s*\(",ctx,re.I) or re.search(r"1\.0E-9|1\.0E-09|1E-9|EPS",ctx,re.I):
                pass
            else:
                flags.append(f"DIV {i}: {l.strip()[:90]}")
    # TON / R_TRIG / arrays
    for i,l in enumerate(lines,1):
        if re.search(r"\b(TON|TOF|TP|R_TRIG|F_TRIG)\b\s*\(",l) and not re.match(r"^\s*(VAR|END_VAR|\(\*)",l):
            ind=len(l)-len(l.lstrip())
            flags.append(f"TIMER {i} (indent {ind}): {l.strip()[:80]}")
        if re.search(r"\[\s*[A-Za-z_]\w*\s*\]",l) and "ARRAY" not in l.upper() and ":" not in l:
            flags.append(f"IDX {i}: {l.strip()[:80]}")
    # elseif/else structure & gotos
    print("=====",r["name"],r["kind"],"lines",len(raw))
    for f in flags: print("   ",f)
