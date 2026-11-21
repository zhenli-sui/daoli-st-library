import re,os,json,sys
files="""FC_DL_ReverseBitsLword FC_DL_BitScanLword FC_DL_Hypot3D FC_DL_TrapezoidArea FC_DL_SortIndexLReal FC_DL_WeightedPercentile FC_DL_MeanAbsDevCalc FB_DL_LongPressButton FB_DL_RailPowerSequence FB_DL_AxisLimitSwitchBank FB_DL_PidParamGuard FB_DL_PhaseLossGuard FB_DL_SensorPairPlausibility FB_DL_AirDryerDiag FB_DL_TurretToolSelect FB_DL_LineClearanceVerify""".split()
res=[]
tot_lines=0
for n in files:
    p=None
    for d in os.listdir('.'):
        if d.startswith('DL_'):
            q=os.path.join(d,n+'.st')
            if os.path.exists(q): p=q
    if not p:
        res.append((n,'MISSFILE',[],0));continue
    s=open(p,encoding='utf-8',errors='replace').read()
    L=s.splitlines(); tot_lines+=len(L)
    fails=[]
    if re.search(r'VAR_EXTERNAL|VAR_GLOBAL',s,re.I): fails.append('GVL')
    if re.search(r'%\s*[IQM]',s): fails.append('ADDR')
    if '(*' in s:
        pass
    # nested comment
    depth=0;bad=False
    i=0
    while i<len(s)-1:
        if s[i:i+2]=='(*': depth+=1; i+=2; continue
        if s[i:i+2]=='*)':
            depth-=1
            if depth<0: bad=True
            i+=2; continue
        i+=1
    if bad or depth!=0: fails.append('COMMENT')
    if 'TODO' in s.upper() or 'FIXME' in s.upper() or '待补' in s or '占位' in s: fails.append('PLACEHOLDER')
    for kw,cl in (('FOR','END_FOR'),('WHILE','END_WHILE'),('REPEAT','END_REPEAT')):
        a=len(re.findall(r'\b'+kw+r'\b',re.sub(r'\(\*.*?\*\)','',s,flags=re.S)))
        b=len(re.findall(r'\b'+cl+r'\b',re.sub(r'\(\*.*?\*\)','',s,flags=re.S)))
        if a!=b: fails.append(f'{kw}{a}/{b}')
    # enum single colon
    if re.search(r'^\s*\w+\s*:\s*=',s,re.M): fails.append('ENUMCOLON')
    # CASE ELSE
    if re.search(r'\bCASE\b',s,re.I):
        # crude: count CASE and ELSE presence
        if not re.search(r'\bELSE\b',s,re.I): fails.append('CASE_NO_ELSE')
    # bilingual comment ratio on VAR decl lines
    decl=[l for l in L if re.match(r'\s*\w+\s*:\s*(BOOL|INT|DINT|UDINT|UINT|SINT|LINT|ULINT|REAL|LREAL|TIME|WORD|DWORD|LWORD|BYTE|STRING|E_DL_|ST_DL_|TON|R_TRIG|F_TRIG|ARRAY)',l,re.I)]
    bi=[l for l in decl if re.search(r'[\u4e00-\u9fff]',l)]
    ratio=(len(bi)/len(decl)*100) if decl else 100
    if ratio<90: fails.append(f'BILING{ratio:.0f}%')
    # output declared
    if re.search(r'\bVAR_OUTPUT\b',s,re.I) is None and re.search(r'\bOUTPUT\b',s,re.I): fails.append('OUT_SYNTAX')
    res.append((n,'PASS' if not fails else 'FAIL',fails,len(L)))
fails=[r for r in res if r[1]!='PASS']
print(f'total {len(res)} pass {len(res)-len(fails)} fail {len(fails)} lines {tot_lines}')
for r in res: print(r)
json.dump([{'name':r[0],'verdict':r[1],'fails':r[2],'lines':r[3]} for r in res],open('_audit_r61.json','w',encoding='utf-8'),ensure_ascii=False,indent=1)
