# -*- coding: utf-8 -*-
"""R84 入队：追加 7 条 + 标记 2 条工具误入重复行（不删行）+ 更新指纹"""
import io, json, os

LIB = r"C:\Library"
STG = os.path.join(LIB, "_Staging_Raw", "2026-11-24")
QP = os.path.join(STG, "candidate_queue.jsonl")
FP = os.path.join(LIB, "_Staging_Raw", "_dedup_fingerprints.json")

final = json.load(open(os.path.join(STG, "_r84_final.json"), encoding="utf-8"))
keep = [r for r in final if r["name"] != "FB_RTPP_CALC"]   # 拆件凑数剔除（FB_RTPP 的子块）

# 逐条人工校准缺口（结构体类给真实缺口，不用占位句）
FIX = {
    "ST_UnwindRecipe": ["纯参数域结构体，无上下限声明；写入侧需补膜宽/张力/直径钳位",
                        "无版本/校验字段，配方回读无法判新旧"],
    "ST_PullWheelsRecipe": ["纯参数域结构体，无速比/轮径合理域校验，需在写入侧加钳位",
                            "无单位声明，轮径与线速度混用易错"],
    "RTPP_REG": ["回归样本数组固定 1000 点无溢出保护，需检查环绕覆盖",
                 "M/C 为 VAR_IN_OUT 全局引用，掉电不保存则冷启动首周期用旧斜率"],
    "FB_RTPP": ["含 TON 定时回归，未见过采样/时基漂移补偿",
                "除子闸仅在标称功率非零时成立，需人工确认 DC 功率为 0 的边界"],
    "FB_Unwind": ["PackML 相序无非法相号兜底，需补 ELSE 分支",
                  "膜卷直径换算含裸除法，需检查直径=0 边界"],
    "FB_PullWheel": ["张力设定到速度输出之间无爬坡限幅，需补 SlewRate 闸",
                     "含平台方言依赖，clean-room 需剥离"],
    "FB_Sealer": ["封刀温度/停留/压力三量无互锁优先级，建议补 2oo3 判据",
                  "PackML 相序无非法相号兜底"],
    "TcoOscilatingConveyorFeeder": ["含 EXTENDS/INTERFACE 继承链，剥离需改组合",
                                    "堵料检测依赖 TON 延时，需检查无复位路径"],
}
for r in keep:
    if r["name"] in FIX:
        r["defense_gaps"] = FIX[r["name"]]
    r["harvested_round"] = "R84"
    r["status"] = "pending"

rows = [json.loads(l) for l in io.open(QP, encoding="utf-8") if l.strip()]
n0 = len(rows)
# 标记本轮工具误入的 2 条（与在册行同名重复，垃圾名 VAR_INPUT）
DUPS = {"E_SMStatus", "VAR_INPUT"}
for r in rows:
    if r["name"] in DUPS and r.get("harvested_at", "").startswith("2026-11-24T16") and r.get("status") is None:
        r["status"] = "rejected"
        r["reject_reason"] = "R84 工具默认检索误入：与在册行同名重复（未删行，留痕）"

rows.extend(keep)
with io.open(QP, "w", encoding="utf-8") as f:
    for r in rows:
        f.write(json.dumps(r, ensure_ascii=False) + "\n")

fp = json.load(open(FP, encoding="utf-8"))
for r in keep:
    fp[r["fp"]] = r["name"]
json.dump(fp, open(FP, "w", encoding="utf-8"), ensure_ascii=False, indent=0)

print("queue %d -> %d (+%d)" % (n0, len(rows), len(keep)))
import collections
print(collections.Counter(r.get("tier") for r in rows))
print("rejected:", sum(1 for r in rows if r.get("status") == "rejected"))
print("fp size:", len(fp))
for r in keep:
    print("  %-30s %-6s %-5s loc=%-4d gaps=%d %s" % (r["name"], r["family"], r["kind"], r["loc"], len(r["defense_gaps"]), r["license"]))
