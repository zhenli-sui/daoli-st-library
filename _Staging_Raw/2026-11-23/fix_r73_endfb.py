# -*- coding: utf-8 -*-
"""R73：FB 尾部 END_FUNCTION 误用 → END_FUNCTION_BLOCK（E007 系统性缺陷）。"""
import io, re, glob, os
files = [f for f in glob.glob(r"DL_*\*.st") if os.path.getmtime(f) > 1763900000]
fixed = []
for p in files:
    s = io.open(p, encoding="utf-8").read()
    if not re.search(r"^\s*FUNCTION_BLOCK\s+\w+", s, re.M):
        continue
    if re.search(r"^\s*END_FUNCTION_BLOCK\s*$", s, re.M):
        continue
    m = list(re.finditer(r"^(\s*)END_FUNCTION\s*$", s, re.M))
    if not m:
        print("NO_TAIL", p); continue
    last = m[-1]
    s = s[:last.start()] + last.group(1) + "END_FUNCTION_BLOCK" + s[last.end():]
    io.open(p, "w", encoding="utf-8", newline="\n").write(s)
    fixed.append(os.path.basename(p))
print("FIXED", len(fixed), fixed)
