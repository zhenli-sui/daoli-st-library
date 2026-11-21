# R24 轮次派单计划（ROUND PLAN R24）

> 生成：2026-11-17 05:19+ ｜ 生成人：工控代码库产品总监（阶段一盘点 + 阶段二源矩阵狩猎）
> 基线：INDEX_REGISTRY.json v2.12.0 / total=404（Base 73 / MathData 148 / Algo 43 / Device 67 / Motion 32 / Process 41）
> 本轮规模：**20 个新组件**（4 批 × 5 件，批次内按序编写）+ **2 个 P0 修复件**（随批次下发，不计入 20）
> 编码者须知：本规格为唯一事实源，不读记忆只读本文件；引脚契约、码位、溯源短语一律照抄本文件与各件派单段，禁止自造惯例（R50/R59 教训）。

---

## 0. 码位游标实测结论（2026-11-17 grep 全库 DL_*/*.st 实测，R61/R105 铁律）

| 段 | 信息级实测最大 | 下一信息游标 | 故障级实测最大 | 下一故障游标 | 备注 |
|---|---|---|---|---|---|
| 0001（Base/MathData） | 0001_0465（04xx 信息带）/ 0001_01FF（01xx 带满） | **0466** | 0001_03B6 | **03B7** | 02xx 带 02FF 满，03xx 为故障延伸带 |
| 0002（Algo，CC 制） | — | **下一 CC = 0x32**（实测 CC 已用至 0x31，32xx 全库零占用） | 同左，CC 内 5 槽 xx01~xx05 | — | 主控口头提示「0033 起」实测不成立：CC 0x32 空闲，按实测从 **0x32** 起分配（R105 偏差留痕，以实测胜） |
| 0003（Device） | 0003_0185 | **0186** | 0003_0359 | **035A** | 0185 为 TankN2 预留禁用码，0186 起均空闲 |
| 0004（Motion） | 0004_01E2 | **01E3** | 0004_02FE | **0300**（02FF 实测空闲但按十年带对齐从 0300 起启用 03xx 故障延伸带） | |
| 0005（Process） | 0005_01EF | **01F0** | 0005_032C | **032D** | |

> 主控交接提示值（0001_04 起、0002_0033 起、0003_0187/035B、0004_01E4/0300、0005_01F1/032E）与实测存在 +1~+2 同向偏差，全部按本表实测值下发（R105：交接链规划值恒比实测少 1~2，实测胜、留痕）。

---

## 1. 20 组件目标清单（总表）

| 序号 | 组件名 | 分类 | 前缀 | 一句话功能 | 来源标签 | 复杂度 | 批次 |
|---|---|---|---|---|---|---|---|
| 1 | FC_DL_Affine2DCompose | DL_MathData | FC | 二维仿射变换矩阵合成（平移/旋转/缩放/剪切按序合成 + 行列式可逆性校验） | T2-1 LGF Math 仿射变换族（矩阵 §5 R13 备注「仿射变换组合族待挖」开族） | 5 | 1 |
| 2 | FC_DL_Affine2DApply | DL_MathData | FC | 二维仿射矩阵对点坐标应用（与 Affine2DCompose 构成定义-应用逆对） | T2-1 LGF Math 仿射变换族 | 3 | 1 |
| 3 | FC_DL_FanLawRootCalc | DL_MathData | FC | 风机定律换算（转速比 → 流量/压力/功率，流量比开方域闸 + 防除零） | ROADMAP P1 §661（风机相似定律公开公式；前缀 FB→FC 改判留档：纯函数无状态，按 R14 聚居判据归 DL_MathData） | 4 | 1 |
| 4 | FB_DL_StepperMicroFeedPulseEquiv | DL_Device | FB | 步进细分脉冲当量换算与反向间隙组态校验（细分×丝距→当量表，组态域校验） | ROADMAP P2 §588（终审立项增强件，复用 FB_DL_PulseDirStepper 组态域校验） | 4 | 1 |
| 5 | FC_DL_TrackerBacktrackCalc | DL_Motion | FC | 跟踪支架逆跟踪角度修正计算（阵列阴影几何，纯函数） | ROADMAP P2 §360 | 5 | 1 |
| 6 | FB_DL_GasDensityComp | DL_Algo | FB | 反应釜气体密度温压补偿（复用 FC_DL_AirDensity 骨架换介质常量） | ROADMAP P2 §670 | 5 | 2 |
| 7 | FB_DL_PumpDryRunGuard | DL_Device | FB | 泵干转保护（功率/流量双判据 + 最短运行时间窗，防频繁启停） | ROADMAP P1 §452 | 7 | 2 |
| 8 | FB_DL_CoilFrostWindow | DL_Device | FB | 盘管结霜窗口判定与除霜请求（霜层窗 + 露点判据双条件） | ROADMAP P1 §727 | 6 | 2 |
| 9 | FB_DL_ElectrolyteMoistureGuard | DL_Device | FB | 注液间露点/湿度联锁（超露点禁止注液，首因锁定） | ROADMAP P1 §693 | 6 | 2 |
| 10 | FB_DL_MfcSetpointRamp | DL_Device | FB | MFC 设定值斜坡与超调抑制（斜率限制 + 量程换算） | ROADMAP P2 §710 | 5 | 2 |
| 11 | FB_DL_StringIVTrace | DL_Process | FB | 组串 IV 曲线扫描与特征点提取（Voc/Isc/Pmax/FF 四特征 + 扫描顺控） | ROADMAP P0 §228 | 8 | 3 |
| 12 | FB_DL_WindingAlignEdge | DL_Motion | FB | 卷绕极片边缘跟随与蛇形抑制（边缘锁存 + 滤波 + 纠偏行程拦截） | ROADMAP P1 §806 | 7 | 3 |
| 13 | FB_DL_SolderRibbonTension | DL_Motion | FB | 焊带放卷张力与蛇形纠偏（锥度张力 + 横动行程拦截） | ROADMAP P1 §703 | 7 | 3 |
| 14 | FB_DL_TrackerSnowShedAngle | DL_Motion | FB | 跟踪支架雪载卸荷角与复位（采暖季窗 + 太阳高度角 + 置角限速） | ROADMAP P1 §812 | 6 | 3 |
| 15 | FB_DL_ChamberPumpDownProfile | DL_Process | FB | 腔体抽气曲线包络监视（窗口统计 + 斜率判据，抽速异常早停） | ROADMAP P1 §708 | 7 | 3 |
| 16 | FB_DL_CartonErectorStation | DL_Process | FB | 开箱（Carton Erector）工站模板（七态九步骨架 + 步超时） | ROADMAP P0 §652 | 9 | 4 |
| 17 | FB_DL_TrackBarcodeTrace | DL_Process | FB | 托盘条码路由追溯（扫码枪契约 + 分道判据） | ROADMAP P0 §469 | 7 | 4 |
| 18 | FB_DL_TankDosingMulti | DL_Process | FB | 多罐轮流定量投加（多实例定量 + 罐序轮值） | ROADMAP P1 §510 | 8 | 4 |
| 19 | FB_DL_BatchDeviationAlarm | DL_Process | FB | 批次偏差分级报警与首出归因（四档分级 + 首出锁存） | ROADMAP P1 §734 | 6 | 4 |
| 20 | FB_DL_RollCompressForceBalance | DL_Process | FB | 辊压机两侧轧制力平衡监视与液压纠偏（压差窗 + 纠偏闭环 + 限速） | ROADMAP P1 §805 | 8 | 4 |

- 分类核验：20 名经 INDEX_REGISTRY + 全库 Glob 双查重 **0 撞名**（2026-11-17 实测）。
- T1/T2 配额：T2-1 LGF Math 仿射变换族 2 件（序号 1/2）——满足「至少 1 个组件族来自 T1/T2 源」。
- 严禁凑数变体：20 件各对应独立工程语义，与既有 404 件无职责重叠（FanLawRootCalc 与既有 FC_DL_NthRoot 的边界：本件是风机相似定律组合律，NthRoot 是开方原子，组合不重复原子）。

## 2. P0 修复件（2 件，随批次下发，不计入 20）

| 修复件 | 现状 | 修复要求 | 版本 | 批次归属 | 码位 |
|---|---|---|---|---|---|
| FC_DL_WetBulbTempCalc（DL_Algo） | v1.0.1 挂账禁用于生产；定点迭代 γ 量纲错位 1000 倍 + 结构性发散（R108） | **二分法重写**：湿球 ≤ 干球区间二分，精度 0.05 K，最大 40 次迭代（防死锁计数器强制），代入 Magnus-Tetens 饱和水汽压公式自洽验证；**保留原引脚契约**（fTempC/fRh/fPress → fWetBulbC/bClamped/eErr/bError/bValid）；头注释补收敛域声明（R108 判据）；附 ≥3 条验收向量推演（建议：30 ℃/65%RH/101325 Pa；5 ℃/80%RH；-10 ℃/20%RH；干湿球相等退化 RH→100） | v1.0.1 → **v1.1.0** | **批次 1**（纯函数数值件，与仿射对同批） | 原码位 2F01/2F02 信息、2F10/2F11 故障、2F12 预留**全保留**（语义重映射：2F02=迭代达上限未达 0.05 K 精度、2F11=输入致二分区间非法，头注释同步改写） |
| FB_DL_TankN2BlanketCtrl（DL_Device） | v1.0.0；泄放段无退出回差，罐压在高压分界附近抖动致泄放阀频繁动作（R23 终审挂账） | 补**泄放退出迟滞回差**：泄放进入阈值 = fPressHiKpa 不变，退出阈值 = fPressHiKpa − fVentHystKpa（**新增输入引脚** fVentHystKpa : LREAL := 0.2 [kPa]，默认非魔法数；非法 ≤0 或 ≥ 分界跨度 → 故障 0357 复用并回退默认）；补氮段迟滞同理审计（进入/退出阈值分离）；eVenting 退出沿以回差带下沿为准 | v1.0.0 → **v1.0.1** | **批次 2**（Device 批） | 新引脚行为挂既有信息码 0003_0184（滞环提示语义扩展，头注释改写）；**不新占码位**；头注释修订历史补 v1.0.1 行 |

## 3. 码位分配表（每件 5 槽含预留；实测游标起分配）

### 3.1 DL_MathData（0001 段）

| 组件 | 信息级 | 故障级 |
|---|---|---|
| FC_DL_Affine2DCompose | 0001_0466~0468（0466 可逆性校验失败信息级降级/0467~0468 预留） | 0001_03B7~03B8（03B7 输入非有限/矩阵元素非法置 bError、03B8 预留） |
| FC_DL_Affine2DApply | 0001_0469~046B | 0001_03B9~03BA（03B9 输入非有限、03BA 预留） |
| FC_DL_FanLawRootCalc | 0001_046C~046E（046C 转速比域外钳位照算信息级） | 0001_03BB~03BC（03BB 输入非法/负开方域、03BC 预留） |

### 3.2 DL_Algo（0002 段，CC 制）

| 组件 | CC | 码位 |
|---|---|---|
| FB_DL_GasDensityComp | 0x32 | 0002_3201~3202（信息级：域外钳位/参考态外推）+ 0002_3210~3211（故障级：输入非法/非有限）+ 0002_3205 预留禁用 |

### 3.3 DL_Device（0003 段）

| 组件 | 信息级 | 故障级 |
|---|---|---|
| FB_DL_StepperMicroFeedPulseEquiv | 0003_0186~0187 | 0003_035A~035C（035C 兜底） |
| FB_DL_PumpDryRunGuard | 0003_0188~0189 | 0003_035D~035F（035F 兜底） |
| FB_DL_CoilFrostWindow | 0003_018A~018B | 0003_0360~0362（0362 兜底） |
| FB_DL_ElectrolyteMoistureGuard | 0003_018C~018D | 0003_0363~0365（0365 兜底） |
| FB_DL_MfcSetpointRamp | 0003_018E~018F | 0003_0366~0368（0368 兜底） |

### 3.4 DL_Motion（0004 段）

| 组件 | 信息级 | 故障级 |
|---|---|---|
| FC_DL_TrackerBacktrackCalc | 0004_01E3~01E4 | 0004_0300~0302（0302 兜底） |
| FB_DL_WindingAlignEdge | 0004_01E5~01E6 | 0004_0303~0305（0305 兜底） |
| FB_DL_SolderRibbonTension | 0004_01E7~01E8 | 0004_0306~0308（0308 兜底） |
| FB_DL_TrackerSnowShedAngle | 0004_01E9~01EA | 0004_0309~030B（030B 兜底） |

### 3.5 DL_Process（0005 段）

| 组件 | 信息级 | 故障级 |
|---|---|---|
| FB_DL_StringIVTrace | 0005_01F0~01F1 | 0005_032D~032F（032F 兜底） |
| FB_DL_ChamberPumpDownProfile | 0005_01F2~01F3 | 0005_0330~0332（0332 兜底） |
| FB_DL_CartonErectorStation | 0005_01F4~01F5 | 0005_0333~0335（0335 兜底） |
| FB_DL_TrackBarcodeTrace | 0005_01F6~01F7 | 0005_0336~0338（0338 兜底） |
| FB_DL_TankDosingMulti | 0005_01F8~01F9 | 0005_0339~033B（033B 兜底） |
| FB_DL_BatchDeviationAlarm | 0005_01FA~01FB | 0005_033C~033E（033E 兜底） |
| FB_DL_RollCompressForceBalance | 0005_01FC~01FD | 0005_033F~0341（0341 兜底） |

> 收口后预计游标（供主控核对，以收口实测为准）：0001 信息 046F / 故障 03BD；0002 CC 0x33；0003 信息 0190 / 故障 0369；0004 信息 01EB / 故障 030C；0005 信息 01FE / 故障 0342。

## 4. 派单样板（R50/R59 教训：规格必须内嵌样板，不能只给语义。编码者逐件照抄替换 `<...>`）

### 4.1 头注释注释行样板（每个 .st 文件头部必须逐行齐备）

```iecst
//==============================================================================
// <功能块/函数>：<POU 名> ｜ 中文名称：<中文名>
// 所属子库：<DL_Base/DL_MathData/DL_Algo/DL_Device/DL_Motion/DL_Process> ｜ 版本：v1.0.0 ｜ 兼容：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop
// 功能描述：<3~8 行，含公式来源/判据来源与关键设计取舍>
// 开源溯源 (Origin)：<按 4.3 溯源短语原文二选一，逐字照抄>
// 单位表：<每个物理量一行：名[单位] 语义，禁止无单位裸数值>
// 错误码表：<逐行列出本件码位与级别，与 §3 分配表一致，禁止出现 %I/%Q/%M 记号>
// 状态机：<ENUM 名与成员 + 「CASE 含 ELSE 兜底」声明；纯函数件写「N/A——纯函数无顺序状态机，无 CASE 可写，非法状态不可能出现，以头注释说明替代 ELSE 兜底」（R60 固定文本）>
// 边界行为：<①~⑥ 逐条：域外早退/上限截断/跨段跨相时序/恢复复位首拍/失能清零/安全侧>
// 收敛域声明：<仅迭代/数值求解件必填：输入子域与收敛性论证（R108 判据）>（不适用则整行省略）
// 修订历史：v1.0.0 2026-11-17 首版（R24 派单 · <来源标签>）
//==============================================================================
```

- 注释纪律：全部中文；严禁嵌套 `(* *)`；严禁「同上」占位词；严禁 `...` 省略号区间记法；文件与头注释中严禁出现 `%I`/`%Q`/`%M` 记号原文（含错误码表行）。
- 变量声明注释样板（每行同行双语）：`    fPressKpa : LREAL;  // 罐压 [千帕] / Tank pressure [kPa]`——格式固定为 `// 中文 / English`，物理量必带单位。

### 4.2 错误码声明样板

```iecst
    eErr     : UDINT;                    // 错误码，0 = 无错，码位 16#<段位_码值>（信息级/故障级分带见错误码表） / Error code, 0 = no error, band info/fault per the code table
    bError   : BOOL;                     // 故障级标志，仅故障级错误置位 / Fault-class flag, set only on fault-level codes
```

- 错误码一律 `eErr : UDINT`；信息级不置 `bError`，故障级必置；每件首用码即兜底槽之外至少 1 信息 + 1 故障；预留禁用槽在错误码表标注「预留禁用（不得挪用）」。

### 4.3 溯源短语原文（二选一，逐字照抄，R93 收敛句式）

- **T2 借鉴件**（本轮序号 1、2 仿射族两件用此句）：
  `开源溯源 (Origin)：道莅 clean-room 防御性实现（仅借 LGF 分类事实/参数域/行为定义，零代码行与符号名复制）`
- **ROADMAP 行业池/自研件**（本轮其余 18 件 + 2 修复件用此句，按各自参考源如实替换括号内参考源名）：
  `开源溯源 (Origin)：道莅原创实现（参考 <公开工程惯例/公开规范条款名> 分类与参数域）`
- 修复件补充：FC_DL_WetBulbTempCalc 沿用既有 T1-2 OSCAT Building 行为定义句式并追加「v1.1.0 二分法重写（R108 挂账修复）」修订行；FB_DL_TankN2BlanketCtrl 追加 v1.0.1 修订行，Origin 句不变。

### 4.4 通用编码红线（逐件自检，7 项）

1. 零全局变量、零硬件寻址（`%I/%Q/%M` 记号连注释都不许出现）；外部数据一律 VAR_INPUT/OUTPUT/IN_OUT 或接口注入。
2. 纯 IEC 61131-3 + Standard.library，零厂商专有库。
3. 防除零（除子前容差判零）、数组越界检查、浮点禁 `=` 判等（`ABS(a-b) < 1E-6` 族）、WHILE 防死锁计数器。
4. ENUM + CASE 含 ELSE 兜底（ELSE 置故障码并落安全侧）；纯函数件按 R60 固定文本豁免。
5. TON/R_TRIG 等实例在待机分支与故障分支均**无条件周期刷新**；单拍标志自清；CASE 前置无条件状态改写禁用（会吞复位沿，R39）。
6. 许可类输出（bValid/bReady/放行位）在失能闸与故障闸 RETURN 路径上显式赋 FALSE（R72）。
7. POU 终结符成对（END_FUNCTION / END_FUNCTION_BLOCK）；POU 名 = 文件名；码位用满 §3 分配表，不得越段。

## 5. 批次依赖说明

- 批次 1（Level 0/纯函数 + 独立组态件）→ 批次 2（Level 1 设备/算法）→ 批次 3（运动 + 判据监视）→ 批次 4（Level 2 工艺工站）。批次内按序号编写；后批依赖前批产物与本库既有 404 件（依赖均为已注册件：PulseDirStepper/SignalStatistics/Differentiator/DewPointCalc/RateLimiter/MarkPositionLatch/CascadePid/PidController 等，引脚契约以各件 MANUAL 为准）。
- 2 修复件随批次 1（WetBulb）/批次 2（TankN2）首件下发，优先送审。

## 6. 交付与登记要求（收口方）

- 每件入库同步：INDEX_REGISTRY.json 增量 + JSONL 语料一条（含 architecture_thought 码位复核，R87 五步）+ 子库 VERSION/MANUAL + 顶层 CHANGELOG/README/LIBRARY_MANUAL（R74 增量四动作，禁整篇重写）。
- 收口游标回写：以源码反算实测游标回写 SOURCE_HUNTING_MATRIX.md §4/§5 与本文件 §0 修正注记。
- 矩阵回写：T2-1 LGF Math 行备注追加「R24 仿射变换组合族开族 2 件（Affine2DCompose/Affine2DApply）」。
