# -*- coding: utf-8 -*-
import json,io,os,datetime
T=json.load(io.open('_Staging_Raw/2026-11-25/r93_targets.json',encoding='utf-8'))
REJ={'FC_DL_ShakeoutCoolingTimeCalc'}
T=[t for t in T if t['name'] not in REJ]
reg=json.load(io.open('INDEX_REGISTRY.json',encoding='utf-8'))
items = reg if isinstance(reg,list) else reg.get('components',reg.get('items',[]))
now=datetime.datetime.now().astimezone().replace(microsecond=0).isoformat()
added=[]
for t in T:
    p=os.path.join(t['category'],t['name']+'.st')
    if not os.path.exists(p): print("MISSING",p); continue
    src=io.open(p,encoding='utf-8').read()
    lc=len(src.splitlines())
    e={"name":t['name'],"category":t['category'],"type":"FB" if t['prefix']=='FB_DL' else "FC",
       "file_path":"C:\Library\\"+t['category']+"\\"+t['name']+'.st',
       "function_tags":[t['category'].lower().replace('dl_',''),"r93","factory",
                        "port-crane" if t['no']<=10 else ("tobacco-primary" if t['no']<=20 else ("data-center-cooling" if t['no']<=30 else "foundry-sand")),
                        t['prefix'].lower()],
       "complexity":int(t['cmplx'][1]),"version":"1.0.0","registered_at":now,"line_count":lc,
       "code_segment":"","source":"r93-plan",
       "origin":{"mode":"internal","source":"道莅原创（clean-room 自研，行业工艺公式）","license":"MIT","ref_tag":"R93-V"},
       "l2_status":"l2-pass","round":"R93","description":t['func']}
    items.append(e); added.append((e,src))
if isinstance(reg,dict):
    for k in ('components','items'):
        if k in reg: reg[k]=items; break
else: reg=items
json.dump(reg,io.open('INDEX_REGISTRY.json','w',encoding='utf-8'),ensure_ascii=False,indent=1)

# JSONL
jl='_AI_Training_Dataset/daoli_st_sft_dataset.jsonl'
n0=sum(1 for _ in io.open(jl,encoding='utf-8'))
with io.open(jl,'a',encoding='utf-8') as f:
    for e,src in added:
        instr=("【%s】%s 现场要求：给定工况下稳定计算/执行，输入含 NaN、越量程、除零等边界，"
               "必须判出并让出口回安全侧而不是把非法值传下去；参数非法要告警不动作；"
               "用 IEC 61131-3 纯跨平台 ST 实现，禁物理地址与外部全局量，状态机用 ENUM+CASE 含 ELSE 兜底，"
               "每个接口量给单位与量纲。")%(e['category'],e['description'])
        cot=("架构：单职责%s，接口按 输入/输出/内部状态 三段分层，输出唯一预置点+分段置位避免多处赋值的锁存竞争。\n"
             "状态机：相位用 ENUM 显式编号（留 10 的间隔便于插入），CASE 每相独立使能出口、独立 TON 超时、ELSE 兜底进 FAULT 并锁存码位。\n"
             "防错：① 先判后用，非有限值闸断实值通路并让出口取安全值（只置 xValid 会让 NaN 直穿 REAL 出口）；"
             "② 判据与出口同源于原始值，禁止先 LIMIT 到量程再判超限（判据恒真）；③ 除法前分母防零；"
             "④ 时间量做上限钳位防首拍 PT=0 假超时；⑤ 机组/台数类整型量钳非负。\n"
             "解耦：纯计算件（FC）不持定时器，时序件（FB）持定时器且实例无条件周期刷新，便于跨平台移植与单件复用。")%e['type']
        f.write(json.dumps({"instruction":instr,"architecture_thought":cot,"output":src},ensure_ascii=False)+"\n")
n1=sum(1 for _ in io.open(jl,encoding='utf-8'))
from collections import Counter
c=Counter(x.get('category') for x in items)
print("registry",len(items),"jsonl",n0,"->",n1,"added",len(added))
print("cats",dict(c),"sum",sum(c.values()))
json.dump([a[0] for a in added],io.open('_Staging_Raw/2026-11-25/r93_added.json','w',encoding='utf-8'),ensure_ascii=False,indent=1)
