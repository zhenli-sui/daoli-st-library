# -*- coding: utf-8 -*-
"""R25-RESUME 终审修复重注入（R19-2 五步法）：
   ① 按组件名定位 JSONL 行 → ② 替换 output → ③ 复核/修正 architecture_thought
   → ④ sha256 与源文件全量复验 → ⑤ 同步 registry 的 version / line_count。
   仅动本轮 6 个修复件对应的行，其余行逐字保持。"""
import json, re, hashlib, os, glob as g, shutil

os.chdir("C:/Library")
BACK = "_Staging_Raw/2026-11-17"
shutil.copy("_AI_Training_Dataset/daoli_st_sft_dataset.jsonl", BACK + "/jsonl.backup_R25_FIX.jsonl")
shutil.copy("INDEX_REGISTRY.json", BACK + "/INDEX_REGISTRY.backup_R25_FIX.json")

FIXED = ["FB_DL_PalletizerLayerSeq", "FB_DL_SolarStringGroundFault", "FB_DL_VavBoxCtrl",
         "FB_DL_RoomClimateCtrl", "FB_DL_SplicerAutoJoint", "FB_DL_BatteryTestCycler"]

# ③ architecture_thought 勘误后缀（追加式，不改原文，避免二次漂移）
NOTE = {
 "FB_DL_PalletizerLayerSeq":
   "（v1.0.1 终审勘误）旋转层阵外平移量改为 (nRowsEff−1)x箱宽：旋转 90° 后箱体沿托盘长方向的足迹是箱宽，"
   "原式加整条托盘长会整体多推一个箱宽、首行越界；层容量按公式自算为正交 3x3=9 / 旋转 4x2=8（派单书验收向量①"
   "所写「容量 6」为派单算术笔误，实现以 9 为准）；bPalletDone 撤销点移交 eIdle 相，杜绝同拍置位又撤位。",
 "FB_DL_SolarStringGroundFault":
   "（v1.0.1 终审勘误）量纲链用除式 Rb x (Vp+Vn)/(Vbus−Vp−Vn)：乘式 Rb x (Vbus/(Vp+Vn)−1) 分子分母倒置，"
   "完全平衡（绝缘趋无穷）时会得 0 kΩ 并把绝缘良好误判为对地短路；组态闸补 fWarnKOhm >= 上限哨兵 1.0E9 kΩ → 035A，"
   "防哨兵值被判成「低于预警阈值」。",
 "FB_DL_VavBoxCtrl":
   "（v1.0.1 终审勘误）非有限闸的安全侧赋值改为可用下限 fFloorPct：原式直接写 fOpenMinPct，而下限脚本身在"
   "本闸判定集合内，NaN 下限会把 NaN 当安全值出口。",
 "FB_DL_RoomClimateCtrl":
   "（v1.0.1 终审勘误）补失能出口收口（段 11）：PID 件失能输出回 rOutMin=−100%，经带符号分程映射为 100% 冷却，"
   "四阀归零要等下一拍 eIdle 相，失能沿那一拍破坏「失能=四阀回 0%」契约。",
 "FB_DL_SplicerAutoJoint":
   "（v1.0.1 终审勘误）eSyncWait 补「进相前置消失」第二退出条件：bNewRollReady 撤销退回 ePreAccel，由该相 tPreAccelMax "
   "超时闸兜住；两相 bCutCmd 均 FALSE，「未同步绝不裁切」不受影响。遗留：同步相无自有超时（挂账下轮，新增 tSyncMax 或改计时窗）。",
 "FB_DL_BatteryTestCycler":
   "（v1.0.1 终审勘误）补 eFault 独立 CASE 标签：原实现 eFault(99) 落进 ELSE 兜底支路，每拍把 034B/034C 覆盖成 034D "
   "「非法状态」，激励消失后真因码丢失；故障仍锁存、安全侧不变。同批另 6 件同类标签缺失已挂账。",
}

path = "_AI_Training_Dataset/daoli_st_sft_dataset.jsonl"
lines = open(path, encoding="utf-8", newline="").read().splitlines()
reg = json.load(open("INDEX_REGISTRY.json", encoding="utf-8"))
by_name = {c["name"]: c for c in reg["components"]}

assert len(lines) == 444, len(lines)
done = []
for i, ln in enumerate(lines):
    obj = json.loads(ln)
    m = re.search(r"\b(?:FB_|FC_|I_)DL_\w+", obj["output"])
    if not m or m.group(0) not in FIXED:
        continue
    nm = m.group(0)                                   # ① 定位
    fp = g.glob("DL_*/%s.st" % nm)
    assert len(fp) == 1, (nm, fp)
    src = open(fp[0], encoding="utf-8", newline="").read()
    obj["output"] = src                               # ② 替换 output
    if "（v1.0.1 终审勘误）" not in obj["architecture_thought"]:
        obj["architecture_thought"] = obj["architecture_thought"] + NOTE[nm]   # ③ 复核/修正
    lines[i] = json.dumps(obj, ensure_ascii=False)
    c = by_name[nm]
    old_ver = c["version"]
    c["version"] = "1.0.1"                            # ⑤ registry 同步
    c["line_count"] = len(src.splitlines())
    done.append((nm, old_ver, c["line_count"]))

assert len(done) == 6, done
open(path, "w", encoding="utf-8", newline="").write("\n".join(lines) + "\n")
json.dump(reg, open("INDEX_REGISTRY.json", "w", encoding="utf-8"), ensure_ascii=False, indent=2)

# ④ 全量 sha 复验（R102 口径：全行，不只末 20 行）
bad, noPou = 0, 0
for ln in lines:
    obj = json.loads(ln)
    m = re.search(r"\b(?:FB_|FC_|I_)DL_\w+", obj["output"])
    if not m:
        noPou += 1
        continue
    fp = g.glob("DL_*/%s.st" % m.group(0))
    if len(fp) != 1:
        bad += 1
        print("NOPATH", m.group(0))
        continue
    src = open(fp[0], encoding="utf-8", newline="").read()
    if hashlib.sha256(obj["output"].encode()).hexdigest() != hashlib.sha256(src.encode()).hexdigest():
        bad += 1
        print("DRIFT", m.group(0))
print("fixed rows:", done)
print("jsonl total lines:", len(lines), "| noPOU rows:", noPou, "| sha mismatch:", bad)
print("registry total:", reg["total_components"], reg["counts"], reg["version"])
