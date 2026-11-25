# -*- coding: utf-8 -*-
"""R73 文档增量更新（全部追加式，不整篇重写）。"""
import io, os, json, datetime

LIB = r"C:\Library"
TS = "2026-11-23"
TOTAL, SFT = 1238, 1277
COUNTS = "1238（Base 157 / MathData 299 / Algo 138 / Device 224 / Motion 128 / Process 292）"


def read(p):
    return io.open(p, encoding="utf-8", errors="replace").read()


def write(p, s):
    io.open(p, "w", encoding="utf-8", newline="\n").write(s)


def append(p, s):
    with io.open(p, "a", encoding="utf-8", newline="\n") as f:
        f.write(s)


# 1) README 徽章 + 摘要行
p = os.path.join(LIB, "README.md")
s = read(p)
s = s.replace("Total%20Components-1218%20%2F%2010%2C000", "Total%20Components-1238%20%2F%2010%2C000")
s = s.replace("SFT%20Corpus-1252%20records", "SFT%20Corpus-1277%20records")
s = s.replace("**Total Components: 1218 / 10,000 (12.18%)**", "**Total Components: 1238 / 10,000 (12.38%)**")
s = s.replace("**Version: v2.64.0**", "**Version: v2.65.0**")
s = s.replace("**SFT 语料: 1252 条**", "**SFT 语料: 1277 条**")
anchor = "> **R72（2026-11-23）**："
add = ("> **R73（2026-11-23）**：**25 件交付（20 新件 + 5 点修）**——复杂件 6（Motion：FlyingSawSyncSeq·CamTableOnlineBlend｜Algo：FanSurgeMarginCalc｜Device：EmergencyStopChainDiag｜Process：TankFarmTransferSeq·ConveyorAccumGateSeq）"
       "+ 简单件 14（MathData 5：MovingRangeCalc·PressureAltitudeCalc·SoundSpeedAirCalc·ExpMovingAvgCalc·TorqueUnitConvert｜Base 3：BitRotateEx·SignalRouteMatrix·SignalEdgeDelayEx｜Device 2：SensorSupplyWatch·ValveCycleCountBank｜Algo 2：TcToFilterCoeff·DeadtimeTapCalc｜Process 2：HandAutoModeGateBank·OperatorAckBank）"
       "+ 5 件点修（VaporPressureSat 族四路全回执：HumidityRatioCalc·MixAirStateCalc·RhFromDewPoint·DewPointToPpmV·NightPurgeCtrl）；总库 1,218→**1,238**，SFT **1,277**；"
       "**L2 闸 25/25 PASS = 100%**（修掉 1 处系统性 E007「FB 尾部误用 END_FUNCTION」+ 1 处非标准 TIME_TO_DWORD）；机检 20/20 CLEAN；审校 17 PASS / 3 MAJOR 返修 / 去重拦截 0；"
       "开源队列 **29 条（绿区 28）**，溯源命中 78.6%；零检索轮（WebSearch 0/3）。\n")
if anchor in s and "R73（2026-11-23）" not in s:
    s = s.replace(anchor, add + anchor, 1)
write(p, s)
print("README ok")

# 2) CHANGELOG
p = os.path.join(LIB, "CHANGELOG.md")
entry = """## v2.65.0 — 2026-11-23（R73 二十件入册 + VaporPressureSat 族四路全回执点修 ｜ 零检索轮 ｜ 五专家生产线首轮满编）

### Added（20 件：DL_Motion 2 / DL_Algo 2 / DL_Device 2 / DL_Process 4 / DL_MathData 5 / DL_Base 3）
- **复杂件 6**：`FB_DL_FlyingSawSyncSeq`（C4 飞锯同步切入-切割-返回序列，速比按主轴位置增量生成）｜`FB_DL_CamTableOnlineBlend`（C4 凸轮表在线渐变切换，权重线性推进 + 相位连续合成）｜`FB_DL_FanSurgeMarginCalc`（C3 风机喘振裕度在线计算 + 分级预警）｜`FB_DL_EmergencyStopChainDiag`（C3 急停回路多节点断链定位）｜`FB_DL_TankFarmTransferSeq`（C4 多罐收发转罐序列，泵阀联锁 + 路径互斥 + 关阀超时闸）｜`FB_DL_ConveyorAccumGateSeq`（C3 积放闸门三态编排）
- **简单件 14**：MathData 5（`FC_DL_MovingRangeCalc` 滑动极差 / `FC_DL_PressureAltitudeCalc` ISA 气压↔海拔 / `FC_DL_SoundSpeedAirCalc` 空气声速 / `FC_DL_ExpMovingAvgCalc` 无状态 EMA / `FC_DL_TorqueUnitConvert` 转矩单位换算）｜Base 3（`FC_DL_BitRotateEx` 跨位宽循环移位 / `FB_DL_SignalRouteMatrix` 2×N 路由矩阵 / `FB_DL_SignalEdgeDelayEx` 双边沿延迟）｜Device 2（`FB_DL_SensorSupplyWatch` 供电窗口 + NE43 / `FB_DL_ValveCycleCountBank` 多阀计数台账）｜Algo 2（`FC_DL_TcToFilterCoeff` 时间常数→滤波系数 / `FC_DL_DeadtimeTapCalc` 死区时间→拍数向上取整）｜Process 2（`FB_DL_HandAutoModeGateBank` 手自动权限门组 / `FB_DL_OperatorAckBank` 成组确认组）

### Fixed（5 件，VaporPressureSat 族回执契约）
- `FC_DL_HumidityRatioCalc` / `FC_DL_MixAirStateCalc` / `FC_DL_RhFromDewPoint` / `FC_DL_DewPointToPpmV` / `FB_DL_NightPurgeCtrl`：8 处属主调用由部分回执改为 **fPvSat/bClamped/eErr/bError/bValid 四路全回执**（R381/R397 契约口径），FALSE 拍并入各件既有兜底码；`FB_DL_NightPurgeCtrl` 同时修正 `LREAL_TO_REAL` 方向错误为 `REAL_TO_LREAL`。

### Changed（质量闸）
- **L2 编译闸 25/25 PASS（100%）**：修掉 6 件复杂件系统性 E007（`FUNCTION_BLOCK` 尾部误写 `END_FUNCTION`）、`CamTableOnlineBlend` 非标准 `TIME_TO_DWORD` 扩展（改 `TIME_TO_LREAL`）。
- 审校：17 PASS / 3 MAJOR 返修（飞锯锚点未来窗、凸轮渐变非有限分支冻结、转罐关阀超时闸）/ 4 件补同族互引；去重拦截 0（名称道/指纹道均 0 命中）。

"""
p = os.path.join(LIB, "CHANGELOG.md")
s = read(p)
mark = "## v2.64.0 — 2026-11-23"
if "v2.65.0" not in s:
    s = s.replace(mark, entry + mark, 1)
    write(p, s)
print("CHANGELOG ok")

# 3) 六库 VERSION 追加
vers = {
    "DL_Base": ("1.33", "FC_DL_BitRotateEx / FB_DL_SignalRouteMatrix / FB_DL_SignalEdgeDelayEx"),
    "DL_MathData": ("1.34", "FC_DL_MovingRangeCalc / FC_DL_PressureAltitudeCalc / FC_DL_SoundSpeedAirCalc / FC_DL_ExpMovingAvgCalc / FC_DL_TorqueUnitConvert + FC_DL_DewPointToPpmV 点修"),
    "DL_Algo": ("1.34", "FB_DL_FanSurgeMarginCalc / FC_DL_TcToFilterCoeff / FC_DL_DeadtimeTapCalc + 3 件全回执点修"),
    "DL_Device": ("1.27", "FB_DL_SensorSupplyWatch / FB_DL_ValveCycleCountBank"),
    "DL_Motion": ("1.26", "FB_DL_FlyingSawSyncSeq / FB_DL_CamTableOnlineBlend"),
    "DL_Process": ("1.32", "FB_DL_TankFarmTransferSeq / FB_DL_ConveyorAccumGateSeq / FB_DL_HandAutoModeGateBank / FB_DL_OperatorAckBank + FB_DL_NightPurgeCtrl 点修"),
}
for lib, (v, items) in vers.items():
    p = os.path.join(LIB, lib, "VERSION.md")
    if not os.path.isfile(p):
        print("no VERSION", lib); continue
    s = read(p)
    if "R73" in s:
        continue
    append(p, "\n## v%s — 2026-11-23（R73）\n\n- 新增/变更：%s\n- L2 编译闸：PASS（RuSTy 1.0.8 串行）\n" % (v, items))
print("VERSION ok")

# 4) MATRIX 台账
p = os.path.join(LIB, "SOURCE_HUNTING_MATRIX.md")
append(p, "\n| R73 | 2026-11-23 | brOscatLib(MIT)/AixOCAT(MIT) 等 | 3 仓 | 29 条（绿区 28 / WTFPL 1） | 78.6%（22/28 件命中候选语义） | F_LIN/F_POWER/SCALE/HYPOT/CABS → FC_DL_SoundSpeedAirCalc / FC_DL_PressureAltitudeCalc 等 | ✔ 已回写 |\n")
print("MATRIX ok")

# 5) EVOLOG
p = os.path.join(LIB, "AGENT_EVOLUTION_LOG.md")
append(p, """
## R73（2026-11-23）五专家生产线首轮满编

- **产出**：20 新件 + 5 点修，总库 1,218→1,238，L2 闸 25/25 PASS（100%），机检 20/20 CLEAN，审校 17 PASS / 3 MAJOR 返修 / 去重拦截 0。
- **系统性缺陷（新发现，已固化红线）**：① FB 尾部误写 `END_FUNCTION`（6/6 复杂件同型，E007）→ **R13**：`FUNCTION_BLOCK` 必须 `END_FUNCTION_BLOCK` 收尾，禁与 `FUNCTION` 混用。② 非标准 `TIME_TO_DWORD`（库内 3 处残留）→ **R14**：TIME 域换算统一 `TIME_TO_LREAL/TIME_TO_DINT`，禁 `TIME_TO_DWORD/TIME_TO_UDINT`。③ 属主多出参 FC 仅收部分回执（E032/E037 双码）→ 全回执升格为交付资格项。
- **并行架构首轮验证**：猎人采集∥总监规划、编码∥编译闸、审校∥收口脚本，省约 12 分钟；编译链仍全串行（假阳性教训）。
""")
print("EVOLOG ok")

# 6) ROADMAP 小结
p = os.path.join(LIB, "ROADMAP.md")
append(p, """
## R73 构建轮小结（2026-11-23）

> **R73 小结**：25 件交付（20 新件：复杂 6 + 简单 14；5 件 VaporPressureSat 族全回执点修），总库 1,218→**1,238**，v2.65.0，SFT 1,252→**1,277**，L2 闸 **25/25 PASS = 100%**，机检 20/20 CLEAN，审校 17 PASS / 3 MAJOR 就地返修 / 去重拦截 0，开源队列 29 条（绿区 28）溯源占比 78.6%。零检索轮。
> **R74 待办（P0）**：① 存量缺陷账：`dl_gate --hours 1` 全量扫描暴露 `F_DECL_MISSING`（`_eState`/`__ISVALIDREF`/`_bAnyAlarm` 等）与 `R6_CASE_NO_ELSE` 一批 BLOCK，需一次性专项回写（估算 ≥40 件）；② `FB_DL_DisturbanceObserver` 缺 `END_FUNCTION_BLOCK` 收尾（NO_TAIL 检出）复核；③ L2 闸常态化；④ 值守三项第 5 轮顺延（配 remote 触发 MatIEC CI / oss_harvest token / GATE MAJOR 人核）。
""")
print("ROADMAP ok")
