# -*- coding: utf-8 -*-
"""R15 归一化：①双语注释改 // 中文 / English ②错误码层改 eErr : UDINT + 16#0001_XXXX
   ③按实际文件重算 manifest 的 code_segment（保证注册表与源码一致）"""
import json, re, io, sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", line_buffering=True)

MAN = r"C:\Library\_Staging_Raw\2026-11-16\manifest_r15.json"

# 语义码 1..5 -> 槽位偏移
INFO_OFF = {1: 0, 3: 1, 4: 2}
FAULT_OFF = {2: 0, 5: 1}
BLOCK = 5

def split_header(text):
    """返回 (header_lines, body_lines)：header 为开头 (* ... 单独一行 *) 的块"""
    lines = text.split("\n")
    if not lines or not lines[0].strip().startswith("(*"):
        return [], lines
    for i in range(1, len(lines)):
        if lines[i].strip() == "*)":
            return lines[:i + 1], lines[i + 1:]
    return [], lines

def conv_comment(cm):
    """'中文 EN: english' -> '中文 / english'"""
    cm = cm.strip()
    m = re.split(r"\s+EN\s*:\s*", cm, maxsplit=1)
    if len(m) == 2:
        cn, en = m[0].strip(), m[1].strip()
        return f"{cn} / {en}"
    return cm

def main():
    man = json.load(open(MAN, encoding="utf-8"))
    items = man["items"]
    for idx, it in enumerate(items):
        info_base = 0x015E + idx * BLOCK
        fault_base = 0x022C + idx * BLOCK
        path = it["file_path"]
        text = open(path, encoding="utf-8").read()
        header, body = split_header(text)

        out = []
        for ln in body:
            # 1) 独立注释行 (* ... *)
            m = re.match(r"^(\s*)\(\*(.*)\*\)\s*$", ln)
            if m and "EN" in m.group(2):
                out.append(f"{m.group(1)}// {conv_comment(m.group(2))}")
                continue
            # 2) 行尾注释 (* ... *)（前面有代码）
            m = re.match(r"^(.*?[;\)])\s+\(\*(.*?)\*\)\s*$", ln)
            if m and "EN" in m.group(2):
                out.append(f"{m.group(1)} // {conv_comment(m.group(2))}")
                continue
            out.append(ln)
        body = "\n".join(out)

        # 3) 错误码层：uErrorId -> eErr，1..5 -> 16#0001_XXXX
        def repl_code(m):
            pre, num = m.group(1), int(m.group(2))
            if num == 0:
                return f"{pre}16#0000_0000"
            if num in INFO_OFF:
                return f"{pre}16#0001_{info_base + INFO_OFF[num]:04X}"
            if num in FAULT_OFF:
                return f"{pre}16#0001_{fault_base + FAULT_OFF[num]:04X}"
            return m.group(0)
        body = re.sub(r"(eErr\s*:=\s*)([0-5])\b", repl_code, body)
        body = re.sub(r"\buErrorId\b", "eErr", body)
        body = re.sub(r"\beErr\s*:\s*UINT\s*;", "eErr : UDINT;", body)
        body = re.sub(r"eErr\s*<>\s*0\b", "eErr <> 16#0000_0000", body)
        body = re.sub(r"eErr\s*=\s*0\b", "eErr = 16#0000_0000", body)
        # 头部内的 uErrorId 也换掉
        header = [re.sub(r"\buErrorId\b", "eErr", h) for h in header]

        txt = "\n".join(header) + "\n" + body
        open(path, "w", encoding="utf-8", newline="").write(txt)

        # 4) 从实际文件提取码位，重写 manifest
        codes = sorted(set(re.findall(r"16#0001_([0-9A-F]{4})", txt)))
        labels = []
        for c in codes:
            lab = ""
            for ln in txt.split("\n"):
                if f"16#0001_{c}" in ln and "//" in ln:
                    lab = ln.split("//", 1)[1].strip().split("/")[0].strip()
                    break
            lvl = "故障级" if int(c, 16) >= fault_base else "信息级"
            labels.append(f"16#0001_{c}({lvl}：{lab[:26]})")
        it["code_segment"] = " / ".join(labels) if labels else "未占用（纯语义包装，无错误码）"
        print(f"[OK] {it['name']:<24} codes={codes}")

    json.dump(man, open(MAN, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print("[DONE] 20 件归一化 + manifest code_segment 重算")

if __name__ == "__main__":
    main()
