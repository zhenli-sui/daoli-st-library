# -*- coding: utf-8 -*-
"""
Round 10 终审 —— JSONL 修复件再同步
从修复后的 .st 文件字节级重注入 daoli_st_sft_dataset.jsonl 对应条目的 output 字段。
其余条目零漂移（逐字节比对校验）。
"""
import json
import os
import sys
import hashlib

JSONL = r"C:\Library\_AI_Training_Dataset\daoli_st_sft_dataset.jsonl"
BACKUP = r"C:\Library\_AI_Training_Dataset\daoli_st_sft_dataset.jsonl.backup_R10_FINAL"

LIB = r"C:\Library"

# 8 个修复件：POU 名 -> .st 绝对路径
FIXED = {
    "FC_DL_FactorialSat":       os.path.join(LIB, r"DL_MathData\FC_DL_FactorialSat.st"),
    "FB_DL_SineGenerator":      os.path.join(LIB, r"DL_Algo\FB_DL_SineGenerator.st"),
    "FB_DL_SawtoothGenerator":  os.path.join(LIB, r"DL_Algo\FB_DL_SawtoothGenerator.st"),
    "FB_DL_RfidTagHandler":     os.path.join(LIB, r"DL_Device\FB_DL_RfidTagHandler.st"),
    "FB_DL_AxiolineDiagLatch":  os.path.join(LIB, r"DL_Device\FB_DL_AxiolineDiagLatch.st"),
    "FB_DL_PdiReadScheduler":   os.path.join(LIB, r"DL_Device\FB_DL_PdiReadScheduler.st"),
    "FB_DL_WindingTraverse":    os.path.join(LIB, r"DL_Motion\FB_DL_WindingTraverse.st"),
    "FB_DL_PickAndPlaceStation": os.path.join(LIB, r"DL_Process\FB_DL_PickAndPlaceStation.st"),
}


def sha256_of(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def read_st(path):
    """按 UTF-8 读取，newline='' 保持原始换行符不变。"""
    with open(path, "r", encoding="utf-8", newline="") as f:
        return f.read()


def pou_name_of(text):
    """优先从头部『组件名称 (Component)』取 POU 名（文件头注释总是第一屏就有）。
    回退：扫描全文件第一处 POU 声明行。"""
    for line in text.splitlines():
        s = line.strip()
        if "组件名称 (Component)" in s:
            # 形如：* 组件名称 (Component)  : FC_DL_FactorialSat
            after = s.split(":", 1)
            if len(after) == 2:
                cand = after[1].strip()
                if cand:
                    return cand
    for line in text.splitlines():
        s = line.strip()
        if s.startswith("FUNCTION_BLOCK ") or s.startswith("FUNCTION ") or s.startswith("INTERFACE "):
            return s.split()[1].split(":")[0].strip()
    return None


def main():
    # 0) 前置：当前文件必须与备份字节一致（确认未被中途改动）
    cur_sha = sha256_of(JSONL)
    bak_sha = sha256_of(BACKUP)
    if cur_sha != bak_sha:
        print("[ABORT] 当前 JSONL 与备份不一致，拒绝覆盖。")
        print("  current:", cur_sha)
        print("  backup :", bak_sha)
        return 1
    print(f"[OK] 前置校验通过，备份 sha256 = {bak_sha}")
    print(f"[OK] 备份文件 = {BACKUP}")

    with open(JSONL, "r", encoding="utf-8", newline="") as f:
        raw_lines = f.read().split("\n")

    # 保留末行空串（文件以换行结尾时 split 末尾会有一个 ""）
    trailing = False
    if raw_lines and raw_lines[-1] == "":
        trailing = True
        raw_lines = raw_lines[:-1]
    n = len(raw_lines)
    print(f"[OK] 读入 {n} 行")

    objs = []
    for i, ln in enumerate(raw_lines):
        objs.append(json.loads(ln))

    # 1) 建立 POU -> 行索引表（从 .st 文件内容反查，避免依赖固定行号）
    #    用 output 里的 POU 声明行匹配
    patched_idx = {}
    for name, path in FIXED.items():
        hits = []
        for i, o in enumerate(objs):
            if pou_name_of(o["output"]) == name:
                hits.append(i)
        if len(hits) != 1:
            print(f"[ABORT] {name} 在 JSONL 中命中 {len(hits)} 条（期望 1）：{hits}")
            return 1
        patched_idx[name] = hits[0]
        print(f"[MAP] {name:28s} -> line {hits[0] + 1}")

    # 2) 逐件读取修复后 .st，做 POU 名一致性断言，然后重注入
    new_texts = {}
    for name, path in FIXED.items():
        if not os.path.isfile(path):
            print(f"[ABORT] 文件不存在：{path}")
            return 1
        txt = read_st(path)
        got = pou_name_of(txt)
        if got != name:
            print(f"[ABORT] {path} 的 POU 名是 {got}，与期望 {name} 不符")
            return 1
        new_texts[name] = txt
        print(f"[READ] {name}: {len(txt)} chars, {txt.count(chr(10)) + 1} lines")

    # 3) 重注入 output，其余字段原样保留
    for name, idx in patched_idx.items():
        old = objs[idx]["output"]
        new = new_texts[name]
        assert new != old or True
        objs[idx]["output"] = new
        # 记录 instruction 首行做人工核对
        instr = objs[idx]["instruction"].replace("\n", " ")[:60]
        print(f"[PATCH] line {idx + 1} {name}: {len(old)} -> {len(new)} chars | {instr}")

    # 4) 序列化：与既有格式保持一致（ensure_ascii=False，紧凑分隔）
    out_lines = [json.dumps(o, ensure_ascii=False) for o in objs]
    total = "\n".join(out_lines) + ("\n" if trailing else "")

    # 5) 漂移校验：未修复的 144 条必须逐字节相同
    drift = []
    patched_set = set(patched_idx.values())
    for i in range(n):
        if i in patched_set:
            continue
        if out_lines[i] != raw_lines[i]:
            drift.append(i + 1)
    if drift:
        print(f"[ABORT] 非目标条目发生漂移：{drift}")
        return 1
    print(f"[OK] 漂移校验通过：{n - len(patched_set)} 条未修复条目逐字节不变")

    # 6) round-trip 校验：每条都能被 json.loads 且 output 与 .st 一致
    for name, idx in patched_idx.items():
        again = json.loads(out_lines[idx])
        if again["output"] != new_texts[name]:
            print(f"[ABORT] round-trip 失败：{name}")
            return 1
    print("[OK] round-trip 校验通过（8/8）")

    # 7) 落盘
    with open(JSONL, "w", encoding="utf-8", newline="") as f:
        f.write(total)

    new_sha = sha256_of(JSONL)
    print(f"[DONE] 写入完成，{len(out_lines)} 行，{os.path.getsize(JSONL)} 字节")
    print(f"[SHA ] old = {bak_sha}")
    print(f"[SHA ] new = {new_sha}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
