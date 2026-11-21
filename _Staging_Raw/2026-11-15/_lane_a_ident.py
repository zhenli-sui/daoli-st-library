# -*- coding: utf-8 -*-
"""标识符使用检查：声明未用 / 使用未声明（临时自检脚本）"""
import re, io, os

FILES = [
    r"C:\Library\DL_Device\I_DL_DeviceHealth.st",
    r"C:\Library\DL_Device\I_DL_PowerMeter.st",
    r"C:\Library\DL_Device\FB_DL_ModbusPowerMeter.st",
    r"C:\Library\DL_Device\FB_DL_ValveStictionDetect.st",
    r"C:\Library\DL_Device\FB_DL_AhuDamperStuckDiag.st",
    r"C:\Library\DL_Device\FB_DL_PumpCavitationGuard.st",
]

TYPES = r'(?:ARRAY\s*\[[^\]]*\]\s*OF\s*)?(?:BOOL|BYTE|WORD|DWORD|LWORD|SINT|INT|DINT|LINT|USINT|UINT|UDINT|ULINT|REAL|LREAL|TIME|LTIME|STRING|DATE|R_TRIG|TON|TOF|F_TRIG|CTU|CTD|E_DL_[A-Za-z0-9_]+|ST_DL_[A-Za-z0-9_]+)'
BUILTIN = set('''IF THEN ELSIF ELSE END_IF CASE OF END_CASE FOR TO BY DO END_FOR WHILE REPEAT
RETURN EXIT NOT AND OR XOR MOD TRUE FALSE AND_THEN OR_ELSE
ABS SQRT LIMIT MIN MAX SHL SHR ROL ROR SEL MUX LEN LEFT RIGHT MID CONCAT INSERT
LOWER_BOUND UPPER_BOUND TIME_TO_DINT DINT_TO_TIME INT_TO_DINT DINT_TO_INT DINT_TO_REAL
REAL_TO_DINT REAL_TO_LREAL LREAL_TO_REAL UINT_TO_REAL UINT_TO_UDINT UDINT_TO_REAL
UDINT_TO_LREAL UDINT_TO_UDINT INT_TO_REAL INT_TO_UINT UINT_TO_DINT DINT_TO_UDINT
BOOL_TO_INT UINT_TO_INT DINT_TO_UINT TIME_TO_REAL REAL_TO_TIME TYPE STRUCT END_STRUCT
VAR VAR_INPUT VAR_OUTPUT VAR_IN_OUT VAR_TEMP VAR CONSTANT END_VAR RETAIN PERSISTENT
FUNCTION_BLOCK FUNCTION PROGRAM INTERFACE END_INTERFACE END_FUNCTION_BLOCK END_FUNCTION
METHOD PROPERTY END_METHOD GET SET IMPLEMENTS EXTENDS PUBLIC PRIVATE PROTECTED
INTERNAL FINAL ABSTRACT THIS SUPER POINTER REFERENCE AT'''.split())

for f in FILES:
    txt = io.open(f, encoding='utf-8').read()
    # 去注释
    code = re.sub(r'\(\*.*?\*\)', lambda m: '\n' * m.group(0).count('\n'), txt, flags=re.S)
    code = re.sub(r'//[^\n]*', '', code)
    lines = code.split('\n')

    decls = {}
    in_var = False
    for ln in lines:
        s = ln.strip()
        if re.match(r'^VAR(_INPUT|_OUTPUT|_IN_OUT|_TEMP|_GLOBAL)?\b', s):
            in_var = True
            continue
        if s.startswith('END_VAR'):
            in_var = False
            continue
        if in_var:
            m = re.match(r'^([A-Za-z_][A-Za-z0-9_]*)\s*:\s*' + TYPES, s)
            if m:
                decls[m.group(1)] = ln
    # 类型声明里的枚举成员
    enum_members = set()
    for m in re.finditer(r'(?m)^\s*(e[A-Za-z0-9_]+)\s*:=', code):
        enum_members.add(m.group(1))
    # POU / 方法 / 属性名
    pou = set(re.findall(r'(?m)^\s*(?:FUNCTION_BLOCK|FUNCTION|INTERFACE|PROGRAM)\s+([A-Za-z0-9_]+)', code))
    methods = set(re.findall(r'(?m)^METHOD\s+([A-Za-z0-9_]+)', code))
    props = set(re.findall(r'(?m)^PROPERTY\s+([A-Za-z0-9_]+)', code))

    # 使用计数
    used = {}
    for name in decls:
        # 排除声明行本身
        cnt = len(re.findall(r'(?<![A-Za-z0-9_])' + re.escape(name) + r'(?![A-Za-z0-9_])', code))
        used[name] = cnt

    unused = sorted(n for n, c in used.items() if c <= 1)
    print('=' * 70)
    print(os.path.basename(f), '声明', len(decls), '个；仅出现一次（疑似未用）:', unused or 'none')

    # 赋值目标未声明
    assign_targets = set(re.findall(r'(?m)^\s*([A-Za-z_][A-Za-z0-9_]*)\s*:=', code))
    unknown = sorted(t for t in assign_targets
                     if t not in decls and t not in enum_members
                     and t not in methods and t not in props)
    print('  赋值目标未声明:', unknown or 'none')

    # 使用未声明（粗略：首字母前缀合法的标识符）
    idents = set(re.findall(r'(?<![A-Za-z0-9_])([A-Za-z_][A-Za-z0-9_]*)(?![A-Za-z0-9_])', code))
    suspicious = []
    for t in idents:
        if t in BUILTIN or t in decls or t in enum_members or t in methods or t in props:
            continue
        if t in pou or t.startswith('E_DL_') or t.startswith('ST_DL_'):
            continue
        if re.match(r'^(b|n|u|f|s|t|a|e|st|fb|i|_)', t):
            suspicious.append(t)
    print('  疑似未声明引用:', sorted(suspicious) or 'none')
