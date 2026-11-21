# ROUND_PLAN_R37 — 第 37 轮规划（R36-RESUME 续作，10 件）

生成：2026-11-18 20:56 主控；目标源：`ROUND_PLAN_R36.md` 序号 4~13（R36 已入库 1~3）。按预算令「R214 ≤10 件/轮」压缩。

## 一、盘点

| 口径 | 数值 |
|---|---|
| 总库已注册 | **640 / 10,000**（registry 实测，磁盘 `.st` 640 三向一致） |
| 今日（11-18）已入册 | **121 / 200** |
| 距 500 计划 | 已达成 +140 |
| ROADMAP 未勾 | **190 条 ≥ 30** → 本轮不补条 |
| R36 遗留 | 17 件（序号 4~20），本轮取前 10 件，余 7 件转 R38 |

## 二、本轮 10 个目标

| 序号 | 组件名 | 分类 | 前缀 | 一句话功能 | 来源标签 | 复杂度 | 批次 |
|---|---|---|---|---|---|---|---|
| 4 | `FB_DL_ResonanceTrackNotch` | DL_Algo | FB | 谐振频率在线跟踪与自适应陷波（相位过零判据 + 频率窗钳制 + 松弛回退） | `t1-6-plcopen` | 高 | 1 |
| 5 | `FB_DL_LineShaftClutch` | DL_Motion | FB | 电子 line shaft 离合（相位对齐后咬合/脱开，含咬合斜坡与滑差监视） | `t2-4-s7-motion` | 高 | 1 |
| 6 | `FB_DL_FlyingCutSync` | DL_Motion | FB | 飞剪同步切断（从轴追赶同步窗 + 切窗区间判定 + 回程重装） | `t1-6-plcopen` | 高 | 1 |
| 7 | `FB_DL_WaferCoolChuck` | DL_Device | FB | 静电卡盘吸附-温控联锁（吸附确认后方可投温控，释放须降温至脱附门限） | `t2-2-lbp` | 中 | 1 |
| 8 | `FB_DL_CurtainEFEMZone` | DL_Device | FB | EFEM 作业区光幕分区屏蔽（4 传感器判向 + 屏蔽窗时限 + 屏蔽期自检） | `t1-5-tcopen` | 高 | 1 |
| 9 | `FB_DL_VentPurgeDuty` | DL_Device | FB | 尾气处理双塔轮值切换（吸附/脱附轮换 + 穿透预警 + 单塔故障禁切） | `t2-8-isa88` | 中 | 2 |
| 10 | `FB_DL_SlurryLevelBank` | DL_Device | FB | 浆料罐点式料位巡检组（多实例扇入 + fail-safe 方向审查 + 断线判别） | `t2-8-isa182` | 中 | 2 |
| 11 | `FB_DL_FoupPurgeN2Flow` | DL_Device | FB | FOUP 氮气吹扫流量-露点双判据监视（建立时限 + 露点越窗分级） | `t2-1-lgf-measurement` | 中 | 2 |
| 12 | `FB_DL_CartonErectVacMonitor` | DL_Device | FB | 开箱吸盘真空建立时长趋势诊断（基线 + 衰减趋势 → 吸盘老化预警） | `t2-1-lgf-measurement` | 中 | 2 |
| 13 | `FB_DL_CoderRibbonLife` | DL_Device | FB | 打码色带寿命与浓度衰减监视（次数 + 浓度双口径换带提示） | `t2-1-lgf-technology` | 中 | 2 |

## 三、码位窗口（派单前码字层实测，非 registry code_segment）

| 窗口 | 码位 | 归属 | 占用件 | 实测依据 |
|---|---|---|---|---|
| W1 | `16#02_3_82` | DL_Algo | #4 | `02_3` 已占 38/3C/40/44/4C/50/54/5C~5F/80/81，82 空 |
| W2 | `16#04_0_A2`~`A3` | DL_Motion | #5、#6 | `04_0` 已占 6C/A0/A1，A2/A3 空 |
| W3 | `16#03_2_0B`~`0F` | DL_Device | #7~#11 | `03_2` 已占 00~04/06~0A，0B~0F 空（05 空缺留存，不占用以免与历史重排冲突） |
| W4 | `16#03_2_10`~`11` | DL_Device | #12、#13 | `03_2` 1x 段全空 |

> 口径缺陷记录：registry `code_segment` 仅 62/650 件有值，不可作占用依据；本轮改为头 1504 字节正则实测（入册 R217）。

## 四、批次与依赖

| 批 | 序号 → 件名 | 依赖（均为已注册件） |
|---|---|---|
| 批 1 | 4~8 | `I_DL_MotionAxis` / `E_DL_AxisState` / `I_DL_VacuumGenerator` / `I_DL_TemperatureZone` / `I_DL_LightCurtain` |
| 批 2 | 9~13 | `FB_DL_PulseFlowMeter` / `I_DL_VacuumGenerator`；#9/#10/#13 仅 Standard.library |
| 批 3/4 | 14~20 | 转 R38-RESUME |
