# MANUAL_DL_Algo — DL_Algo 子库使用说明书

> **子库定位**：Level 1 工业控制算法层（闭环控制律 / 轨迹规划 / 信号运算 / 过程补偿），仅依赖 Standard.library，不引用更高层子库。
> **兼容平台**：CODESYS V3.5+ ｜ TwinCAT 3 ｜ 汇川 InoProShop ｜ Schneider Machine Expert
> **当前版本**：v1.11.0（2026-11-17，R23）｜ 组件总数：43（注册表口径）
> **说明**：本手册按 R19-4 纪律于 R23 建骨架；本轮新增件接口表当轮收录，历史 38 件接口表按 R88 节奏（每轮 ≤10 件）分批补录。

---

## 使用通则

1. 全部组件零全局耦合：外部数据一律经引脚或接口注入，禁 %I/%Q/%M 物理地址。
2. 故障语义三分类：故障级置 bError 且输出确定值；信息级只置 eErr 不置 bError；bValid = FALSE 时输出不可用。
3. 浮点禁 `=` 判等；除法必有分母闸；迭代必有防死锁计数器。
4. 焓湿图族（R23 起）：饱和压唯一属主 `FC_DL_VaporPressureSat`（Magnus-Tetens 常数 a=17.625 / b=243.04 / E0=610.94 Pa），族内其余件禁止内联饱和压公式；`FC_DL_WetBulbTempCalc` 现处挂账警示期（R24 修复迭代格式前禁用于生产）。
5. 未经编译器验证声明见 `LIBRARY_MANUAL.md` 第十五节。


---

## R23 批次接口表（R23 追加 · 5 件 · T1-2 焓湿图原子族 ｜ 子库 v1.10.0→v1.11.0）

### FC_DL_VaporPressureSat ｜ 饱和水蒸气压计算（DL_Algo ｜ FUNCTION → BOOL）
| 引脚 | 方向 | 类型 | 说明 |
|---|---|---|---|
| `fTempC` | IN | `LREAL` | 空气温度 [摄氏度]，有效域 -40.0..100.0，域外钳位照算 |
| `fPvSat` | OUT | `LREAL` | 饱和水蒸气压 [Pa] |
| `bClamped` | OUT | `BOOL` | TRUE = 输入已钳位，结果按趋势参考 |
| `eErr` | OUT | `UDINT` | 错误码，0 = 无错 |
| `bError` | OUT | `BOOL` | 故障级标志，仅故障级错误置位 |
| `bValid` | OUT | `BOOL` | 输出可用标志 |

### FC_DL_HumidityRatioCalc ｜ 含湿量计算（DL_Algo ｜ FUNCTION → BOOL）
| 引脚 | 方向 | 类型 | 说明 |
|---|---|---|---|
| `fTempC` | IN | `LREAL` | 干球温度 [摄氏度] |
| `eRhMode` | IN | `E_DL_RhInputMode` | 第二输入模式枚举 [—] |
| `fRhIn` | IN | `LREAL` | 相对湿度 [百分数] 或露点 [摄氏度]，按 eRhMode 解释 |
| `fPress` | IN | `LREAL := 101325.0` | 大气压 [Pa]，引脚注入非魔法数 |
| `fHumRatio` | OUT | `LREAL` | 含湿量 [kg 水蒸气 |
| `fPv` | OUT | `LREAL` | 实际水蒸气分压 [Pa] |
| `bClamped` | OUT | `BOOL` | TRUE = 湿度 |
| `eErr` | OUT | `UDINT` | 错误码，0 = 无错 |
| `bError` | OUT | `BOOL` | 故障级标志，仅故障级错误置位 |
| `bValid` | OUT | `BOOL` | 输出可用标志 |

### FC_DL_WetBulbTempCalc ｜ 湿球温度估算（DL_Algo ｜ FUNCTION → BOOL）
| 引脚 | 方向 | 类型 | 说明 |
|---|---|---|---|
| `fTempC` | IN | `LREAL` | 干球温度 [摄氏度]，有效域 -20.0..60.0，域外钳位照算 |
| `fRh` | IN | `LREAL` | 相对湿度 [百分数]，有效域 1.0..100.0，域外钳位照算 |
| `fPress` | IN | `LREAL := 101325.0` | 大气压 [Pa]，引脚注入非魔法数 |
| `fWetBulbC` | OUT | `LREAL` | 湿球温度 [摄氏度] |
| `bClamped` | OUT | `BOOL` | TRUE = 温度或湿度输入已钳位 |
| `eErr` | OUT | `UDINT` | 错误码，0 = 无错 |
| `bError` | OUT | `BOOL` | 故障级标志，仅故障级错误置位 |
| `bValid` | OUT | `BOOL` | 输出可用标志 |

### FC_DL_RhFromDewPoint ｜ 露点反算相对湿度（DL_Algo ｜ FUNCTION → BOOL）
| 引脚 | 方向 | 类型 | 说明 |
|---|---|---|---|
| `fTempC` | IN | `LREAL` | 干球温度 [摄氏度]，有效域 -40.0..100.0，域外钳位照算 |
| `fDewPointC` | IN | `LREAL` | 露点温度 [摄氏度] |
| `fRh` | OUT | `LREAL` | 相对湿度 [百分数]，输出域 0..100 |
| `eErr` | OUT | `UDINT` | 错误码，0 = 无错 |
| `bError` | OUT | `BOOL` | 故障级标志，仅故障级错误置位 |
| `bValid` | OUT | `BOOL` | 输出可用标志 |

### FC_DL_MixAirStateCalc ｜ 回风/新风混合点状态计算（DL_Algo ｜ FUNCTION → BOOL）
| 引脚 | 方向 | 类型 | 说明 |
|---|---|---|---|
| `fRaTempC` | IN | `LREAL` | 回风干球温度 [摄氏度] |
| `fRaHumRatio` | IN | `LREAL` | 回风含湿量 [kg 水蒸气 |
| `fOaTempC` | IN | `LREAL` | 新风干球温度 [摄氏度] |
| `fOaHumRatio` | IN | `LREAL` | 新风含湿量 [kg 水蒸气 |
| `fOaFrac` | IN | `LREAL` | 新风比 [百分数]，有效域 0.0..100.0，域外钳位照算 |
| `fPress` | IN | `LREAL := 101325.0` | 大气压 [Pa]，引脚注入非魔法数 |
| `fMixTempC` | OUT | `LREAL` | 混合点干球温度 [摄氏度] |
| `fMixHumRatio` | OUT | `LREAL` | 混合点含湿量 [kg 水蒸气 |
| `fMixEnthalpy` | OUT | `LREAL` | 混合点比焓 [kJ |
| `bCondensation` | OUT | `BOOL` | TRUE = 混合点越过饱和线，结露预警（非故障） |
| `eErr` | OUT | `UDINT` | 错误码，0 = 无错 |
| `bError` | OUT | `BOOL` | 故障级标志，仅故障级错误置位 |
| `bValid` | OUT | `BOOL` | 输出可用标志 |

### 续补说明 / Remaining（R23 更新）

> 本节为 R23 新增件接口表（引脚取自 .st 声明区实测抽取，脚本 pins_r23.json 留档）；R23 终审修复件以修订历史为准（v1.0.1 引脚契约零变更）；历史件补录按 R88 节奏（每轮 ≤10 件）继续。

## R24 批次追加（2026-11-17 ｜ 行业纵深轮：本子库新增 1 件 + 修复件 1 件）

### FB_DL_GasDensityComp（功能块 FB，）｜ v1.0.0

- **功能**：理想气体定律温压补偿——由工作温度与绝对压力换算气体密度：
- **码位带**：16#0002_xxxx（信息级/故障级分带见源码头注释错误码表）
- **引脚契约**（完整语义与默认值以源码头注释/声明区为准）：

| 方向 | 引脚 | 类型 | 说明 |
|---|---|---|---|
| INPUT | `fPressKpa` | LREAL := 101.325 | 工作绝对压力 [千帕]，域 10..2000，域外钳位照算 |
| INPUT | `fTempC` | LREAL := 20.0 | 工作温度 [摄氏度]，域 -40..200，域外钳位照算 |
| INPUT | `fMolarMassG` | LREAL := 28.96 | 介质摩尔质量 [克每摩尔]，有效域 (0, 200]，空气 28.96 |
| INPUT | `fPressRefKpa` | LREAL := 101.325 | 参考态绝对压力 [千帕]，须 > 0 |
| INPUT | `fTempRefC` | LREAL := 20.0 | 参考态温度 [摄氏度]，须 > -273.15 |
| INPUT | `bEnable` | BOOL | 补偿使能 [—] |
| INPUT | `bReset` | BOOL | 故障复位 [—]，上升沿清组态锁存 |
| OUTPUT | `fRhoKgM3` | LREAL | 补偿密度 [千克每立方米] |
| OUTPUT | `fRhoRefKgM3` | LREAL | 参考态密度（诊断出口）[千克每立方米] |
| OUTPUT | `eState` | E_DL_GasCompState | 补偿相位 [—] |
| OUTPUT | `eErr` | UDINT | 错误码，0 = 无错，码位 16#0002_3201 起信息级、16#0002_3210 起故障级（分带见错误码表） |
| OUTPUT | `bError` | BOOL | 故障级标志，仅故障级错误置位 |
| OUTPUT | `bValid` | BOOL | 输出可用标志 |

### FC_DL_WetBulbTempCalc（函数 FC，）｜ v1.1.0　**注**：v1.0.1→v1.1.0（R23 P0 挂账关闭：二分法重写）

- **功能**：由干球温度 + 相对湿度 + 大气压求解湿球温度。v1.1.0 起
- **码位带**：16#0002_xxxx（信息级/故障级分带见源码头注释错误码表）
- **引脚契约**（完整语义与默认值以源码头注释/声明区为准）：

| 方向 | 引脚 | 类型 | 说明 |
|---|---|---|---|
| INPUT | `fTempC` | LREAL | 干球温度 [摄氏度]，有效域 -20.0..60.0，域外钳位照算 |
| INPUT | `fRh` | LREAL | 相对湿度 [百分数]，有效域 1.0..100.0，域外钳位照算 |
| INPUT | `fPress` | LREAL := 101325.0 | 大气压 [Pa]，有效域 50000..110000，域外故障拒绝 |
| OUTPUT | `fWetBulbC` | LREAL | 湿球温度 [摄氏度] |
| OUTPUT | `bClamped` | BOOL | TRUE = 温度或湿度输入已钳位 |
| OUTPUT | `eErr` | UDINT | 错误码，0 = 无错，码位 16#0002_2F01 起信息级、16#0002_2F10 起故障级（分带见错误码表） |
| OUTPUT | `bError` | BOOL | 故障级标志，仅故障级错误置位 |
| OUTPUT | `bValid` | BOOL | 输出可用标志 |


## R27 新增接口表（3 件 · 2026-11-17）

| 名称 | 类型 | 主要引脚 | 说明 |
|---|---|---|---|
| `FC_DL_GasFlowSqrt` | FC | IN `fDiffPress`/`fGasDensity`/`fCompFactor`/`fScaleMax`；OUT `fFlowSlm`/`eError` | 特气差压开方，委托 NthRoot + FlowCompensate，密度非法拒算、补偿比越界钳制 |
| `FC_DL_AirDensityFanPower` | FC | IN `fTemp_C`/`fRelHumPct`/`fPress_Pa`/`fPowerRated`；OUT `fPowerCorr`/`eError` | 风机功率密度修正，密度委托 AirDensity，比率钳 [0.5,1.5]，ρ0 为带单位常量 |
| `FB_DL_LoopWaveInject` | FB | IN `bEnable`/`eWaveType`/`fAmplitude`/`fPeriod_s`/`fSlewLimit`/`tSampleTime`；OUT `fInjectOut`/`bActive`/`eErr` | 回路调试正弦/方波/阶跃注入，相位累加器与限速器每拍无条件刷新，撤销平滑回零 |

## R30 新增接口表（Algo 2 件 · 2026-11-18）

| 名称 | 类型 | 主要引脚 | 说明 |
|---|---|---|---|
| `FB_DL_FanArraySeq` | FB | IN `uReqStages`〔0~6，越界钳位 + 码〕/`abFanAvail`/`abVfdEn`〔ARRAY[1..6]〕/`tMinRun`/`bRotateReq`；OUT `abFanRun`/`abFanVfdMode`/`uRunCount`/`eErr` | 需求 > 可用只投可用数 + 信息码；变频优先投切、工频补位（一台同拍至多一种模式）；最短运行时间内不轮值；台数 0 全停（安全侧）；码位 3729~372D |
| `FB_DL_ChwDifferentialPressure` | FB | IN `fDp_kPa`/`fDpSet_kPa`/`fPidOut_Pct`〔PID 输出引脚注入不内联〕/`fValveMin_Pct`/`fValveMax_Pct`/`fResetRate_kPa_s`;OUT `fValveOut_Pct`/`fDpSmooth_kPa`/`bByPassActive`/`eErr` | 压差平滑与设定值重置限速均消费低层件（MovingAverage / RateLimiter）；非有限压差 → 阀位保持 + 故障码；限幅饱和信息码；码位 372E~3732 |

## R62 追加（Algo +1 件 · 子库 v1.28→v1.29）

### FB_DL_BiquadFilter ｜ 通用二阶 IIR 节（FB ｜ v1.0.0）

**选型对照（滤波族五件分工）**

| 场合 | 用谁 | 理由 |
|---|---|---|
| 一阶惯性平滑（温度/压力信号去噪） | `FB_DL_LowPassFilter` | 单参数（时间常数），现场可调，二阶无收益 |
| 一阶高通（去直流漂移） | `FB_DL_HighPassFilter` | 同上，结构最简 |
| 单一工频/机械谐振抑制 | `FB_DL_NotchFilter` | 陷波结构固定、Q 已内含，无需下发系数 |
| FIR（线性相位、有限脉冲） | `FB_DL_FirFilter` | 需要严格线性相位时只有 FIR |
| **带通 / 带阻 / 可调 Q / 系数在线下发** | **`FB_DL_BiquadFilter`** | 唯一支持五系数在线下发与稳定域闸的通用节；代价是调用方须自行按公开二阶节设计公式算系数 |

**两条现场须知**
1. **系数由调用方负责**：本件只做「稳定域闸 + 变更沿清状态 + 输出钳位」，不做滤波器设计。`a0` 必须已归一为 1，`a1/a2` 须落稳定域，否则本件判组态故障并冻结输出。
2. **本版稳定性判据存在缺陷（R63 修复中）**：段 3 判据未覆盖 Jury 下边界 `a2 > |a1| − 1`，(a1 = −1.9, a2 = −0.95) 之类发散系数会被放行且 `bValid` 仍为 TRUE。**在 R63 返修发布前，请勿把本件用于安全相关回路**；非安全场合使用后须实测输出与理论频响一致性。详见 `_Staging_Raw/2026-11-21/REVIEW_R62.md` D2。
