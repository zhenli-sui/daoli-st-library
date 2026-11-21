# -*- coding: utf-8 -*-
"""R13 泳道 A 自检脚本（临时，仅用于本地自检，不写入库目录）"""
import re, io, os, sys, json

FILES = [
    r"C:\Library\DL_Device\I_DL_DeviceHealth.st",
    r"C:\Library\DL_Device\I_DL_PowerMeter.st",
    r"C:\Library\DL_Device\FB_DL_ModbusPowerMeter.st",
    r"C:\Library\DL_Device\FB_DL_ValveStictionDetect.st",
    r"C:\Library\DL_Device\FB_DL_AhuDamperStuckDiag.st",
    r"C:\Library\DL_Device\FB_DL_PumpCavitationGuard.st",
]

def strip_comments(txt):
    out = []
    i = 0
    n = len(txt)
    while i < n:
        if txt.startswith('(*', i):
            j = txt.find('*)', i + 2)
            if j < 0:
                j = n
            block = txt[i:j+2]
            out.append('\n' * block.count('\n'))
            i = j + 2
        elif txt.startswith('//', i):
            j = txt.find('\n', i)
            if j < 0:
                j = n
            i = j
        else:
            out.append(txt[i])
            i += 1
    return ''.join(out)

def check(path):
    txt = io.open(path, encoding='utf-8').read()
    code = strip_comments(txt)
    lines = txt.split('\n')
    res = {}
    res['lines'] = len(lines)

    # 1 占位符
    ph = []
    for idx, ln in enumerate(lines, 1):
        for pat in ['// 略', '// 同上', '…', '...', 'TODO', 'TBD', '待补', 'XX']:
            if pat in ln:
                ph.append((idx, pat, ln.strip()[:60]))
    res['placeholder'] = ph

    # 2 禁记号（含注释）
    forbid = []
    for idx, ln in enumerate(lines, 1):
        for pat in ['GVL', 'VAR_EXTERNAL', '%IX', '%QX', '%IW', '%QW', '%MD', '%ID', '%QD', 'AT %']:
            if pat in ln:
                forbid.append((idx, pat, ln.strip()[:60]))
    res['forbidden'] = forbid

    # 3 嵌套注释
    nested = []
    depth = 0
    for idx, ln in enumerate(lines, 1):
        i = 0
        while i < len(ln):
            if ln.startswith('(*', i):
                depth += 1
                if depth > 1:
                    nested.append((idx, ln.strip()[:60]))
                i += 2
            elif ln.startswith('*)', i):
                depth = max(0, depth - 1)
                i += 2
            else:
                i += 1
    res['nested_comment'] = nested
    res['comment_depth_end'] = depth

    # 4 孤立分号
    stray = [(idx, ln.strip()) for idx, ln in enumerate(lines, 1) if ln.strip() == ';']
    res['stray'] = stray

    # 5 POU 成对
    pairs = [
        ('TYPE', 'END_TYPE'),
        ('FUNCTION_BLOCK', 'END_FUNCTION_BLOCK'),
        ('INTERFACE', 'END_INTERFACE'),
        ('CASE', 'END_CASE'),
        ('FOR', 'END_FOR'),
        ('IF', 'END_IF'),
    ]
    counts = {}
    for a, b in pairs:
        ca = len(re.findall(r'(?m)^\s*' + a + r'\b', code))
        cb = len(re.findall(r'(?m)^\s*' + b + r'\b', code))
        counts[a] = (ca, cb)
    res['pairs'] = counts

    # 6 枚举成员单冒号
    single = []
    for idx, ln in enumerate(lines, 1):
        m = re.match(r'\s*(e[A-Za-z0-9_]+)\s*:\s*[0-9]', ln)
        if m:
            single.append((idx, ln.strip()[:60]))
    res['enum_single_colon'] = single

    # 7 R29 赋值目标声明性
    decls = set()
    for m in re.finditer(r'(?m)^\s*([A-Za-z_][A-Za-z0-9_]*)\s*:\s*(?:ARRAY|BOOL|BYTE|WORD|DWORD|SINT|INT|DINT|LINT|USINT|UINT|UDINT|ULINT|REAL|LREAL|TIME|STRING|LTIME|E_DL_[A-Za-z0-9_]+|ST_DL_[A-Za-z0-9_]+|R_TRIG|TON|TOF|F_TRIG|CTU)', code):
        decls.add(m.group(1))
    assigns = set()
    for m in re.finditer(r'(?m)^\s*([A-Za-z_][A-Za-z0-9_]*)\s*(?:\[[^\]]*\])?\s*:=', code):
        assigns.add(m.group(1))
    # PROPERTY/METHOD 名不算
    undefined = sorted(a for a in assigns if a not in decls)
    res['undefined_assign'] = undefined

    # 8 浮点判等
    feq = []
    for idx, ln in enumerate(lines, 1):
        c = strip_comments(ln)
        if re.search(r'\bf[A-Z][A-Za-z0-9_]*\s*(?:=|<>)\s*', c):
            feq.append((idx, ln.strip()[:80]))
    res['float_eq'] = feq

    # 9 定时器实例是否在段 1 层无条件调用
    res['timer_calls'] = sorted(set(re.findall(r'^\s*(fb[A-Za-z0-9_]*)\(', code, re.M)))

    return res

total = 0
for f in FILES:
    r = check(f)
    total += r['lines']
    print('=' * 78)
    print(os.path.basename(f), ' 行数', r['lines'])
    print('  占位符:', r['placeholder'] or 'none')
    print('  禁记号:', r['forbidden'] or 'none')
    print('  嵌套注释:', r['nested_comment'] or 'none', '| 注释深度收尾', r['comment_depth_end'])
    print('  孤立分号:', r['stray'] or 'none')
    print('  成对:', r['pairs'])
    print('  枚举单冒号:', r['enum_single_colon'] or 'none')
    print('  未声明赋值目标:', r['undefined_assign'] or 'none')
    print('  浮点判等:', r['float_eq'] or 'none')
    print('  定时器调用:', r['timer_calls'])
print('=' * 78)
print('合计行数', total)
