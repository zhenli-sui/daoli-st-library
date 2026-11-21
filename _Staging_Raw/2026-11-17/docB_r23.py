# -*- coding: utf-8 -*-
"""Doc B: four VERSION.md + four MANUAL interface tables."""
import json, re

PINS = json.load(open("C:/Library/_Staging_Raw/2026-11-17/pins_r23.json", encoding="utf-8"))

def rd(p): return open(p, encoding="utf-8").read()
def wr(p, t): open(p, "w", encoding="utf-8", newline="").write(t)

def pin_table(name):
    d = PINS[name]
    rows = ["| 引脚 | 方向 | 类型 | 说明 |", "|---|---|---|---|"]
    for n, ty, zh in d["VAR_INPUT"]:
        rows.append("| `%s` | IN | `%s` | %s |" % (n, ty, zh))
    for n, ty, zh in d["VAR_OUTPUT"]:
        rows.append("| `%s` | OUT | `%s` | %s |" % (n, ty, zh))
    return "\n".join(rows)

BRIEF = {
 "FC_DL_VaporPressureSat": "饱和水蒸气压计算（Magnus-Tetens 过水面参数化，焓湿图全参族公式唯一属主件）",
 "FC_DL_HumidityRatioCalc": "含湿量计算（水汽分压反算 W = 0.622·pv/(p−pv)，饱和压取族属主）",
 "FC_DL_WetBulbTempCalc": "湿球温度估算（Stull 2011 湿度计方程迭代；**v1.0.1 挂账警示：R24 立项修迭代格式前禁用于生产**）",
 "FC_DL_RhFromDewPoint": "露点反算相对湿度（Magnus 反解，与属主件同口径）",
 "FC_DL_MixAirStateCalc": "回风/新风混合点状态计算（质量守恒加权 + 内联混合焓 + 结露预警，v1.0.1 补六输入非有限闸）",
 "FB_DL_HealthAggregator": "多源 NE107 健康聚合仲裁（至多 16 路\"最差者胜\"，HMI 健康横幅单一事实源，T2-8 落地）",
 "FB_DL_OvenDoorInterlock": "烘箱炉门-氮气-温区三联锁（先氮气置换后开门）",
 "FB_DL_ChamberGateValve": "真空腔闸阀互锁互斥控制",
 "FB_DL_RobotGripVerify": "机械手夹持确认与掉片判据（真空/夹爪双反馈置位校验）",
 "FB_DL_FilterDpMonitor": "过滤器压差寿命监视（压差趋势 + 滤芯更换预警，NE107 健康出口）",
 "FB_DL_TankN2BlanketCtrl": "储罐氮封压力双分程（低压补氮比例段 / 高压泄放开关段，互斥断言；**R24 挂账：分界迟滞回差待补**）",
 "FB_DL_ElectrolyteDosingSeq": "电解液定量注液 ISA-88 节拍链（抽液→称重→粗注→细注→静置，中止两段化，v1.0.1 补确认窗/惰转窗组态闸）",
 "FB_DL_NailMachineSeq": "打钉机送钉-打钉顺控站",
 "FB_DL_LamHeaterZoneSync": "层压机加热板多温区同步跟随（区差阈值 + 链速联动）",
 "FB_DL_SteamCondensatePot": "凝液罐液位-排放顺控（液位双限 + 排水阀间歇）",
 "FB_DL_AirCompDutyN2": "空压机/制氮机组联产轮值（负荷排序 + 优先级投切）",
 "FB_DL_BoilerThreeElement": "锅炉三冲量给水控制（水位主回 PID + 蒸汽前馈 + 给水反馈比偏诊断，手/自无扰切换）",
 "FB_DL_HumidityOverride": "除湿优先模式仲裁（覆盖触发/释放双确认窗 + 迟滞回差，v1.0.1 注释对齐）",
 "FB_DL_WaferCountAxis": "晶圆计数轴（编码器分频 + 片位同步）",
 "FB_DL_BagFeedDancerSync": "制袋供膜摆辊同步（线速前馈 + 摆辊 PI + 抗饱和；v1.0.1 补拓扑语义假设留档）",
}
GROUPS = {
 "DL_Algo": "T1-2 焓湿图原子族（族属主 VaporPressureSat，族内其余件一律调用取饱和压）",
 "DL_Device": "健康联锁族（T2-8 NE107 多源聚合 + ROADMAP P1 设备保护）",
 "DL_Process": "行业工艺站（锂电/光伏/公用工程/锅炉/暖通，ROADMAP P1）",
 "DL_Motion": "运动工艺延伸（ROADMAP P1：半导体计数轴 / 包装摆辊同步）",
}
BATCH = {
 "DL_Algo": (["FC_DL_VaporPressureSat","FC_DL_HumidityRatioCalc","FC_DL_WetBulbTempCalc","FC_DL_RhFromDewPoint","FC_DL_MixAirStateCalc"],
             "v1.11.0", "v1.10.0", 43, "3 件终审修复（WetBulb v1.0.1 挂账警示 / MixAir v1.0.1 闸门补全 / DewPointCalc·HumidAirEnthalpy v1.0.1 属主转移声明）"),
 "DL_Device": (["FB_DL_HealthAggregator","FB_DL_OvenDoorInterlock","FB_DL_ChamberGateValve","FB_DL_RobotGripVerify","FB_DL_FilterDpMonitor","FB_DL_TankN2BlanketCtrl"],
             "v0.13.0", "v0.12.0", 67, "HealthAggregator 主控修注释占位符后终审 PASS（0348 组态错误路径推演过）；TankN2BlanketCtrl 终审挂账 R24（分界迟滞回差）"),
 "DL_Process": (["FB_DL_ElectrolyteDosingSeq","FB_DL_NailMachineSeq","FB_DL_LamHeaterZoneSync","FB_DL_SteamCondensatePot","FB_DL_AirCompDutyN2","FB_DL_BoilerThreeElement","FB_DL_HumidityOverride"],
             "v0.13.0", "v0.12.0", 41, "BoilerThreeElement 主控修未声明标识符（fSteamFlow→fSteamFlowTh）后终审 PASS（前馈符号与 PID 跟踪反算自洽推演过）；ElectrolyteDosingSeq / HumidityOverride 终审升 v1.0.1；`FB_DL_BatchTransferSeq` v1.0.2（R22 挂账中止两段化闭合，见修订记录）"),
 "DL_Motion": (["FB_DL_WaferCountAxis","FB_DL_BagFeedDancerSync"],
             "v0.13.0", "v0.12.0", 32, "BagFeedDancerSync 终审补拓扑语义假设留档升 v1.0.1（符号经「抽膜」拓扑推演为负反馈正确）"),
}

# ---------- VERSION.md x4 ----------
for cat, (names, ver, oldver, total, note) in BATCH.items():
    p = "C:/Library/%s/VERSION.md" % cat
    t = rd(p)
    t = t.replace("| 子库版本 / Sublibrary Version | **%s** |" % oldver,
                  "| 子库版本 / Sublibrary Version | **%s** |" % ver, 1)
    # 库总版本行
    t = re.sub(r"\| 库总版本 / Library Version \| v2\.\d+\.\d+ \|",
               "| 库总版本 / Library Version | v2.12.0 |", t, count=1)
    # 组件总数行（R86 断言口径：以注册表 counts 为准）
    m = re.search(r"\| 组件总数 / Components \| \*\*(\d+)\*\*", t)
    claimed = int(m.group(1)) if m else -1
    t = re.sub(r"\| 组件总数 / Components \| \*\*\d+\*\*（[^）]*） \|",
               "| 组件总数 / Components | **%d**（以注册表 counts 为准，R23 校正口径） |" % total, t, count=1)
    t = t.replace("| 发布日期 / Release Date | 2026-11-16 |",
                  "| 发布日期 / Release Date | 2026-11-17 |", 1)
    sec = ["\n## %s ｜ 2026-11-17 ｜ R23 行业纵深轮 %d 件（%s）\n" % (ver, len(names), GROUPS[cat])]
    for n in names:
        sec.append("- `%s`：%s（引脚见 MANUAL 接口表；码位见 .st 头注释码位总账）。" % (n, BRIEF[n]))
    sec.append("\n> **R86 组件数断言**：注册表 counts[%s] = %d，本文档原记 %d%s；本轮已校正为注册表口径。" %
               (cat, total, claimed, "（历史批次漏计，随本节一并校正）" if claimed != total else "（一致）"))
    sec.append("\n> **终审留痕**：%s。\n" % note)
    # 追加位置：插到"## 版本号约定"之前（与既有节序一致），或文件尾
    anchor = "## 版本号约定 / Versioning Policy"
    if anchor in t:
        t = t.replace(anchor, "\n".join(sec) + "\n" + anchor, 1)
    else:
        t = t.rstrip("\n") + "\n" + "\n".join(sec)
    wr(p, t)
    print("VERSION %-12s -> %s (claimed %s -> %d)" % (cat, ver, claimed, total))

# ---------- MANUAL x4 ----------
for cat, (names, ver, oldver, total, note) in BATCH.items():
    p = "C:/Library/MANUAL_DL_%s.md" % cat
    t = rd(p).rstrip("\n")
    sec = ["\n\n---\n", "## R23 批次接口表（R23 追加 · %d 件 · %s ｜ 子库 %s→%s）" % (len(names), GROUPS[cat], oldver, ver), ""]
    for n in names:
        typ = "FUNCTION → BOOL" if n.startswith("FC_") else "FUNCTION_BLOCK"
        sec.append("### %s ｜ %s（%s ｜ %s）" % (n, BRIEF[n].split("（")[0], cat, typ))
        sec.append(pin_table(n))
        sec.append("")
    sec.append("### 续补说明 / Remaining（R23 更新）")
    sec.append("")
    sec.append("> 本节为 R23 新增件接口表（引脚取自 .st 声明区实测抽取，脚本 `pins_r23.json` 留档）；"
               "R23 终审修复件以修订历史为准（v1.0.1 引脚契约零变更）；历史件补录按 R88 节奏（每轮 ≤10 件）继续。")
    t = t + "\n".join(sec) + "\n"
    wr(p, t)
    print("MANUAL DL_%s ok (+%d comps)" % (cat, len(names)))
