# ROUND_PLAN_R95（2026-11-25 第 8 轮 · S1 规划查重官）

> 交付对象：S3 编码席（本表是其唯一输入）。本轮 40 件 = 4 族 × 10 件连号，四查全部实测留痕。
> 复杂度配额：复杂 **4**（C3×3 + C4×1）/ 简单 **36**（C1×2 + C2×34），满足「复杂 ≤4、简单 ≥36」硬约束。

## 一、四族名与目标目录

| 族 | 族名 | 目标目录 | 序号段 | 来源标签 | 在册数 → 轮后 |
|---|---|---|---|---|---|
| A | 五轴 CNC RTCP 插补几何与刀具补偿族 | `C:\Library\DL_Motion` | 1–10 | DLF-A-RTCP | 195 → 205 |
| B | 求根与一维极小单步算子族 | `C:\Library\DL_Algo` | 11–20 | DLF-B-ROOTSTEP | 197 → 207 |
| C | 七段数码管字形译码与多路扫描族 | `C:\Library\DL_Base` | 21–30 | DLF-C-SEVENSEG | 233 → 243 |
| D | 在线水质分析仪测量与标定诊断族 | `C:\Library\DL_Device` | 31–40 | DLF-D-WATERANA | 352 → 362 |

选域理由（为什么是真空域）：四族的**族核心词根**在全库 2,041 件名称做 CamelCase 分词后检索，命中数为 0（逐词实测见 §3.1）。DL_Motion 补最薄子库优先；DL_Algo 取「数值单步算子」这一库内空白层（库内只有整迭代 `FC_DL_NewtonRaphson`，无括号法/区间收缩单步算子）；DL_Base 取「显示字形译码」这一纯位型变换带（库内位域件全部集中在掩码/移位/校验，无字形语义）；DL_Device 取「液体分析仪测侧与标定」带（库内仪表件集中在流量/液位/称重/功率，pH/ORP/浊度/余氯测侧为 0）。

## 二、磁盘差集前置结论（双向差集）

- `INDEX_REGISTRY.json`：`total_components = 2041`，`components` 数组 **2,041 条**，名称唯一 2,041。
- 磁盘 `.st` 实点：DL_Base 233 + DL_MathData 454 + DL_Algo 197 + DL_Device 352 + DL_Motion 195 + DL_Process 610 = **2,041**。
- **registry N ≡ 磁盘 M，双向差集 k = 0**（only_in_registry = 0，only_on_disk = 0，category 不一致 = 0）。→ 本轮 40 件全部为新增写盘，无「规划已存在文件」风险。
- ⚠️ 台账缺陷挂账（交 S0/S5，不由本席修）：`INDEX_REGISTRY.json` 的 `counts` 字段仍是旧值（Base 223 / MathData 454 / Algo 194 / Device 329 / Motion 171 / Process 551，合计 **1,922 ≠ 2,041**），与 `components` 数组及磁盘均不一致，属 `counts` 字段未随 R92–R94 刷新。本席一律以 `components` 数组 + 磁盘为准。

## 三、四查留痕

### 3.1 词根饱和度实测（全库 2,041 件名称 CamelCase 分词命中数 / 正文边界词命中文件数）

| 族 | 族核心词根 | 名称命中 | 正文命中 | 判定 |
|---|---|---|---|---|
| A | Rtcp / RtcpPivot / FiveAxis | 0 / 0 / 0 | 0 / 0 / 0 | 真空 ✔ |
| A | ToolLength / ToolComp / ToolCenter | 0 / 0 / 0 | 0 / 0 / 0 | 真空 ✔ |
| A | ArcCenter / Helical / Swivel / Tilt | 0 / 0 / 0 / 0 | 0 / 0 / 0 / 0 | 真空 ✔ |
| A | CornerRounding / InvTime / SagFeed | 0 / 0 / 0 | 31 / 0 / 0 | 真空（`Rounding` 仅注释词）✔ |
| B | Bisect / RegulaFalsi / Secant / Illinois | 0 / 0 / 0 / 0 | 0 / 0 / 0 / 0 | 真空 ✔ |
| B | GoldenSection / Ternary / Parabola / Brent | 0 / 0 / 0 / 0 | 0 / 0 / 0 / 0 | 真空 ✔ |
| B | IterTerm / IterSolve / IterStep | 0 / 0 / 0 | 0 / 1 / 0 | 真空 ✔ |
| C | SevenSeg / Glyph / BlankMask | 0 / 0 / 0 | 0 / 0 / 0 | 真空 ✔ |
| C | Multiplex / Brightness / GhostGuard | 0 / 0 / 0 | 0 / 1 / 0 | 真空 ✔ |
| C | MinusFlag / FontSlot / BcdDecode | 0 / 0 / 0 | 0 / 0 / 0 | 真空 ✔ |
| D | PhSlope / PhAsymm / OrpRef | 0 / 0 / 0 | 0 / 0 / 0 | 真空 ✔ |
| D | Turbidity(Ntu) / ChlorineDpd / Dpd | 1 / 1 / 0 | 5 / 2 / 0 | 真空（≤2）✔ |
| D | DoSalinity / SodiumPna / Kcell | 0 / 0 / 0 | 0 / 0 / 0 | 真空 ✔ |
| D | AnalyzerRecal / TwopointCal | 0 / 0 | 0 / 0 | 真空 ✔ |

**命中 ≥3 被废弃的候选族（换域记录）**：
1. 「电子凸轮从动件高阶曲线族」→ 词根 `Follower` 名称命中 1、正文 4，`Cycloidal` 正文 1；已由在册 `FB_DL_CamTableOnlineBlend`/`FC_DL_CamTableInterp`/`FB_DL_CamPhaseTrim` 占据凸轮语义带，放弃。
2. 「SPC 控制图判异族」→ 核心词根被在册 `FB_DL_ShewhartRules`（判异规则）+ `FB_DL_CusumMonitor` + `FB_DL_EwmaFilter` + `FC_DL_CpkCalc`/`FC_DL_CpkIndex` 三重占据，族级冲突，**整族废弃**。
3. 「令牌桶/漏桶流量整形族」→ `TokenBucket`/`LeakyBucket` 虽 0 命中，但限流域已被 `FB_DL_RateLimiter`（Algo）+ `FC_DL_RateLimitReal`（MathData）+ `FB_DL_AlarmFloodLimiter`（Base）三件占位，语义邻接过密，放弃。
4. 「班次班制与交接边界族」→ 词根 `Shift` 名称命中 6（含在册 `FB_DL_ShiftMonthReport`、`FB_DL_ShiftHandoverCheck`）、`Rotation` 3，非真空域，**整族换域为族 C（七段数码管族）**。
5. 「多轴前瞻/绕线换向/同步带张力补偿」→ 与在册 `FB_DL_LookaheadVelPlanner`、`FB_DL_WindingTraverse`、`FC_DL_BeltLengthCalc` 撞语义带，未进入候选。

### 3.2 签名指纹查重（入参类型序列 + 出参类型序列）

- 全库 2,041 件解析 VAR_INPUT / VAR_OUTPUT / VAR_IN_OUT 得 **1,691 个不同签名**（最高频 `(LREAL)→(UDINT,BOOL,BOOL)` 24 件、`(REAL×4)→(REAL,REAL,BOOL,BOOL)` 与 `(REAL×4)→(REAL,BOOL)` 各 14 件）。
- 本轮 40 件逐件与 1,691 个在册签名比对：**0 撞签名**；40 件内部两两比对：**40/40 唯一**。
- 规划期打回并改签名的 3 件（原先与在册常见签名完全同型）：`FC_DL_OrpRefOffsetCalc`（原 `(R,R,R,R)→(R,R)` 撞 2 件 → 增 DINT 入参）、`FC_DL_ChlorineDpdAbsorbCalc`（原 `(R,R,R)→(R,R,B)` 撞 5 件 → 增 INT 入参）、`FC_DL_DoSalinityPermCalc`（原 `(R×6)→(R,B)` 撞 5 件 → 改 `(R×6)→(R,B,B)`）。另 `FC_DL_SwivelHeadTiltLimitCalc`（原 `(R×4)→(R,R,B)` 撞 5 件 → 增 DINT 入参）、`FC_DL_PhSlopeEffCalc`（原 `(R×4)→(R,B)` 撞 5 件 → 改 `(R×4)→(R,UDINT,B)`）、`FC_DL_SodiumPnaCalc`（原 `(R,R)→(R,R,B)` 撞 2 件 → 改 `(R,R,INT)→(R,B)`）同步改毕。

### 3.3 语义邻件（逐件「最近邻在册件 + 差异点」）

见 §5 附表，40 件逐行留痕，无空缺。

### 3.4 族级冲突复核（R93 教训：族级冲突必须整族换域）

- 族 A：`DL_Motion` 已有 `FB_DL_CircInterp2Axis`/`FB_DL_LineInterp2Axis`/`FB_DL_DeltaRobotIk`/`FB_DL_CamPhaseTrim`，均为**轨迹执行器**；本族为**几何反解与刀补参数算子 + RTCP 相序**，属参数层，非执行层 → 无族级冲突（逐件差异点已写明）。
- 族 B：`DL_Algo` 已有 `FB_DL_PidController`/`FB_DL_RateLimiter`/`FB_DL_AutoTuneRelay` 与 `DL_MathData` 的 `FC_DL_NewtonRaphson`/`FC_DL_QuadraticSolve`。本族**显式避让牛顿法**（不设 Newton 单步件），只做括号法/区间收缩/终止判据 → 单点邻接非族级冲突。
- 族 C：`DL_Base` 已有 `FC_DL_BcdToByte`/`FC_DL_BcdToUdint`/`FC_DL_BitMaskRange`/`FB_DL_BlinkOutput`。字形译码为**位型→段码映射**，与 BCD 数值转换、位掩码区间、闪烁输出三族语义正交 → 无族级冲突。
- 族 D：`DL_Device` 已有 `FB_DL_AnalogSensorHealthClassify`/`FC_DL_StrainGaugeTempComp`/`FB_DL_FlowMeterKFactorDrift`，`DL_Process` 有 `FB_DL_AnalyzerSampleSeq`/`FB_DL_WaterChlorineDoseTrim`/`FC_DL_CentrateTurbidityIdx`。本族为**测侧量值换算与标定相序**，与「健康分类/投加修正/采样流路」分工清楚 → 无族级冲突（`ChlorineDpd` 测侧 vs `WaterChlorineDoseTrim` 投加侧、`TurbidityNtu` 表标定 vs `CentrateTurbidityIdx` 工艺指数，已逐件写明）。

## 四、R95 目标规划表（S3 唯一输入）

| 序号 | 组件名 | 分类 | 前缀 | 功能 | 来源标签 | 复杂度 | 批次 | 档 |
|---|---|---|---|---|---|---|---|---|
| 1 | FC_DL_ArcCenterOffsetCalc | DL_Motion | FC_DL_ | 由起点/终点/半径反解圆心相对起点偏移 fDx/fDy(mm)，bCcw 选劣弧或优弧；半径小于半弦长走 uErrId 出口 | DLF-A-RTCP | C2 | 1 | 简单 |
| 2 | FC_DL_HelicalTurnAdvanceCalc | DL_Motion | FC_DL_ | 螺旋插补每转 Z 向进给与切向合成进给(mm/rev、mm/min)，含螺距≤0 防零 | DLF-A-RTCP | C2 | 1 | 简单 |
| 3 | FC_DL_RtcpPivotOffsetCalc | DL_Motion | FC_DL_ | RTCP 摆动轴枢轴偏置在工件坐标系的三向位移分量(mm)，双摆角绝对值>180° 折叠 | DLF-A-RTCP | C2 | 1 | 简单 |
| 4 | FC_DL_ToolLengthCompDeltaCalc | DL_Motion | FC_DL_ | 刀具长度补偿切换的增量(mm)与刀补号应用回执，含新旧长度差越限 | DLF-A-RTCP | C2 | 1 | 简单 |
| 5 | FC_DL_RotFeedInvTimeCalc | DL_Motion | FC_DL_ | 旋转轴进给率在 INV_TIME 与 deg/min 间双向换算并限幅，出 fFeedPerRev | DLF-A-RTCP | C2 | 1 | 简单 |
| 6 | FC_DL_SagFeedLimitCalc | DL_Motion | FC_DL_ | 按允许弦高(垂度)、向心加速度与采样周期 tCycle 反解进给上限(mm/min)，出 bLimited | DLF-A-RTCP | C2 | 1 | 简单 |
| 7 | FC_DL_SwivelHeadTiltLimitCalc | DL_Motion | FC_DL_ | 摆动头倾角指令钳位与角速度限幅(deg/s)，出 bAtLimit 与回退后指令 | DLF-A-RTCP | C2 | 1 | 简单 |
| 8 | FC_DL_CornerRoundingRadiusCalc | DL_Motion | FC_DL_ | 拐角圆弧过渡半径(mm)与拐角通过速度(mm/min)，受 jerk 上限约束 | DLF-A-RTCP | C2 | 1 | 简单 |
| 9 | FC_DL_RtcpTrackingErrCalc | DL_Motion | FC_DL_ | RTCP 下编程点与实绩点三维偏差矢量模长(mm)、分量与 uErrId | DLF-A-RTCP | C2 | 1 | 简单 |
| 10 | FB_DL_RtcpFiveAxisSeq | DL_Motion | FB_DL_ | 五轴 RTCP 补偿四相状态机：枢轴标定→使能→插补补偿→退出，含枢轴角软限位、超差转 eFault、锁存解除路径 | DLF-A-RTCP | C4 | 1 | 复杂 |
| 11 | FC_DL_BisectIterStep | DL_Algo | FC_DL_ | 二分法单步：端点与函数值→中点及新区间，fFa×fFb≥0 报 bBrktLost | DLF-B-ROOTSTEP | C2 | 2 | 简单 |
| 12 | FC_DL_RegulaFalsiIterStep | DL_Algo | FC_DL_ | 试位法单步：弦线插值取新点并由函数值符号换端，输出新括号 | DLF-B-ROOTSTEP | C2 | 2 | 简单 |
| 13 | FC_DL_SecantIterStep | DL_Algo | FC_DL_ | 割线法单步（无导数、四点输入），透传 uIter，abs(f1−f0) 防零 | DLF-B-ROOTSTEP | C2 | 2 | 简单 |
| 14 | FC_DL_IllinoisIterStep | DL_Algo | FC_DL_ | Illinois 改进试位单步：同侧停滞端点函数值折半，防单侧卡死 | DLF-B-ROOTSTEP | C2 | 2 | 简单 |
| 15 | FC_DL_GoldenSectionIterStep | DL_Algo | FC_DL_ | 黄金分割单步：一维极小点区间收缩(0.618)，出两点函数值与新区间 | DLF-B-ROOTSTEP | C2 | 2 | 简单 |
| 16 | FC_DL_TernaryNarrowIterStep | DL_Algo | FC_DL_ | 三分法单步：区间四等分两点比较后收缩，出收缩比与新区间 | DLF-B-ROOTSTEP | C2 | 2 | 简单 |
| 17 | FC_DL_ParabolaVertexIterStep | DL_Algo | FC_DL_ | 抛物线插值顶点步：三点拟合取顶点，三点共线走 bDegenerate 出口 | DLF-B-ROOTSTEP | C2 | 2 | 简单 |
| 18 | FC_DL_BrentBracketIterStep | DL_Algo | FC_DL_ | Brent 括号收缩单步：逆二次插值与二分混合，出新区间与收敛标记 | DLF-B-ROOTSTEP | C2 | 2 | 简单 |
| 19 | FC_DL_IterTermJudge | DL_Algo | FC_DL_ | 迭代终止判据：区间宽度/步长/最大迭代/超时四判据，出 bDone 与 uReason 编码 | DLF-B-ROOTSTEP | C2 | 2 | 简单 |
| 20 | FB_DL_IterSolverRunner | DL_Algo | FB_DL_ | 多方法求根运行器：方法选择(二分/试位/割线/Illinois/Brent)＋括号管理＋无解与发散出口＋迭代上限防死锁 | DLF-B-ROOTSTEP | C3 | 2 | 复杂 |
| 21 | FC_DL_SevenSegBcdDecode | DL_Base | FC_DL_ | BCD(0~9)→七段段码，bCommonAnode 极性切换，bDecimalPoint 叠加；输入>9 输出全灭 | DLF-C-SEVENSEG | C1 | 3 | 简单 |
| 22 | FC_DL_SevenSegHexCodeCalc | DL_Base | FC_DL_ | 0~F 十六进制字形段码（A~F 近似字形），bHexMode=FALSE 时按 BCD 严格校验 | DLF-C-SEVENSEG | C2 | 3 | 简单 |
| 23 | FC_DL_SevenSegMinusFlagCalc | DL_Base | FC_DL_ | 负号段与小数点段按位叠加，出叠加后段码与 bOverflow(段占用冲突) | DLF-C-SEVENSEG | C1 | 3 | 简单 |
| 24 | FC_DL_SevenSegBlankMaskCalc | DL_Base | FC_DL_ | 按有效位数 uDigits 生成前导零消隐掩码，uDigits=0 全灭 | DLF-C-SEVENSEG | C2 | 3 | 简单 |
| 25 | FC_DL_SevenSegBrightnessPwmCalc | DL_Base | FC_DL_ | 亮度 PWM 占空系数：uLevel/uFullScale、uMinDuty 下限保护，出 uDuty 与 bAtMin | DLF-C-SEVENSEG | C2 | 3 | 简单 |
| 26 | FC_DL_SevenSegBlinkPhaseCalc | DL_Base | FC_DL_ | 闪烁相位与频率(tOn/tPeriod,Hz)→bOn，tPeriod≤0 恒定点亮 | DLF-C-SEVENSEG | C2 | 3 | 简单 |
| 27 | FC_DL_SevenSegMultiplexPhaseCalc | DL_Base | FC_DL_ | 多路扫描相位：由 tScan 与 uDigitCnt 出当前位索引与单位保持时间 tSlot | DLF-C-SEVENSEG | C2 | 3 | 简单 |
| 28 | FC_DL_SevenSegGhostGuardCalc | DL_Base | FC_DL_ | 鬼影抑制消隐时间：按段关断延时与位切换时间取安全间隙，出 tBlank(µs) | DLF-C-SEVENSEG | C2 | 3 | 简单 |
| 29 | FC_DL_SevenSegGlyphFontCalc | DL_Base | FC_DL_ | 自定义字形字模查表：段掩码→字形槽号 uFontSlot，未命中出 bMiss | DLF-C-SEVENSEG | C2 | 3 | 简单 |
| 30 | FB_DL_SevenSegMultiplexSeq | DL_Base | FB_DL_ | 多路动态扫描驱动状态机：位选推进→消隐插入→亮度乘算→段码锁存，含扫描超时与位缺失诊断 | DLF-C-SEVENSEG | C3 | 3 | 复杂 |
| 31 | FC_DL_PhSlopeEffCalc | DL_Device | FC_DL_ | pH 电极斜率效率(%)：双点标定实测 mV/pH 对理论 59.16 mV/pH 之比，含温度修正与越限标记 | DLF-D-WATERANA | C2 | 4 | 简单 |
| 32 | FC_DL_PhAsymmPotentialCalc | DL_Device | FC_DL_ | pH 零点不对称电位(mV)：相对 7.00 pH 的实测偏移与零点漂移量 | DLF-D-WATERANA | C2 | 4 | 简单 |
| 33 | FC_DL_OrpRefOffsetCalc | DL_Device | FC_DL_ | ORP 参比电位偏移修正(mV)：Ag/AgCl 相对 SHE 换算与实测参比偏移 | DLF-D-WATERANA | C2 | 4 | 简单 |
| 34 | FC_DL_TurbidityNtuCalc | DL_Device | FC_DL_ | 浊度比值法：散射/透射比经标定系数转 NTU，含量程上限栅与负值保护 | DLF-D-WATERANA | C2 | 4 | 简单 |
| 35 | FC_DL_ChlorineDpdAbsorbCalc | DL_Device | FC_DL_ | DPD 比色吸光度→余氯(mg/L)：两点标定线性换算与量程钳制 | DLF-D-WATERANA | C2 | 4 | 简单 |
| 36 | FC_DL_DoSalinityPermCalc | DL_Device | FC_DL_ | 溶解氧膜渗透系数与盐度修正(mg/L、‰)，出修正后浓度与 bOutOfRange | DLF-D-WATERANA | C2 | 4 | 简单 |
| 37 | FC_DL_KcellConstCalc | DL_Device | FC_DL_ | 电导池常数 Kcell(1/cm)：标准液电导率反算与温补系数修正 | DLF-D-WATERANA | C2 | 4 | 简单 |
| 38 | FC_DL_SodiumPnaCalc | DL_Device | FC_DL_ | 钠离子 pNa 与温度斜率换算，出 pNa 与 µg/L 双量纲值 | DLF-D-WATERANA | C2 | 4 | 简单 |
| 39 | FC_DL_AnalyzerRecalDaysCalc | DL_Device | FC_DL_ | 分析仪漂移率(单位/天)→距重新标定天数(INT)，负值即已超标 | DLF-D-WATERANA | C2 | 4 | 简单 |
| 40 | FB_DL_AnalyzerTwopointCalSeq | DL_Device | FB_DL_ | 两点标定状态机：零液/标液切换→稳定判据→斜率计算→写回→失败回滚，含超时与 eFault 锁存解除 | DLF-D-WATERANA | C3 | 4 | 复杂 |

## 五、语义邻件留痕附表（每件「最近邻在册件 + 差异点」）

| 序号 | 最近邻在册件 | 差异点 |
|---|---|---|
| 1 | FB_DL_CircInterp2Axis | 本件只解圆心几何偏移，不含插补推进与轴输出 |
| 2 | FB_DL_LineInterp2Axis | 三维螺旋螺距→速度换算，不驱动轴 |
| 3 | FB_DL_DeltaRobotIk | 串联五轴枢轴偏置几何，非并联机构逆解 |
| 4 | FB_DL_ToolChangerSeq | 纯刀补增量几何计算，不含换刀时序 |
| 5 | FC_DL_RotaryIndexModulo | 进给率单位域换算，非角度回绕 |
| 6 | FC_DL_GeoChordHeightCalc | 把弦高容差反解为进给率上限，非几何量计算 |
| 7 | FB_DL_AxisRotaryShortPath | 倾角/角速双限幅，不选路径 |
| 8 | FB_DL_PathCornerBlend | 只出半径/速度参数，不做轨迹混合 |
| 9 | FB_DL_DualEncoderDeviationWatch | 工件坐标系三维跟随误差，非编码器差值 |
| 10 | FB_DL_CamPhaseTrim | RTCP 全相序补偿与枢轴标定，非单点相位偏置 |
| 11 | FC_DL_NewtonRaphson | 无内部循环的单步算子，且为括号法非导数法 |
| 12 | FC_DL_NewtonRaphson | 弦线插值不依赖导数，且不保证单侧收敛 |
| 13 | FC_DL_NewtonRaphson | 割线差分替代解析导数，无括号维护 |
| 14 | FC_DL_RegulaFalsiIterStep（本族 12） | 增加停滞端修正因子，收敛阶更高 |
| 15 | FC_DL_QuadraticSolve | 无导数区间收缩求极小，非解析求根 |
| 16 | FC_DL_GoldenSectionIterStep（本族 15） | 等分三点比较，收缩率 0.75 非 0.618 |
| 17 | FC_DL_QuadPolyFit | 只取顶点做单步跳跃，不输出拟合系数 |
| 18 | FC_DL_NewtonRaphson | 逆二次＋二分混合单步，含括号保护 |
| 19 | FC_DL_RangeCheckEx | 四判据仲裁出终止原因码，非区间成员判定 |
| 20 | FB_DL_AutoTuneRelay | 通用求根/极小运行器，非整定专用辨识 |
| 21 | FC_DL_BcdToByte | 转段码位型而非数值，含极性/小数点 |
| 22 | FC_DL_SevenSegBcdDecode（本族 21） | 扩展 A~F 字形与模式开关 |
| 23 | FC_DL_SevenSegBcdDecode（本族 21） | 修饰段叠加与冲突检测，不做字形译码 |
| 24 | FC_DL_BitMaskRange | 按十进制位数生成消隐掩码，非位区间掩码 |
| 25 | FC_DL_DitherSignalGen | 亮度级→占空比映射含下限保护，非调制波形 |
| 26 | FB_DL_BlinkOutput | 带相位与频率校验的段码闪烁判据，无定时器实例 |
| 27 | FB_DL_RotaryIndexTable | 时间域位选相位推进，非机械分度 |
| 28 | FC_DL_PulseWidthFilter | 生成消隐间隙时长，不过滤脉冲 |
| 29 | FC_DL_InterpStepNearest | 段掩码精确匹配取槽号，不做数值插值 |
| 30 | FB_DL_BlinkOutput | 多位扫描相序与消隐插空，单路闪烁不具备 |
| 31 | FC_DL_ConductivityTempComp | pH 电极斜率效率标定，非电导值温补 |
| 32 | FC_DL_StrainGaugeTempComp | 零点电位偏移量，非桥路温补 |
| 33 | FC_DL_ConductivityTempComp | 参比电位基准换算，非电导率量 |
| 34 | FC_DL_CentrateTurbidityIdx | 在线表比值法标定换算，非工艺浓缩浊度指标 |
| 35 | FB_DL_WaterChlorineDoseTrim | 测侧比色换算，非投加侧闭环 |
| 36 | FC_DL_MembraneFluxCalc | 溶氧膜渗透与盐度修正，非水通量 |
| 37 | FC_DL_ConductivityDilutionCalc | 反算池常数标定值，非浓度换算 |
| 38 | FC_DL_PhSlopeEffCalc（本族 31） | 钠离子电极 pNa 域，非 pH 域斜率 |
| 39 | FB_DL_SensorSupplyMon | 标定到期预测，非供电健康 |
| 40 | FB_DL_AnalyzerSampleSeq | 标定相序与斜率回写，非取样流路切换 |

## 六、签名指纹登记（S3 编码须严格落地，不得改型）

| 序号 | 组件名 | VAR_INPUT 类型序列 | VAR_OUTPUT 类型序列 |
|---|---|---|---|
| 1 | FC_DL_ArcCenterOffsetCalc | LREAL,LREAL,LREAL,LREAL,LREAL,BOOL | LREAL,LREAL,UDINT,BOOL |
| 2 | FC_DL_HelicalTurnAdvanceCalc | LREAL,LREAL,LREAL,REAL | REAL,REAL,UDINT |
| 3 | FC_DL_RtcpPivotOffsetCalc | LREAL,REAL,REAL | REAL,REAL,REAL,BOOL |
| 4 | FC_DL_ToolLengthCompDeltaCalc | REAL,REAL,DINT | REAL,DINT,BOOL |
| 5 | FC_DL_RotFeedInvTimeCalc | LREAL,LREAL,LREAL | LREAL,LREAL,UDINT,BOOL |
| 6 | FC_DL_SagFeedLimitCalc | LREAL,LREAL,LREAL,TIME | LREAL,BOOL |
| 7 | FC_DL_SwivelHeadTiltLimitCalc | REAL,REAL,REAL,REAL,DINT | REAL,REAL,BOOL |
| 8 | FC_DL_CornerRoundingRadiusCalc | LREAL,LREAL,LREAL,LREAL,LREAL | LREAL,LREAL,REAL |
| 9 | FC_DL_RtcpTrackingErrCalc | LREAL×6 | LREAL,UDINT |
| 10 | FB_DL_RtcpFiveAxisSeq | BOOL,BOOL,REAL,REAL,REAL,DINT | BOOL,BOOL,REAL,UDINT,INT |
| 11 | FC_DL_BisectIterStep | LREAL,LREAL,LREAL,LREAL,BOOL | LREAL,LREAL,BOOL |
| 12 | FC_DL_RegulaFalsiIterStep | LREAL×5 | LREAL,LREAL |
| 13 | FC_DL_SecantIterStep | LREAL,LREAL,LREAL,LREAL,UDINT | LREAL,LREAL,BOOL |
| 14 | FC_DL_IllinoisIterStep | LREAL×5,UDINT | LREAL,LREAL,UDINT,BOOL |
| 15 | FC_DL_GoldenSectionIterStep | LREAL,LREAL,LREAL | LREAL,LREAL,LREAL,BOOL |
| 16 | FC_DL_TernaryNarrowIterStep | LREAL×4 | LREAL,LREAL,LREAL |
| 17 | FC_DL_ParabolaVertexIterStep | LREAL×6 | LREAL,REAL,BOOL |
| 18 | FC_DL_BrentBracketIterStep | LREAL×7 | LREAL,LREAL,UDINT,BOOL |
| 19 | FC_DL_IterTermJudge | LREAL,LREAL,UDINT,UDINT,TIME | BOOL,UDINT |
| 20 | FB_DL_IterSolverRunner | BOOL,BOOL,LREAL,LREAL,LREAL,INT,INT,TIME | BOOL,BOOL,LREAL,LREAL,UDINT,INT |
| 21 | FC_DL_SevenSegBcdDecode | BYTE,BOOL | BYTE,BOOL |
| 22 | FC_DL_SevenSegHexCodeCalc | BYTE,BOOL,BOOL | BYTE,UDINT |
| 23 | FC_DL_SevenSegMinusFlagCalc | BYTE,BOOL,BOOL | BYTE |
| 24 | FC_DL_SevenSegBlankMaskCalc | BYTE,UINT | BYTE,UDINT |
| 25 | FC_DL_SevenSegBrightnessPwmCalc | USINT,USINT,USINT | USINT,BOOL |
| 26 | FC_DL_SevenSegBlinkPhaseCalc | TIME,TIME,TIME | BOOL,REAL |
| 27 | FC_DL_SevenSegMultiplexPhaseCalc | TIME,UINT,TIME | UINT,TIME |
| 28 | FC_DL_SevenSegGhostGuardCalc | TIME,TIME,BOOL | TIME,BOOL |
| 29 | FC_DL_SevenSegGlyphFontCalc | BYTE,UINT | BYTE,BOOL |
| 30 | FB_DL_SevenSegMultiplexSeq | BOOL,UINT,TIME,UINT,BOOL | BYTE,UINT,BOOL,UDINT |
| 31 | FC_DL_PhSlopeEffCalc | REAL,REAL,REAL,REAL | REAL,UDINT,BOOL |
| 32 | FC_DL_PhAsymmPotentialCalc | REAL,REAL,REAL | REAL,UDINT |
| 33 | FC_DL_OrpRefOffsetCalc | REAL,REAL,REAL,REAL,DINT | REAL,REAL |
| 34 | FC_DL_TurbidityNtuCalc | REAL×6 | REAL,UDINT |
| 35 | FC_DL_ChlorineDpdAbsorbCalc | REAL,REAL,REAL,INT | REAL,REAL,BOOL |
| 36 | FC_DL_DoSalinityPermCalc | REAL×6 | REAL,BOOL,BOOL |
| 37 | FC_DL_KcellConstCalc | REAL,REAL,REAL,REAL | REAL,REAL,UDINT |
| 38 | FC_DL_SodiumPnaCalc | REAL,REAL,INT | REAL,BOOL |
| 39 | FC_DL_AnalyzerRecalDaysCalc | REAL,REAL,REAL,TIME | INT,BOOL |
| 40 | FB_DL_AnalyzerTwopointCalSeq | BOOL,BOOL,REAL,REAL,UINT | BOOL,BOOL,REAL,UDINT,UINT |

## 七、计数与行数预估

- 复杂件 **4**：`FB_DL_RtcpFiveAxisSeq` C4（序号 10）、`FB_DL_IterSolverRunner` C3（20）、`FB_DL_SevenSegMultiplexSeq` C3（30）、`FB_DL_AnalyzerTwopointCalSeq` C3（40）——每族恰 1 件，全部落在批次末位。
- 简单件 **36**：C1×2（21、23）+ C2×34，全部为同族参数化变体（同族不同方法/不同位型/不同量纲/不同极性）。
- 行数预估：族 A 439 行、族 B 431 行、族 C 387 行、族 D 412 行 → 合计 **约 1,669 行**（简单 36 件 1,165 行、均 32.4 行/件，落在 20~50 行带；复杂 4 件 504 行、均 126 行/件）。
- 轮后总库：2,041 → **2,081**（Motion 205 / Algo 207 / Base 243 / Device 362；MathData 454、Process 610 不变）。

## 八、拒收 / 换域记录（规划期打回留痕）

| # | 名字（原拟） | 打回原因 | 与谁冲突 | 处置 |
|---|---|---|---|---|
| 1 | FC_DL_CamFollowerCycloidalCalc | 族根 `Follower` 名称命中 1、正文 4；凸轮语义带已被在册件占满 | FB_DL_CamTableOnlineBlend / FC_DL_CamTableInterp / FB_DL_CamPhaseTrim | 整族废弃，族 A 改为 RTCP 几何族 |
| 2 | FC_DL_XbarChartLimitCalc（SPC 族） | 控制图判异族在册已有实现 | FB_DL_ShewhartRules / FB_DL_CusumMonitor / FB_DL_EwmaFilter / FC_DL_CpkCalc | 整族废弃换域 |
| 3 | FC_DL_TokenBucketFillCalc（令牌桶族） | 限流域三件在册，语义邻接过密 | FB_DL_RateLimiter / FC_DL_RateLimitReal / FB_DL_AlarmFloodLimiter | 整族废弃换域 |
| 4 | FC_DL_ShiftBoundaryRemainCalc（班次族，10 件套） | 族根 `Shift` 名称命中 6、`Rotation` 3，非真空域 | FB_DL_ShiftMonthReport / FB_DL_ShiftHandoverCheck | **整族换域**为族 C 七段数码管族（未偷改单件） |
| 5 | FC_DL_RotaryAxisFeedScaleCalc | 词根 `Rotary` 名称命中 7（≥3） | FB_DL_RotaryIndexTable / FB_DL_AxisRotaryShortPath / FB_DL_RotaryIndexModulo | 换词 → FC_DL_RotFeedInvTimeCalc |
| 6 | FC_DL_RtcpDeviationCalc | 词根 `Deviation` 名称命中 5（≥3） | FB_DL_DualEncoderDeviationWatch / FB_DL_BatchDeviationAlarm | 换词 → FC_DL_RtcpTrackingErrCalc |
| 7 | FC_DL_CornerBlendRadiusCalc | 词根 `Blend` 名称命中 5（≥3） | FB_DL_PathCornerBlend / FB_DL_CamTableOnlineBlend | 换词 → FC_DL_CornerRoundingRadiusCalc |
| 8 | FC_DL_ChordTolFeedLimitCalc | `ChordHeight` 与在册件同根，`Tol` 名称命中 3 | FC_DL_GeoChordHeightCalc | 换词 → FC_DL_SagFeedLimitCalc（垂度语义） |
| 9 | FC_DL_CellConstCalc | 词根 `Cell` 名称命中 13（≥3） | FB_DL_CellVolumeCheck / FB_DL_CellOcvBinSort 等 | 换词 → FC_DL_KcellConstCalc |
| 10 | FC_DL_TurbidityRatioCalc | 与在册件编辑距离 3 | FC_DL_HumidityRatioCalc | 换词 → FC_DL_TurbidityNtuCalc |
| 11 | FC_DL_SevenSegFromBcdCalc / FC_DL_SevenSegFromHexCalc | 两件互相编辑距离 3（族内近名） | 彼此 | 改名为 FC_DL_SevenSegBcdDecode / FC_DL_SevenSegHexCodeCalc |
| 12 | FC_DL_IterRootSolveRunner | 词根 `Root` 名称命中 3（≥3） | FC_DL_NthRoot / FC_DL_FanLawRootCalc / FC_DL_GearRootCircleCalc | 换词 → FB_DL_IterSolverRunner |
| 13 | FC_DL_TernarySearchIterStep / FC_DL_IterStopJudge | 词根 `Search` 7、`Stop` 7（≥3） | 在册同名根件 | 换词 → FC_DL_TernaryNarrowIterStep / FC_DL_IterTermJudge |
| 14 | FC_DL_HelicalPitchFeedCalc | 词根 `Pitch` 3、`Feed` 5（≥3） | 在册螺纹/进给件 | 换词 → FC_DL_HelicalTurnAdvanceCalc |

> 说明：改型后仍保留的通用工业词（Offset / Feed / Time / Axis / Tool / Length / Comp / Ref / Days / Cal）属行业通用词汇，不作族根判定——族根一律取「RTCP / ToolLength / ArcCenter / Helical / Swivel / Bisect / RegulaFalsi / SevenSeg / Glyph / Ph / Orp / Turbidity / Sodium」等区分性复合词根。

## 九、给 S3 的写盘提示

1. 严格按序号 1→40 连号写盘，批次 1/2/3/4 = 四族，同一族一次调用批量写，减少切族开销。
2. 签名（§6）不得变更；如需增删引脚，先回报本席改规划表，不得自行改型（会破签名唯一性）。
3. 复杂件 4 件（10 / 20 / 30 / 40）必须在批次末位实现，便于失败时整批回退。
4. 本族内变量命名建议统一族前缀（`fArc…`、`fIter…`、`uSeg…`、`fPh…`），便于 S4/S5 事后族内重复检查。
5. 来源标签 `DLF-A-RTCP` / `DLF-B-ROOTSTEP` / `DLF-C-SEVENSEG` / `DLF-D-WATERANA` 需写入各件头注释溯源段。
6. 溯源如实申报：当日候选队列 297 行（绿区 232 / 黄区 65），逐词实测四族 0 命中，**溯源 0/40**，按内部原创线登记，不得编造仓库名。
