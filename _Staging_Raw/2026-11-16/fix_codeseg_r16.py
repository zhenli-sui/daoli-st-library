# -*- coding: utf-8 -*-
"""R16 码位修正：按源码反算 20 件注册条目的 code_segment（源码为唯一事实源）"""
import json, re, io, sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", line_buffering=True)

REG = r"C:\Library\INDEX_REGISTRY.json"
MAN = r"C:\Library\_Staging_Raw\2026-11-16\manifest_r16.json"
NAMES = [it["name"] for it in json.load(open(MAN, encoding="utf-8"))["items"]]

CODE_RE = re.compile(r"16#0001_([0-9A-Fa-f]{4})")

def parse_file(path):
    txt = open(path, encoding="utf-8").read()
    # 取头注释 错误码 段（从“错误码    :”到“修订记录”之间）
    m = re.search(r"错误码\s+:\s*(.*?)修订记录", txt, re.S)
    seg = m.group(1) if m else ""
    out = []
    for line in seg.splitlines():
        line = line.strip()
        mm = CODE_RE.search(line)
        if not mm:
            continue
        code = "16#0001_" + mm.group(1).upper()
        rest = line[mm.end():].strip()
        rest = re.sub(r"^[—=\-–\s]+", "", rest)
        if "预留禁用" in rest or "不得挪用" in rest:
            level = "信息级" if "信息级" in rest else ("故障级" if "故障级" else "信息级")
            desc = "预留禁用"
            out.append("%s(%s：%s)" % (code, level, desc))
            continue
        # 级别：行内标注优先，否则按码值区间
        if "故障级" in line:
            level = "故障级"
        elif "信息级" in line:
            level = "信息级"
        else:
            level = "故障级" if int(mm.group(1), 16) >= 0x028E else "信息级"
        desc = re.sub(r"[——]-(故障级|信息级)[，,].*$", "", rest).strip()
        desc = re.sub(r"(故障级|信息级)[，,].*$", "", desc).strip()
        if not desc:
            desc = "见文件头错误码表"
        out.append("%s(%s：%s)" % (code, level, desc))
    return out

def main():
    reg = json.load(open(REG, encoding="utf-8"))
    idx = {c["name"]: c for c in reg["components"]}
    fixed = 0
    for n in NAMES:
        codes = parse_file(r"C:\Library\DL_MathData\%s.st" % n)
        assert len(codes) == 5, "%s: 提取到 %d 槽，应为 5" % (n, len(codes))
        seg = " / ".join(codes)
        old = idx[n]["code_segment"]
        idx[n]["code_segment"] = seg
        if old != seg:
            fixed += 1
        print("[%s] %s" % ("FIX" if old != seg else "SAME", n))
        print("      ->", seg)
    json.dump(reg, open(REG, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
    print("[DONE] corrected=%d/20 registry total=%d" % (fixed, reg["total_components"]))

if __name__ == "__main__":
    main()
