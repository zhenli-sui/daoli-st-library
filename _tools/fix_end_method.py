#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""fix_end_method.py —— 补齐 METHOD 缺失的 END_METHOD（IEC 61131-3 第3版必需）

问题（2026-11-23 全库扫描）:
    45 个 .st 文件共 154 个 METHOD 声明缺少对应的 END_METHOD（仅 4 个有），
    形态如:

        METHOD Enable : BOOL
        VAR_INPUT
            xEnable : BOOL;
        END_VAR
        METHOD Reset : BOOL      ← 这里缺 END_METHOD

    Method 是 IEC 61131-3 第3版规定的有界块，必须有 END_METHOD 收尾，
    否则 CODESYS / TwinCAT / RuSTy 全部解析失败（E006/E007）。
    这批接口与 FB 长期未被真编译验证，故缺陷一直隐藏。

策略:
    线性扫描，维护 in_method 状态：
      - 遇 METHOD name       → in_method = True，记录该行缩进
      - 遇 END_METHOD        → in_method = False
      - in_method 且遇 METHOD / PROPERTY / END_INTERFACE / END_FUNCTION_BLOCK
        → 在**该行之前**插入 END_METHOD（沿用 METHOD 行缩进）
      - 文件结束仍 in_method → 在文件末尾补 END_METHOD

用法:
    python fix_end_method.py --dry-run    # 预览将插入的位置与数量
    python fix_end_method.py              # 执行（自动备份到 _archive/）
    python fix_end_method.py --files a.st b.st   # 只处理指定文件
"""
import glob
import os
import re
import shutil
import sys
import datetime

LIB = r"C:\Library"
MEMBER_START = re.compile(r"^\s*(METHOD|PROPERTY)\s+[A-Za-z_]", re.I)
BLOCK_END = re.compile(r"^\s*(END_INTERFACE|END_FUNCTION_BLOCK|END_FUNCTION)\b", re.I)
END_METHOD = re.compile(r"^\s*END_METHOD\b", re.I)


def fix_text(lines):
    """返回 (新行列表, 插入数)。"""
    out, n_ins = [], 0
    in_method = False
    indent = "    "
    for ln in lines:
        s = ln.strip()
        if END_METHOD.match(s):
            in_method = False
            out.append(ln)
            continue
        if MEMBER_START.match(s):
            if in_method:  # 上一个 METHOD 未收尾 → 先补，并立刻复位
                out.append(indent + "END_METHOD")
                out.append("")
                n_ins += 1
                in_method = False
            if re.match(r"^METHOD\s+[A-Za-z_]", s, re.I):
                in_method = True
                indent = ln[:len(ln) - len(ln.lstrip())] or "    "
            out.append(ln)
            continue
        if BLOCK_END.match(s):
            if in_method:
                out.append(indent + "END_METHOD")
                n_ins += 1
                in_method = False
            out.append(ln)
            continue
        out.append(ln)
    if in_method:
        out.append(indent + "END_METHOD")
        n_ins += 1
    return out, n_ins


def main():
    dry = "--dry-run" in sys.argv
    args = sys.argv[1:]
    explicit = []
    if "--files" in args:
        i = args.index("--files")
        explicit = args[i + 1:]
        explicit = [a for a in explicit if not a.startswith("--")]

    files = explicit or [f for f in sorted(glob.glob(os.path.join(LIB, "DL_*", "*.st")))
                         if not f.endswith((".bak", ".bak_gate"))]

    ts = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    bak = os.path.join(LIB, "_archive", "fix_endmethod_" + ts)
    changed, total_ins = [], 0
    for fp in files:
        try:
            text = open(fp, encoding="utf-8", errors="ignore").read()
        except OSError:
            continue
        lines = text.split("\n")
        new_lines, n = fix_text(lines)
        if n:
            changed.append((fp, n))
            total_ins += n
            if not dry:
                os.makedirs(bak, exist_ok=True)
                shutil.copy2(fp, os.path.join(bak, os.path.basename(fp)))
                open(fp, "w", encoding="utf-8", newline="\n").write("\n".join(new_lines))

    print(("【预览】" if dry else "【已执行】") +
          " 涉及文件 %d 个，补 END_METHOD %d 处" % (len(changed), total_ins))
    for fp, n in changed[:20]:
        print("  %-44s +%d" % (os.path.basename(fp), n))
    if len(changed) > 20:
        print("  ...（共 %d 文件）" % len(changed))
    if not dry and changed:
        print("备份:", bak)
    return 0


if __name__ == "__main__":
    sys.exit(main())
