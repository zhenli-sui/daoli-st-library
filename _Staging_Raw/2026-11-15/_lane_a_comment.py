# -*- coding: utf-8 -*-
"""声明行同行注释完整性检查（临时）"""
import io, os, re

FILES = [
    r"C:\Library\DL_Device\I_DL_DeviceHealth.st",
    r"C:\Library\DL_Device\I_DL_PowerMeter.st",
    r"C:\Library\DL_Device\FB_DL_ModbusPowerMeter.st",
    r"C:\Library\DL_Device\FB_DL_ValveStictionDetect.st",
    r"C:\Library\DL_Device\FB_DL_AhuDamperStuckDiag.st",
    r"C:\Library\DL_Device\FB_DL_PumpCavitationGuard.st",
]
TYPES = (r'(?:ARRAY\s*\[[^\]]*\]\s*OF\s*)?(?:BOOL|BYTE|WORD|DWORD|SINT|INT|DINT|USINT|UINT|UDINT|'
         r'REAL|LREAL|TIME|STRING|R_TRIG|TON|TOF|F_TRIG|CTU|E_DL_[A-Za-z0-9_]+|ST_DL_[A-Za-z0-9_]+)')

for f in FILES:
    bad = []
    for i, ln in enumerate(io.open(f, encoding='utf-8').read().split('\n'), 1):
        s = ln.strip()
        if re.match(r'^[A-Za-z_][A-Za-z0-9_]*\s*:\s*' + TYPES, s):
            if '//' not in ln:
                bad.append((i, s[:70]))
    print(os.path.basename(f), '缺同行注释:', bad or 'none')
