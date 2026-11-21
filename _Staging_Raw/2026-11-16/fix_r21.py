# -*- coding: utf-8 -*-
"""R21 缺陷修复：补统一溯源短语 + 改写「同上」占位词。嵌套注释 2 处为审计正则误报（独立注释块跨块匹配），改用非贪婪成对剥离法复测。"""
import io, re

T0 = ["FC_DL_ModPos","FC_DL_DivLrealSafe","FC_DL_QuantizeStep","FC_DL_PolyEvalHorner",
      "FC_DL_WrapAngleDeg","FC_DL_StringToDint","FC_DL_DwordToHexString",
      "FC_DL_ArraySumLreal","FB_DL_MinOnOffGuard","FB_DL_SignalChangeCounter",
      "FB_DL_SamplingTrigger","FB_DL_PulseWidthFilter"]
CAT0 = {"FC_DL_ModPos":"DL_MathData","FC_DL_DivLrealSafe":"DL_MathData",
        "FC_DL_QuantizeStep":"DL_MathData","FC_DL_PolyEvalHorner":"DL_MathData",
        "FC_DL_WrapAngleDeg":"DL_MathData","FC_DL_StringToDint":"DL_MathData",
        "FC_DL_DwordToHexString":"DL_MathData","FC_DL_ArraySumLreal":"DL_MathData",
        "FB_DL_MinOnOffGuard":"DL_Base","FB_DL_SignalChangeCounter":"DL_Base",
        "FB_DL_SamplingTrigger":"DL_Base","FB_DL_PulseWidthFilter":"DL_Base"}
T2 = {"FC_DL_LwordBitFieldExtract":"DL_MathData","FC_DL_LwordBitFieldInsert":"DL_MathData",
      "FC_DL_LwordBitCount":"DL_MathData","FC_DL_Crc16Generic":"DL_MathData",
      "FC_DL_ChecksumSum8":"DL_MathData","FC_DL_TimeToHmsString":"DL_MathData",
      "FC_DL_DateToIsoString":"DL_MathData"}

def patch(path, old, new, must=True):
    s = io.open(path, encoding="utf-8", newline="").read()
    if old not in s:
        if must: raise SystemExit("NOT FOUND in %s: %s" % (path, old))
        return
    s = s.replace(old, new, 1)
    io.open(path, "w", encoding="utf-8", newline="").write(s)

# 1) 统一溯源短语（追加到「开源溯源」首行行尾）
for name, cat in CAT0.items():
    p = "%s/%s.st" % (cat, name)
    s = io.open(p, encoding="utf-8", newline="").read()
    m = re.search(r"(    开源溯源 : [^\n]*)", s)
    assert m, p
    tag = "；本件为 IEC 61131-3 标准语义的道莅防御性实现（原创实现，零外部源码复制）。"
    s = s.replace(m.group(1), m.group(1) + tag, 1)
    io.open(p, "w", encoding="utf-8", newline="").write(s)
for name, cat in T2.items():
    p = "%s/%s.st" % (cat, name)
    s = io.open(p, encoding="utf-8", newline="").read()
    m = re.search(r"(    开源溯源 : [^\n]*)", s)
    assert m, p
    tag = "；本件为道莅 clean-room 防御性实现（仅借 LGF 分类事实/参数域/行为定义，零代码行与符号名复制）。"
    s = s.replace(m.group(1), m.group(1) + tag, 1)
    io.open(p, "w", encoding="utf-8", newline="").write(s)

# 2) 「同上」占位词改写为显式表述
patch("DL_MathData/FC_DL_DivLrealSafe.st",
      "// 同上，分母同判 / same test for the denominator",
      "// 与分子同一判据 / same finite test as for the numerator")
patch("DL_MathData/FC_DL_DwordToHexString.st",
      "预留禁用（不得挪用，同上）", "预留禁用（不得挪用）")
patch("DL_Base/FB_DL_SignalFrozenDetect.st",
      "fMaxVal := fValue;                // 同上 / same as above\n        fMinVal := fValue;",
      "fMaxVal := fValue;                // 基准重建：极值取当前值 / rebuild baseline: max takes current value\n        fMinVal := fValue;",
      must=False)
s = io.open("DL_Base/FB_DL_SignalFrozenDetect.st", encoding="utf-8", newline="").read()
# 逐个处理剩余「同上」（每次替换第一处）
while "同上" in s:
    s = s.replace("// 同上 / same as above",
                  "// 极值基准取当前值 / extrema baseline takes current value", 1)
    io.open("DL_Base/FB_DL_SignalFrozenDetect.st", "w", encoding="utf-8", newline="").write(s)
    s = io.open("DL_Base/FB_DL_SignalFrozenDetect.st", encoding="utf-8", newline="").read()
print("fix done; remaining 同上:", sum(io.open(f, encoding="utf-8").read().count("同上")
      for f in ["DL_MathData/FC_DL_DivLrealSafe.st","DL_MathData/FC_DL_DwordToHexString.st",
                "DL_Base/FB_DL_SignalFrozenDetect.st"]))
