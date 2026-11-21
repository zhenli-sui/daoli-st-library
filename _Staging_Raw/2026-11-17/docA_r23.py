# -*- coding: utf-8 -*-
import re
def rd(p): return open(p, encoding="utf-8").read()
def wr(p, t): open(p, "w", encoding="utf-8", newline="").write(t)

# ---------- 1. ROADMAP ticks ----------
p = "C:/Library/ROADMAP.md"; t = rd(p)
TICKS = ["FB_DL_HumidityOverride", "FB_DL_BoilerThreeElement", "FB_DL_OvenDoorInterlock",
         "FB_DL_WaferCountAxis", "FB_DL_RobotGripVerify", "FB_DL_BagFeedDancerSync",
         "FB_DL_SteamCondensatePot", "FB_DL_AirCompDutyN2", "FB_DL_FilterDpMonitor",
         "FB_DL_TankN2BlanketCtrl", "FB_DL_ElectrolyteDosingSeq", "FB_DL_LamHeaterZoneSync"]
cnt = 0
for name in TICKS:
    pat = "- [ ] `" + name + "`"
    if pat in t:
        t = t.replace(pat, "- [x] `" + name + "`", 1); cnt += 1
    else:
        print("MISS:", name)
lines = t.splitlines(); out = []
for ln in lines:
    for name in TICKS:
        if ln.startswith("- [x] `" + name + "`") and "R23 交付" not in ln:
            ln = ln + "（**R23 交付**）"
    out.append(ln)
t = "\n".join(out) + "\n"
t = t.replace("- [ ] `FB_DL_BatchTransferSeq` 中止时序修复（v1.1 候选）",
              "- [x] `FB_DL_BatchTransferSeq` 中止时序修复（v1.0.2 已修复）", 1)
t = t.replace("**R23 立项，安全相关不与本轮抢时间**。",
              "**R23 已修复（v1.0.2：bAbort 两段化 xCoastStop + tPumpCoastTime 惰转窗→关阀，新故障码 0005_0317，五条验收向量推演通过）**。", 1)
wr(p, t); print("ROADMAP ticked:", cnt, "/12")

# ---------- 2. README badges + R23 block ----------
p = "C:/Library/README.md"; t = rd(p)
t = t.replace("Total%20Components-384%20%2F%2010%2C000-blue", "Total%20Components-404%20%2F%2010%2C000-blue")
t = t.replace("SFT%20Corpus-384%20records-informational", "SFT%20Corpus-404%20records-informational")
r23 = ("> **Round 23（2026-11-17）：行业纵深轮——焓湿图原子族开族 / NE107 多源健康聚合 / 锂电·光伏·半导体·公用工程·锅炉·暖通工艺站 20 件**"
"——DL_Algo 5（**T1-2 OSCAT Building 焓湿图族开族收口**：VaporPressureSat 饱和压族属主 / HumidityRatioCalc / WetBulbTempCalc / RhFromDewPoint / MixAirStateCalc，"
"Magnus-Tetens 常数属主裁定并回写 DewPointCalc·HumidAirEnthalpy 属主转移声明）、DL_Device 6（HealthAggregator **T2-8 NE107 多源聚合落地** / OvenDoorInterlock / ChamberGateValve / "
"RobotGripVerify / FilterDpMonitor / TankN2BlanketCtrl）、DL_Process 7（ElectrolyteDosingSeq ISA-88 节拍链 / NailMachineSeq / LamHeaterZoneSync / SteamCondensatePot / AirCompDutyN2 / "
"BoilerThreeElement 三冲量 / HumidityOverride）、DL_Motion 2（WaferCountAxis / BagFeedDancerSync）；合计 3,754 行；`FB_DL_BatchTransferSeq` 升 v1.0.2（中止两段化，R22 挂账闭合）；"
"registry 384→**404**（v2.12.0，counts 73/148/43/67/32/41），JSONL **404 条全量 sha256 MATCH**，CLASH=NONE，机检 fail=12 全为 E_DL_Ne107Status 属主误报豁免（属主 I_DL_DeviceHealth.st）；"
"**R23 终审 8 件高风险定向抽查：2 PASS / 4 件轻微当场修升 v1.0.1 / 2 件严重挂账 R24**（WetBulb 定点迭代结构性发散 + γ 常数千倍量纲错位；TankN2 分界迟滞回差），主控收口另拦下 2 处编码侧漏（未声明标识符 fSteamFlow、注释省略号占位）；"
"子库版本 DL_Algo v1.11.0 / DL_Device v0.13.0 / DL_Process v0.13.0 / DL_Motion v0.13.0；总库 **v2.12.0 / 404 件**，距 500 冲刺差 **96 件**。\n")
anchor = "距 500 冲刺差 **116 件**。"
assert anchor in t, "README anchor missing"
t = t.replace(anchor, anchor + "\n" + r23, 1)
wr(p, t); print("README ok, badge404:", "404%20%2F%2010%2C000" in t)

# ---------- 3. CHANGELOG v2.12.0 ----------
p = "C:/Library/CHANGELOG.md"; t = rd(p)
entry = ("## v2.12.0 ｜ 2026-11-17 ｜ R23：行业纵深轮——焓湿图原子族 + NE107 多源聚合 + 行业工艺站 20 件 / Round 23 — Psychrometric Atoms, NE107 Aggregation and Industry Process Stations\n\n"
"**阶段**：Phase 1 第二十三轮（T1-2 OSCAT Building 焓湿图族 + T2-8 NE107 + ROADMAP P1 ×14）｜ **新增组件**：20（`DL_Algo` 5 ｜ `DL_Device` 6 ｜ `DL_Process` 7 ｜ `DL_Motion` 2，合计 **3,754 行**）｜ "
"**累计**：**404 / 10,000**（距 500 冲刺差 96）｜ **子库版本**：`DL_Algo` v1.10.0→**v1.11.0**、`DL_Device` v0.12.0→**v0.13.0**、`DL_Process` v0.12.0→**v0.13.0**、`DL_Motion` v0.12.0→**v0.13.0** ｜ "
"**JSONL**：**404 条**，全量 sha256 MATCH ｜ **机检**：fail=12 全为 `E_DL_Ne107Status` 跨文件属主误报豁免（属主 `I_DL_DeviceHealth.st`）｜ **码位**：CLASH=NONE ｜ "
"**修复**：`FB_DL_BatchTransferSeq` v1.0.1→**v1.0.2**（R22 挂账闭合）｜ **终审**：8 件高风险定向抽查，2 PASS / 4 件轻微当场修升 v1.0.1 / 2 件严重挂账 R24 ｜ "
"**属主裁定**：Magnus-Tetens 常数唯一属主 `FC_DL_VaporPressureSat`，`FC_DL_DewPointCalc` / `FC_DL_HumidAirEnthalpy` 头注释追加属主转移声明升 v1.0.1（逻辑零改动）\n\n"
"### 新增 / Added\n\n| 子库 | 组件 | 类型 | 说明 |\n|---|---|---|---|\n"
"| DL_Algo | `FC_DL_VaporPressureSat` / `FC_DL_HumidityRatioCalc` / `FC_DL_WetBulbTempCalc` / `FC_DL_RhFromDewPoint` / `FC_DL_MixAirStateCalc` | FC×5 | 焓湿图原子族（T1-2 OSCAT Building 行为定义 clean-room）：饱和压族属主（Magnus-Tetens 过水面参数化，族内唯一公式源）/ 含湿量 / 湿球温度（Stull 2011 湿度计方程）·**挂账 R24** / 露点反算 RH / 回风新风混合点（质量守恒 + 结露预警） |\n"
"| DL_Device | `FB_DL_HealthAggregator` / `FB_DL_OvenDoorInterlock` / `FB_DL_ChamberGateValve` / `FB_DL_RobotGripVerify` / `FB_DL_FilterDpMonitor` / `FB_DL_TankN2BlanketCtrl` | FB×6 | 健康联锁族：NE107 多源\"最差者胜\"聚合仲裁（T2-8 落地）/ 烘箱炉门三联锁 / 真空腔闸阀互锁 / 机械手夹持确认 / 过滤器压差寿命（NE107 出口）/ 储罐氮封双分程 |\n"
"| DL_Process | `FB_DL_ElectrolyteDosingSeq` / `FB_DL_NailMachineSeq` / `FB_DL_LamHeaterZoneSync` / `FB_DL_SteamCondensatePot` / `FB_DL_AirCompDutyN2` / `FB_DL_BoilerThreeElement` / `FB_DL_HumidityOverride` | FB×7 | 行业工艺站：电解液定量注液 ISA-88 节拍链 / 打钉机顺控 / 层压机多温区同步 / 凝液罐液位排放顺控 / 空压制氮联产轮值 / 锅炉三冲量给水 / 除湿优先仲裁 |\n"
"| DL_Motion | `FB_DL_WaferCountAxis` / `FB_DL_BagFeedDancerSync` | FB×2 | 晶圆计数轴（编码器分频 + 片位同步）/ 制袋供膜摆辊同步（线速前馈 + 摆辊 PI，拓扑假设头注释留档） |\n\n"
"### 修复 / Fixed（R23 终审 + 承接 R22 挂账）\n\n| 组件 | 版本 | 级别 | 缺陷 | 处置 |\n|---|---|---|---|---|\n"
"| `FB_DL_BatchTransferSeq` | v1.0.1→v1.0.2 | 中等（R22 挂账） | bAbort「先停泵后关阀」缺物理时序分隔 | 两段化：xCoastStop + tPumpCoastTime 惰转窗→关阀，新故障码 0005_0317，五条验收向量推演通过 |\n"
"| `FC_DL_MixAirStateCalc` | v1.0.0→v1.0.1 | 轻微 | 段 2 非有限闸漏查 fOaFrac（NaN 直通 bValid=TRUE） | 当场修：闸门补全六输入，契约不变 |\n"
"| `FB_DL_HumidityOverride` | v1.0.0→v1.0.1 | 轻微 | 注释-实现漂移（「保持末态」vs 实现「转故障退出覆盖 + 01EE 显式声明」） | 当场修：注释按实现口径对齐，逻辑零改动 |\n"
"| `FB_DL_ElectrolyteDosingSeq` | v1.0.0→v1.0.1 | 轻微 | tSettleTime > 步 1 超时 / tCoastTime=0 无组态闸（结构性超时/中止永不收口） | 当场修：段 3 补组态一致性闸归 0318，契约不变 |\n"
"| `FC_DL_DewPointCalc` / `FC_DL_HumidAirEnthalpy` | v1.0.0→v1.0.1 | 文档 | Magnus-Tetens 常数属主裁定回写 | 头注释属主转移声明，逻辑零改动 |\n"
"| `FC_DL_WetBulbTempCalc` | v1.0.0→v1.0.1（警示） | **严重（挂账 R24）** | γ 常数 1000 倍量纲错位 + 定点迭代在 e_s'(Tw)/(γ·p)>1 区间结构性发散，正常工况误报 2F11 | 头注释挂账警示（禁用于生产），R24 立项改二分法 + 量纲组合表纪律 |\n"
"| `FB_DL_TankN2BlanketCtrl` | v1.0.0（挂账 R24） | 轻微→中等 | 高压分界无迟滞回差，bVentCmd 分界处逐拍抖振（0184 仅提示不消振） | 挂账 R24：复用 DL_N2_BAND_TOL 作回差，补验收向量 |\n\n"
"> **R23 编码侧漏（主控收口拦下）**：①`FB_DL_BoilerThreeElement` 两处未声明标识符 `fSteamFlow`（输入名实为 `fSteamFlowTh`，编译阻断级，收口时修正）；②`FB_DL_HealthAggregator` 调用示例注释含省略号占位符（语义化改写）。\n\n")
marker = "*Last updated: 2026-11-16（R22 追加 v2.11.0 条目）*"
assert marker in t, "CHANGELOG marker missing"
t = t.replace(marker, entry + "*Last updated: 2026-11-17（R23 追加 v2.12.0 条目）*", 1)
wr(p, t); print("CHANGELOG ok")

# ---------- 4. SOURCE_HUNTING_MATRIX ----------
p = "C:/Library/SOURCE_HUNTING_MATRIX.md"; t = rd(p)
lines = t.splitlines(); last = -1
for i, ln in enumerate(lines):
    if re.match(r"^- \*{0,1}R2\d+ ?实 ?测", ln) or re.match(r"^- ?\*\*R2\d+ 实测", ln) or ln.startswith("- R") and "实测" in ln[:14]:
        last = i
print("matrix anchor:", last + 1)
r23m = ("- **R23 实测**：本轮 20 件跨 **T1 一族开族收口 + T2 一组落地 + ROADMAP P1 ×12 勾销 + 自研线**——T1-2 OSCAT Building **焓湿图原子族 ✔ 开族收口 5 件**"
"（VaporPressureSat 饱和压族属主 / HumidityRatioCalc / WetBulbTempCalc / RhFromDewPoint / MixAirStateCalc，Magnus-Tetens 常数属主裁定并回写 DewPointCalc·HumidAirEnthalpy 属主转移声明）｜"
"T2-8 NAMUR NE107 **多源健康聚合落地 2 件**（HealthAggregator 最差者胜仲裁 + FilterDpMonitor NE107 出口）｜ROADMAP P1 待办 12 条勾销"
"（OvenDoorInterlock / ChamberGateValve / RobotGripVerify / ElectrolyteDosingSeq / LamHeaterZoneSync / SteamCondensatePot / AirCompDutyN2 / TankN2BlanketCtrl / "
"WaferCountAxis / BagFeedDancerSync / BoilerThreeElement / HumidityOverride，另自研线 NailMachineSeq）｜**检索预算用 1/3**（Stull 2011 湿度计方程原文核对）｜"
"**状态列结论：T1-2 行备注「焓湿图子族 ✔（子族收口，非整组挖尽）」；T2-8 行备注「NE107 多源聚合已落地」；无 ☐→◐ 开组、无整组 ◐→✔ 收口，未触碰任何已收口组。**")
if last >= 0:
    lines.insert(last + 1, r23m)
    wr(p, "\n".join(lines) + "\n"); print("MATRIX ok")
else:
    print("MATRIX: no anchor found")
