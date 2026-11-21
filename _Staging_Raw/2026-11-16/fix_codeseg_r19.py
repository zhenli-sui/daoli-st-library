# -*- coding: utf-8 -*-
"""R19 fix: re-extract code_segment restricted to 16#000[1-5]_ pattern; verify collisions; save registry."""
import json, re, glob

NEWNAMES = {'FC_DL_DintMsToTod','FC_DL_TimeRatioCalc','FC_DL_RatioToPwrDb','FC_DL_LintToUdintSat',
 'FB_DL_BitShiftRegister','FC_DL_ModbusRtuFrameCheck','FB_DL_FlowSqrtExtract','FB_DL_RatioController',
 'FB_DL_LeadLagCompensator','FB_DL_AutoTuneRelay','FB_DL_DeviceHealthArbiter','FB_DL_ProfinetAlarmDiag',
 'FB_DL_EscChuckCurrentMonitor','FB_DL_DeviceParamWrite','FB_DL_ExternalEncoderScaler','FB_DL_CamPhaseTrim',
 'FB_DL_FilmWebCenter','FB_DL_WindingLayerCounter','FB_DL_DrumLevelThreeElem','FB_DL_VacCupRingCtrl'}
PAT = re.compile(r'16#000[1-5]_[0-9A-Fa-f]{4}')

reg = json.load(open('INDEX_REGISTRY.json', encoding='utf-8'))
fix = 0
for c in reg['components']:
    if c['name'] not in NEWNAMES:
        continue
    txt = open(c['file_path'], encoding='utf-8', newline='').read()
    head = txt[:5000]
    seen = []
    for m in PAT.finditer(head):
        u = m.group(0).upper()
        if u not in seen:
            seen.append(u)
        if len(seen) == 5:
            break
    assert len(seen) == 5, (c['name'], seen)
    cs = ' / '.join(seen)
    if cs != c['code_segment']:
        print('FIX', c['name'], 'old:', c['code_segment'], '-> new:', cs)
        c['code_segment'] = cs
        fix += 1

newcodes = {}
for c in reg['components']:
    if c['name'] in NEWNAMES and c['code_segment'] != 'N/A':
        for code in c['code_segment'].split(' / '):
            newcodes.setdefault(code, []).append(c['name'])
oldcodes = set()
for f in glob.glob('DL_*/*.st'):
    base = f.replace('\\', '/').split('/')[-1].rsplit('.', 1)[0]
    if base in NEWNAMES:
        continue
    for m in PAT.finditer(open(f, encoding='utf-8').read()):
        oldcodes.add(m.group(0).upper())
clash = [(n, code) for code, ns in newcodes.items() for n in ns if code in oldcodes]
dup = {code: ns for code, ns in newcodes.items() if len(ns) > 1}
print('fixed entries:', fix)
print('CLASH vs old:', clash if clash else 'NONE')
print('internal dup:', dup if dup else 'NONE')
json.dump(reg, open('INDEX_REGISTRY.json', 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
print('registry saved, total', reg['total_components'])
