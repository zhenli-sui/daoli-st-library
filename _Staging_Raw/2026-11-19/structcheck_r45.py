# -*- coding: utf-8 -*-
"""R45 结构平衡抽检：IF/END_IF、CASE/END_CASE、POU 头尾、VAR/END_VAR、注释配对、CRLF。"""
import re, os, sys


def struct(p):
    t = open(p, encoding="utf-8", newline="").read()
    code = re.sub(r"\(\*.*?\*\)", lambda m: "\n" * m.group(0).count("\n"), t, flags=re.S)
    code = re.sub(r"//[^\n]*", "", code)
    d = {}
    d["IF"] = (len(re.findall(r"\bIF\b", code)), len(re.findall(r"\bEND_IF\b", code)))
    d["ELSIF"] = len(re.findall(r"\bELSIF\b", code))
    d["CASE"] = (len(re.findall(r"\bCASE\b", code)), len(re.findall(r"\bEND_CASE\b", code)))
    d["FB"] = (len(re.findall(r"\bFUNCTION_BLOCK\b", code)), len(re.findall(r"\bEND_FUNCTION_BLOCK\b", code)))
    d["FN"] = (len(re.findall(r"\bFUNCTION\b", code)) - len(re.findall(r"\bFUNCTION_BLOCK\b", code)),
               len(re.findall(r"\bEND_FUNCTION\b", code)) - len(re.findall(r"\bEND_FUNCTION_BLOCK\b", code)))
    d["VAR"] = (len(re.findall(r"^\s*VAR(_INPUT|_OUTPUT|_IN_OUT|_TEMP|_CONSTANT|_STAT|_GLOBAL)?(\s+CONSTANT)?\s*$", code, re.M)),
                len(re.findall(r"\bEND_VAR\b", code)))
    d["CMT"] = (t.count("(*"), t.count("*)"))
    d["CRLF"] = (t.count("\r\n"), t.count("\n"))
    return d


bad = 0
for p in sys.argv[1:]:
    d = struct(p)
    ok = (d["IF"][0] == d["IF"][1] and d["CASE"][0] == d["CASE"][1] and d["FB"][0] == d["FB"][1]
          and d["FN"][0] == d["FN"][1] and d["VAR"][0] == d["VAR"][1]
          and d["CMT"][0] == d["CMT"][1] and d["CRLF"][0] == d["CRLF"][1])
    print(("OK  " if ok else "BAD ") + os.path.basename(p), d)
    if not ok:
        bad += 1
print("structural BAD =", bad)
