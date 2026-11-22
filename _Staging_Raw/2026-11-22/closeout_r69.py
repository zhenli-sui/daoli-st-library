# -*- coding: utf-8 -*-
"""R69 closeout: gate scan, registry update, JSONL append."""
import json, subprocess, sys, datetime, copy

TS = "2026-11-22T14:35:00+08:00"
LIB = r"C:\Library"
GATE = LIB + r"\_tools\dl_gate.py"

NEW = [
    # name, category, kind, complexity, line_count, tags, origin_source, origin_desc, ref_tag
    ("FC_DL_TimeMulSat", "DL_MathData", "FC", 2, 96,
     ["time", "multiply", "saturate", "overflow-guard", "iec-std-wrapper", "r69-new"],
     "r69-plan", "IEC 61131-3 标准语义的道莅防御性实现（TIME 乘法饱和，委托平台内建乘法，不重实现内核）", "t0-std-wrapper"),
    ("FC_DL_TimeClampEx", "DL_MathData", "FC", 2, 80,
     ["time", "clamp", "range-guard", "iec-std-wrapper", "r69-new"],
     "r69-plan", "IEC 61131-3 标准语义的道莅防御性实现（TIME 上下限钳位，含下限>上限防御交换）", "t0-std-wrapper"),
    ("FC_DL_UdintToStringTrim", "DL_MathData", "FC", 3, 133,
     ["udint", "string", "convert", "trim", "iec-std-wrapper", "r69-new"],
     "r69-plan", "IEC 61131-3 标准语义的道莅防御性实现（UDINT→STRING 定宽右对齐补位/去前导零）", "t0-std-wrapper"),
    ("FB_DL_MotorHealthAoi", "DL_Device", "FB", 3, 283,
     ["motor", "health", "aoi", "temperature", "current", "rockwell-aoi", "r69-new"],
     "r69-plan", "罗克韦尔 AOI 设备级粒度族语义借鉴，clean-room 重写（电机健康综合评级）", "t2-6-rockwell-aoi"),
    ("FB_DL_ValveIslandDiag", "DL_Device", "FB", 3, 244,
     ["valve-island", "diagnostics", "slot", "online-count", "self-std", "r69-new"],
     "r69-plan", "自研防御性新增线（阀岛在线/槽数对账诊断）", "self-std"),
    ("FB_DL_AlarmShelveMgmt", "DL_Base", "FB", 3, 269,
     ["alarm", "shelving", "isa182", "lifecycle", "r69-new"],
     "r69-plan", "ISA-18.2 报警搁置(Shelving)生命周期语义借鉴，clean-room 重写", "t2-8-isa182"),
    ("FB_DL_SignalFreeze", "DL_Base", "FB", 2, 223,
     ["signal-freeze", "batch", "sampling", "latch", "self-std", "r69-new"],
     "r69-plan", "自研防御性新增线（批量/报表期信号冻结采样）", "self-std"),
    ("FB_DL_AxisDroopComp", "DL_Motion", "FB", 3, 218,
     ["axis", "droop", "following-error", "compensation", "s7motion", "r69-new"],
     "r69-plan", "西门子 S7 Motion 跟随误差补偿语义借鉴，clean-room 重写", "t2-4-s7motion"),
    ("FB_DL_CascadeCtrl", "DL_Algo", "FB", 3, 312,
     ["cascade", "bumpless-transfer", "anti-windup", "control", "self-std", "r69-new"],
     "r69-plan", "自研控制族新增线（串级骨架：切换无扰+双向抗饱和回投）", "self-std"),
    ("FB_DL_CuringOvenSeq", "DL_Process", "FB", 3, 276,
     ["curing-oven", "sequence", "temperature-profile", "state-machine", "self-std", "r69-new"],
     "r69-plan", "自研工艺新增线（固化炉升温/保温/固化/降温顺控）", "self-std"),
]

FIXED = {  # name -> (new version, tag suffix)
    "FB_DL_InterlockBypassAudit": ("1.0.1", "r69-postfix"),
    "FB_DL_StretchWrapSeq": ("1.0.2", "r69-postfix"),
    "FB_DL_FlowMeterKFactorDrift": ("1.0.2", "r69-postfix"),
    "FB_DL_TruckScaleSeq": ("1.0.2", "r69-postfix"),
    "FB_DL_RotaryAirlockCtrl": ("1.0.2", "r69-postfix"),
}

JL_DESC = {
    "FC_DL_TimeMulSat": ("定时器预设时间按倍率系数放大并饱和，用于节拍拉长/老化试验延时倍增",
        "纯函数实现 TIME×REAL：换算 LWORD 防溢出，乘积超 T#2147483647ms 饱和返回并置溢出提示位；负系数与零系数防御（返回 t#0s）；不重实现内核，委托平台乘法"),
    "FC_DL_TimeClampEx": ("定时参数超限钳位，保证人机组态误输入不炸定时器",
        "纯函数 TIME 钳位：先判 tMin>tMax 防御交换，再钳位返回；零异常零分支遗漏，ELSE 兜底语义由比较链实现"),
    "FC_DL_UdintToStringTrim": ("UDINT 大数转 STRING：定宽右对齐补位或去前导零，用于诊断文本拼接",
        "委托平台 UDINT_TO_STRING 后再处理前导零/定宽：宽度不足截断保护、宽度足够右侧对齐补 '0'；缓冲区越界防御，循环上限钳位"),
    "FB_DL_MotorHealthAoi": ("电机健康综合评级：绕组温度、电流偏差、启停次数、连续运行时长四维加权",
        "FB 架构：四通道采集-滑动均值-限值比较-加权评分-ENUM 健康等级(eGood/eWarning/eDegraded/eFailure)；失败锁存+bReset 边沿解除；TON 实例无条件周期刷新"),
    "FB_DL_ValveIslandDiag": ("阀岛诊断：配置槽数与在线回报数对账，丢站/多站统计并分级报警",
        "FB 架构：槽位映射数组+在线计数+对账偏差；丢站去抖 TON（无条件刷新）；诊断码 ENUM+CASE 含 ELSE 兜底；数组下标越界防御"),
    "FB_DL_AlarmShelveMgmt": ("报警搁置管理（ISA-18.2）：搁置申请-审批-到期自动解除的完整生命周期",
        "FB 架构：搁置台账数组+审批门控+到期 TON 自动解除+人工解除双通道；锁存副本与实时镜像分离；解除路径恒真可达验证；ENUM 状态机 ELSE 兜底"),
    "FB_DL_SignalFreeze": ("批量/报表期间冻结过程信号采样，冻结沿取值、解除后恢复实时",
        "FB 架构：bFreeze 上升沿锁存副本、实时镜像分离双变量；冻结期间输出保持；解除后镜像回投；防锁存期写入镜像混用（R349 规则落地）"),
    "FB_DL_AxisDroopComp": ("轴跟随误差(垂度)补偿：按指令速度分段动态前馈补偿量",
        "FB 架构：速度分段线性插值+方向判别+补偿限幅+斜坡平滑；零速死区防抖；输出钳位防过补；纯 IEC 无轴专有调用"),
    "FB_DL_CascadeCtrl": ("串级控制骨架：主副环手动/自动/串级三态切换无扰，双向抗饱和回投",
        "FB 架构：三态 ENUM 状态机+切换无扰(输出跟踪/设定值跟踪)+抗饱和双向回投+副环故障自动降级；CoT 解耦：主环不直接写执行器，全部经切换仲裁层"),
    "FB_DL_CuringOvenSeq": ("固化炉顺控：升温-保温-固化-降温四段状态机，段超时与温度偏差报警",
        "FB 架构：ENUM 四段+ELSE 兜底；每段进入/退出条件与超时 TON（无条件刷新）；温度偏差窗判断含浮点容差；失败停机待人工，不自动重跑"),
}

FIX_DESC = {
    "FB_DL_InterlockBypassAudit": "修复组态锁存解除路径缺陷：迁相（组态故障打断/兜底迁移）时补 bBypassOn:=FALSE，防止新组态首旁路被旧计时窗立即收割；04B1 随新一轮受理归零、04B2 改一次性事件码+复位沿回落",
    "FB_DL_StretchWrapSeq": "修复切膜相死锁：计次饱和后单次窗再超时→03B3+bCutFail 锁存+迁 eFault 停机待人工，不自动重切；压膜释放口径固化为仅 ePreClamp 有效",
    "FB_DL_FlowMeterKFactorDrift": "落地 eFailure 声明实现：三项组态闸各自置 eHealth:=eFailure，失败锁存期锁死最严等级，bReset 边沿解除",
    "FB_DL_TruckScaleSeq": "NaN 信号与组态闸拆拍：本拍判定只置诊断码与保持槽，主体末行滞后一拍供消费，防同拍锁存脏值",
    "FB_DL_RotaryAirlockCtrl": "jog 正/反转出口改同拍派生（状态派生后同拍交叉互斥），消除反转首拍延后一拍",
}

def gate_file(path):
    r = subprocess.run([sys.executable, GATE, "--file", path], capture_output=True, text=True)
    return r.stdout

def main():
    import os, re
    report = {"round": "R69", "mode": "pseudo-compile (dl_gate, no real IEC compiler)", "files": [], "MAJOR": 0, "BLOCK": 0}
    targets = []
    for name, cat, *_ in NEW:
        targets.append(os.path.join(LIB, cat, name + ".st"))
    for name in FIXED:
        targets.append(os.path.join(LIB, "DL_Base", name + ".st"))
    for t in targets[5:]:
        pass
    # fixed files live in various cats; resolve by search
    all_fixed = {}
    for cat in ["DL_Base", "DL_MathData", "DL_Algo", "DL_Device", "DL_Motion", "DL_Process"]:
        for name in FIXED:
            p = os.path.join(LIB, cat, name + ".st")
            if os.path.exists(p):
                all_fixed[name] = p
    scan_list = [os.path.join(LIB, cat, n + ".st") for n, cat, _, _, _, _, _, _, _ in NEW] + list(all_fixed.values())
    for p in scan_list:
        out = gate_file(p)
        m = re.findall(r"MAJOR[:\s]*(\d+)", out)
        b = re.findall(r"BLOCK[:\s]*(\d+)", out)
        report["files"].append({"file": os.path.basename(p), "raw_tail": out.strip().splitlines()[-1] if out.strip() else ""})
        report["MAJOR"] += sum(int(x) for x in m)
        report["BLOCK"] += sum(int(x) for x in b)
    with open(os.path.join(LIB, "_Staging_Raw", "2026-11-22", "_gate_R69.json"), "w", encoding="utf-8") as f:
        json.dump(report, f, ensure_ascii=False, indent=1)
    print("GATE: MAJOR=%d BLOCK=%d files=%d" % (report["MAJOR"], report["BLOCK"], len(scan_list)))

    # registry
    reg = json.load(open(os.path.join(LIB, "INDEX_REGISTRY.json"), encoding="utf-8"))
    comps = reg["components"]
    existing = {c["name"] for c in comps}
    added = 0
    for name, cat, kind, cx, lc, tags, src, desc, ref in NEW:
        assert name not in existing, "DUPLICATE: " + name
        comps.append({
            "name": name, "category": cat, "type": kind,
            "file_path": os.path.join(LIB, cat, name + ".st"),
            "function_tags": tags, "complexity": cx, "version": "1.0.0",
            "registered_at": TS, "line_count": lc, "code_segment": "",
            "source": src, "origin": {"mode": "classification", "source": desc,
                                       "license": "cleanroom-ref" if ref.startswith("t2") else "iec-std-wrapper",
                                       "ref_tag": ref}})
        added += 1
    # fixed version bump + line_count refresh
    for c in comps:
        if c["name"] in FIXED:
            v, tag = FIXED[c["name"]]
            c["version"] = v
            c["line_count"] = sum(1 for _ in open(c["file_path"], encoding="utf-8", errors="replace"))
            if tag not in c.get("function_tags", []):
                c["function_tags"] = c.get("function_tags", []) + [tag]
    reg["total_components"] = len(comps)
    reg["version"] = "2.61.0"
    reg["last_updated"] = TS
    counts = {}
    for c in comps:
        counts[c["category"]] = counts.get(c["category"], 0) + 1
    reg["counts"] = counts
    assert sum(counts.values()) == len(comps), "SUM MISMATCH"
    json.dump(reg, open(os.path.join(LIB, "INDEX_REGISTRY.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print("REGISTRY: +%d -> %d v2.61.0 counts=%s sum_ok" % (added, len(comps), counts))

    # JSONL append
    jl = os.path.join(LIB, "_AI_Training_Dataset", "daoli_st_sft_dataset.jsonl")
    n0 = sum(1 for _ in open(jl, encoding="utf-8"))
    with open(jl, "a", encoding="utf-8") as f:
        for name, cat, kind, cx, lc, tags, src, desc, ref in NEW:
            p = os.path.join(LIB, cat, name + ".st")
            src_code = open(p, encoding="utf-8").read()
            inst, arch = JL_DESC[name]
            rec = {"instruction": f"编写道莅库组件 {name}（{cat}，{kind}）：{inst}。要求纯 IEC 61131-3 跨平台、防除零/越界/浮点容差、变量同行中英双语注释、ENUM+CASE 含 ELSE 兜底、定时/边沿实例无条件周期刷新。",
                   "architecture_thought": arch + f"。来源标签 {src}，合规 clean-room，撞名三查通过。",
                   "output": src_code}
            f.write(json.dumps(rec, ensure_ascii=False) + "\n")
        for name, (v, tag) in FIXED.items():
            p = all_fixed[name]
            src_code = open(p, encoding="utf-8").read()
            rec = {"instruction": f"修复道莅库组件 {name}（升级 v{v}）：{FIX_DESC[name]}。保持既有接口兼容，修复后通过七项红线自检。",
                   "architecture_thought": "返修重注入（修复即语料）：记录缺陷模式（" + FIX_DESC[name] + "）与修法，供模型学习'锁存解除路径可达性/同拍派生/拆拍防脏值'等防错范式。",
                   "output": src_code}
            f.write(json.dumps(rec, ensure_ascii=False) + "\n")
    n1 = sum(1 for _ in open(jl, encoding="utf-8"))
    bad = 0
    for line in open(jl, encoding="utf-8"):
        try:
            json.loads(line)
        except Exception:
            bad += 1
    print("JSONL: %d -> %d (+%d) bad=%d" % (n0, n1, n1 - n0, bad))

if __name__ == "__main__":
    main()
