# AUDIT_R6 — Round 06 阶段五终审报告（DL_Device 10 + DL_Motion 3 + DL_Process 2 + DL_Algo 1，共 16 组件）

> 日期：2026-11-15 ｜ 终审人：道莅工控代码库产品总监（兜底模式 · 终审线）
> 终审对象：`C:\Library\DL_Device / DL_Motion / DL_Process / DL_Algo` 下 R6 全部 16 个 .st（全部逐行通读，未抽样）
> 依据：`ROUND_PLAN_R6.md`（含验收向量与故障码台账）+ `daoli-st-standard` + `AGENT_EVOLUTION_LOG.md` 现行规则库（R19~R23 / 公约 0.1~0.15）
> 独立机检已全过，本轮为人工读码终审（逻辑缺陷抓取线）。
> 结论：**终审通过**。16/16 PASS（其中 8 个 PASS(修后)），终审共修复缺陷 6 处（致命 2、严重 1、工程语义 2、逻辑级 1）+ 注释级勘误 2 处；修后机检 ALL 16 PASS，受影响 8 条 JSONL 已重建并 sha256 校验一致。

---

## 一、16 组件逐个结论

| # | 组件 | 子库 | 终审结论 | 修复数 | 版本 |
|---|---|---|---|---|---|
| 1 | FB_DL_SingleSolenoidCyl | DL_Device | **PASS** | 0 | 1.0.0 |
| 2 | I_DL_VacuumGenerator | DL_Device | **PASS** | 0 | 1.0.0 |
| 3 | FB_DL_VacuumEjector | DL_Device | **PASS(修后)** | 1 | **1.0.1** |
| 4 | FB_DL_StarDeltaMotor | DL_Device | **PASS(修后)** | 1 | **1.0.1** |
| 5 | I_DL_VfdDrive | DL_Device | **PASS** | 0 | 1.0.0 |
| 6 | FB_DL_VfdGeneric | DL_Device | **PASS(修后)** | 2 | **1.0.1** |
| 7 | I_DL_ProportionalValve | DL_Device | **PASS** | 0 | 1.0.0 |
| 8 | FB_DL_AnalogValve | DL_Device | **PASS(修后)** | 1 | **1.0.1** |
| 9 | I_DL_MotorizedValve | DL_Device | **PASS** | 0 | 1.0.0 |
| 10 | FB_DL_ThreePointValve | DL_Device | **PASS(修后)** | 0（注释级） | **1.0.1** |
| 11 | FB_DL_AxisHomingSeq | DL_Motion | **PASS(修后)** | 1 | **1.0.1** |
| 12 | FB_DL_AxisRelativeMove | DL_Motion | **PASS** | 0 | 1.0.0 |
| 13 | FB_DL_AxisVelocityMove | DL_Motion | **PASS** | 0 | 1.0.0 |
| 14 | FB_DL_EnthalpyCompareCtrl | DL_Process | **PASS(修后)** | 1 | **1.0.1** |
| 15 | FB_DL_OccScheduleWindow | DL_Process | **PASS** | 0 | 1.0.0 |
| 16 | FB_DL_RampSoakProfile | DL_Algo | **PASS(修后)** | 1 | **1.0.1** |

接口契约逐项对齐核验：4 个新接口（I_DL_VacuumGenerator / I_DL_VfdDrive / I_DL_ProportionalValve / I_DL_MotorizedValve）的属性组与实现块 PROPERTY GET 逐一兑现（R22），方法签名逐字一致、无声明未实现/实现未声明；`I_DL_Cylinder`（复用契约）4 方法 + 5 属性全部落地；`I_DL_MotionAxis` 依赖方式合法（iAxis VAR_IN_OUT 注入）。接口方法数全部 ≤6（I_DL_VfdDrive 恰为 6，临界合规）。

## 二、缺陷清单与修法（全部就地修复，改动文件版本号 → 1.0.1）

### 致命缺陷（R13 逐扫描推演复现，验收向量原本不成立）

| # | 文件 | 缺陷 | 修法 | 影响 |
|---|---|---|---|---|
| 1 | FB_DL_VacuumEjector | **吹气脉冲永不触发**：`_bBlowReq` 于 CASE 内置位（TP 实例已在段 1 最前部刷新完毕）、主体末尾**同拍**自清——TP 的 IN 在任何扫描周期内被采样时恒为 FALSE，`_fbTpBlow.Q` 恒 FALSE → `bBlowValve` 恒不输出，eBlowing 态下一拍即因 `NOT _fbTpBlow.Q` 退回 eIdle。逐拍推演：触发拍 TP 见 FALSE → 下一拍仍 FALSE → 立即回 Idle | 自清语句移至 TP 实例调用之后（TP 本拍采样 TRUE 起振，下一拍入参回落，定宽由 TP 自身保持） | 破真空功能整体失效；V3 验收向量不成立。与 R2 DualEdgeTrig「恒 FALSE」同级的时序型缺陷，文本机检完全不可见 |
| 2 | FB_DL_VfdGeneric | **同型缺陷**：`_bResetPulseReq` 同拍置位/自清 → `_fbTpResetPulse.Q` 恒 FALSE → `bFaultResetOut` 恒不输出 | 同上修法 | 故障复位端子脉冲永不输出，驱动故障只能靠反馈自恢复；V5 验收向量不成立 |

### 严重缺陷（状态机跃迁完整性）

| # | 文件 | 缺陷 | 修法 | 影响 |
|---|---|---|---|---|
| 3 | FB_DL_AxisHomingSeq | **三终态死锁**：eDone / eAborted / eFault 在 CASE 内均无任何迁出路径，`rtrigStart.Q` 启动沿被吞——首次回零完成后（或中止/故障后）本块永远无法再次回零，仅 bTrack 可逃逸；头注释却声称「仅重新启动可退出故障态」，实现与声明矛盾（E_DL_HomingStep.eDone「等待下次启动」注释同为空头承诺） | 新增段 5.5「终态重启借道」：三终态收到启动沿 → eStep := eIdle，同拍 CASE 的 eIdle 门禁分支受理该沿（不吞沿、不要求双击）；eIdle 分支已有 bDone/bAbortPend 清理逻辑，借道后语义自洽 | 状态机跃迁完整性违规（本轮重点审读清单项）；生产节拍内第二次回零必失效 |

### 工程语义级缺陷（NaN 穿透，R4 #15 同型）

| # | 文件 | 缺陷 | 修法 | 影响 |
|---|---|---|---|---|
| 4 | FB_DL_AnalogValve | **限幅域对调回读原始引脚**：对调分支 `_fOutMinEff := fOutMax; _fOutMaxEff := fOutMin` 直读**未经防御的原始引脚**——混合非数组态（如下端 NaN + 上端负值）把 NaN 带回生效域，经映射链输出 **NaN 阀位指令**且不带任何故障码 | 对调改为经中间变量 `_fSpanTmp` 交换**已防御的生效值** | NaN 以无故障身份进入阀位指令链 |
| 5 | FB_DL_EnthalpyCompareCtrl | **参数 REAL 输入非数防御缺口**（违反公约 0.8「全部 REAL 输入」）：fMinOaPos / fFreeCoolOaPos NaN 经 `LIMIT(...)` 直透生效域 → **fOaDamperCmd 输出 NaN**（新风阀位指令！）；fEnthalpyDeadband NaN 使迟滞判据恒 FALSE、状态机冻结；fEnthalpyHighLimit 依赖 NaN 比较恒 FALSE 的隐式落空 | 三参数补 `fX <> fX` 兜底（回落默认 30.0/100.0/2.0）后再钳位；对调改经 `fPosTmp` 交换已防御生效值；高限门限补显式自比检测 | 与 R4 FlowCompensate 大气压穿透完全同型——「看似常量的参数」无豁免 |

### 逻辑级缺陷（诊断码语义）

| # | 文件 | 缺陷 | 修法 | 影响 |
|---|---|---|---|---|
| 6 | FB_DL_StarDeltaMotor | **同库同语义双码**：重启抑制期启动拒绝分配新码 0003_0105，而 FB_DL_DolMotor（R5）同一事件已用信息级 0003_0208——HMI 报警分组将出现同事件双映射。规格原分配 0102 与 R5 台账冲突顺延至 0105 是机械执行公约 0.7，未上溯「沿用 DolMotor 口径」的规格本意 | 改用 0003_0208（语义归一），0105 空置不分配；同步修订 VfdGeneric/AnalogValve/ThreePointValve 三处头注释占位表述；机检白名单登记该归一裁定 | 电机族两块诊断口径统一 |

### 注释级勘误（随修后版本一并落档）

- FB_DL_VfdGeneric：规格设计要点「点动频率取 aPresetFreq[1]（注释声明）」未落地为注释 → bCmdJogFwd 引脚注释补声明（本块不切换频率通道，段速 1 兼作点动频率域，R11 偏离②留档）。
- FB_DL_ThreePointValve：头注释偏离①的 0105 占位表述对齐终审裁定；并登记已知诊断口径观察项（见第四节 4）。

## 三、偏离裁定（含两项专项裁定）

### 3.1 D4 裁定（收口遗留项）：EnthalpyCompareCtrl 负干球域钳位保守性 —— **裁定：维持现状，PASS**

- 事实链核验：本块 Oa 温度验收域 -30..60 摄氏度 → 负干球透传 `FC_DL_HumidAirEnthalpy`（计算域 0..100）→ 下游 `MIN(MAX(fTempC,0),100)` 钳位至 0 摄氏度并置 `0002_1701` → 新风焓**偏高估计**（实际 -10 摄氏度湿空气焓低于 0 摄氏度钳位值）→ 开侧判据 `fOaEnthalpy < fRaEnthalpy − 死区` 更难满足 → 经济器少开 → 不会引入高焓空气，**误差方向恒为保守安全侧**，仅损失潜在免费冷量（能效项，非安全项）。
- 钳位信息经 `_bClampInfo` 归并为 0005_0103 当拍呈现，调用方可知晓。
- 结论：D4 语义成立、方向保守、信息可视、头注释已声明取舍通道（是否放行负干球由调用方决定）。**维持引脚域 -30..60 与透传钳位方案**；若后续高精度冷量计量需求出现，再立项「冰面 Magnus 修正版焓值 FC」，不在本块内实现。已落档于本报告与本块 v1.0.1 头注释（无代码改动）。

### 3.2 故障码族段裁定：RampSoakProfile 0110~0113/0220 落在 PID/串级族段 —— **裁定：划独立族段 18xx 并已修正**

- 事实：`DL_Algo/VERSION.md` v1.0.0 变更说明明载族段划分「01xx PID / 02xx 串级 / … / 16xx 流量」（17xx 湿空气为 v1.1.0 增补）。RampSoakProfile 信息级 0110~0113 侵入 01xx PID 族段、故障级 0220 侵入 02xx 串级族段——数值未撞既有码位，但族段语义冲突（HMI 按族段分组会把它归入 PID/串级报警组）。
- 裁定：划**独立族段 18xx（Ramp/Soak 程序曲线族）**，信息级 1801（末段跳段）/ 1802（段数钳位）/ 1803（零斜坡阶跃）/ 1804（采样周期钳位），故障级 1810（段目标非有限值，锁存）。语义零变更，仅码位重排。
- 落地：`.st` 内 5 个码位常量全部重排（头注释故障码表/验收向量引用同步）+ 组件升 v1.0.1 + **`DL_Algo/VERSION.md` v1.0.0 节故障码族段口径行已按授权修正**（补记 17xx/18xx 两行，注明 18xx 为终审裁定归位族段）。
- 白名单复核：1810/1801~1804 与全库既有实占码零冲突（机检第 12 项通过）。

### 3.3 其余偏离留档逐条核验（全部 PASS）

| 偏离 | 组件 | 裁定 |
|---|---|---|
| 0003_0221 改用于缩回方向磁开校验超窗（规格伸出/缩回同窗重叠） | SingleSolenoidCyl | PASS——两码位各自可测，语义不冲突，R11 留档规范 |
| bCmdExtend 电平 OR 上升沿双通道受理 | SingleSolenoidCyl | PASS——单线圈电平物理语义涵盖边沿，无悬挂态 |
| 吹气脉冲改用 IEC 标准 TP（规格建议时间戳累积法与公约 0.9 冲突） | VacuumEjector | PASS——冲突裁定正确（时间戳法需时钟基准）；TP 用法经缺陷 #1 修复后语义等价 |
| 星角码位 0242/0246 语义重排（星粘连 vs 角未吸合各自可测） | StarDeltaMotor | PASS——分断失败与转换失败分离，互锁时序「先分断后吸合」物理成立（星线圈断 → tDeadTime 死区（此窗角线圈严禁输出，`_bInDeltaWin` 恒 FALSE 保证）→ 星反馈确认分断 → 角指令 → 角反馈窗） |
| ELSE 兜底沿用库级既有码 0201 | StarDeltaMotor | PASS——库级「非法状态」族码先例 |
| 信息级码链 0106→0107→0108/0109/0112→0110/0111 冲突顺延 | Vfd/AnalogValve/ThreePointValve | PASS（附 #6 归一修订）——与 DL_Device VERSION.md 台账逐码核对一致 |
| 0005_0201/0202 码位对调（0201 已被 PackML 占用） | EnthalpyCompareCtrl | PASS——与 DL_Process VERSION.md 核对一致，同义码复用留档 |
| 失效语义 D2（输出 fMinOaPos 兜底 + 诊断量冻结） | EnthalpyCompareCtrl | PASS——与规格双表述的自洽裁定，安全侧 |
| 0210/0211 信息级占用 02xx 段 | OccScheduleWindow | **PASS（维持）**——日历排程块全事件信息级、故障级段整体保留给后续工艺联锁件，规格 §7 有意裁定 + FB_DL_TimeWindowCheck（0001_0202）库内先例，头注释显式声明，不予改码 |
| bDirNeg 补充引脚（规格引脚表未列回零方向） | AxisHomingSeq | PASS——必要扩展，R11 留档规范 |
| 0004_0106 三块共用（参数门禁拒绝） | HomingSeq/RelativeMove/VelocityMove | PASS——同码同义共用留档规范 |
| 0212 同时承载中止与轴故障（含中止给故障级码的语义瑕疵） | AxisHomingSeq | 接受（规格明示分配，遵守规格；观察项见 4.5） |
| TON ET 折算积分替代逐拍 fDt 累加（公约 0.9 冲突裁定） | ThreePointValve | PASS——零时钟依赖且消除逐拍折算误差，量纲推导注释完备（R20） |
| 1% 吸附带固定值（bOpened/bClosed，规格未定值） | ThreePointValve | PASS——R11 留档，现场可整定行程时间 |

### 3.4 重点审读清单逐项核验结论

| 审读项 | 结论 |
|---|---|
| 首扫判据方向（R19） | 全部合规：ThreePointValve / EnthalpyCompareCtrl / RampSoakProfile 三处均为 `IF bTrack OR (NOT bInit)`、bInit 初值 FALSE、bTrack 优先；事件型免首扫标注（R23）逐块核对正确（SingleSolenoidCyl / StarDeltaMotor / VfdGeneric / AnalogValve / AxisRelativeMove / AxisVelocityMove / OccScheduleWindow 无 bInit，理由成立） |
| 状态机跃迁完整性 | 修复 1 处（#3 AxisHomingSeq 三终态死锁）；其余各块每态可达、无死状态、故障锁存仅复位/解除路径清除（R15）、信息级码未置 bError（R21 派生式逐块核对通过） |
| 双限位/双反馈冲突 + TON PT 变更（R14） | ThreePointValve 双限位互斥监视、StarDelta 星角双反馈监视、VfdGeneric 正反转冲突安全侧均到位；R14 口径裁定：本轮各 TON 的 PT 均为组态期定值且 IN 随状态门控（状态切换即断输入复位），AxisHomingSeq 另实现了显式 PT 变更断拍（bTmoBreak）——本库口径为「组态参数运行中变更按下一窗口生效，不强制断拍；相位切换类必须断拍」，合规 |
| 除零/越界 | 全部除法分母有下限防御（VfdGeneric fFreqMaxEff 钳 1E-6、RampSoak fRampSec 下限、ThreePointValve 行程时间非正值回退、AnalogValve/EnthalpyCompareCtrl 跨度退化回退）；数组索引全部先校验（RampSoak nSegEff 钳位 [1,16]、OccScheduleWindow 星期索引域检、VfdGeneric 段速表 1..7 门控） |
| 量纲一致性（R20） | TON ET 折算式（ThreePointValve/RampSoak）换算与量纲推导注释齐备；fFreqRefPercent [%]、fPosEstimate [%]、焓值 [kJ/kg 干空气]、预启带 TIME 域回绕推导均与算法一致，零混写 |
| 星三角切换时序 | 物理成立（见 3.3 表）；出口互斥断言对在位（防御性，推导上不可同真） |
| 三点浮点阀开度积分 | 行程时间折算、端点双保险（限位锚定 + 估算端点拒绝）、双向冲突拒绝、bTrack 重同步（V5）全部到位；uTravelCount 首扫计数偏差列为观察项（4.3） |
| OccScheduleWindow 边界 | 跨零点窗（实例侧）、预启动带回绕（T#24H 回绕式，lead≤start 与 lead>start 两分支边界连续）、节假日覆盖（折入 bEnableDay）、多窗最小号仲裁（升序首中）、日期越界降级（星期表全 FALSE 自然不在窗）——逐项推演通过，V1~V6 向量口径与实现一致 |
| 接口文件对齐 | 见第一节，无声明未实现/实现未声明 |

## 四、观察项（不改码，留档备查）

1. **TP 单拍触发范式（缺陷 #1/#2 的家族性根因）**：两个文件同模板出错，证明「TP/脉冲类实例的触发请求自清位置」必须成为固定范式——**自清一律置于实例调用之后、CASE 置位之前**。建议入册 R24（见第六节）。
2. AxisRelativeMove / AxisVelocityMove 的信息级码（0106/0107/钳位提示）为单扫描可见（段 4 瞬时清零 + 事件不重算），与 DL_Device 族「无故障透出本拍信息级」口径一致但与 AxisHomingSeq「持久驻留」口径不一致——跨族口径差异，HMI 采集需按族适配，留文档线统一说明。
3. ThreePointValve 的 uTravelCount 在上电首扫若全关限位已压住会即计 +1（限位态计数口径，±1 偏差，与 R4 PwmDutyController 同类）——已登记于该块 v1.0.1 修订历史。
4. StarDeltaMotor eStopping 态反馈触点粘连时无限时等待（头注释已声明「直至上层干预」）；AxisHomingSeq 的 0212 同时承载中止与轴故障（中止非故障但规格明示，遵守规格）。二者均为规格层语义，留 ROADMAP 评估。
5. 三平台真实编译验证连续五轮悬置（P0）——本轮 2 处致命缺陷再次证明文本机检对时序语义失明，CODESYS 最小工程 + 验收向量回放必须于 R7 启动。

## 五、修后机检与 JSONL 重建结果

### 机检（machine_check_r6.py 全量重跑，含白名单归一登记）

```text
16 文件 ALL PASS：禁记号 0 ｜ 占位符 0 ｜ 终结符成对 ｜ 末行 END_* ｜ 反序首扫 0 ｜
CASE-ELSE 全带 ｜ 接口方法 ≤6 ｜ 实例无条件刷新 ｜ 浮点判等 0 ｜ 声明双语 100% ｜
跨文件重名 0 ｜ 故障码冲突 0（白名单含 0003_0201/0208 等库级同义码，归一裁定已登记）
16 文件总行数：4461
```

### JSONL 重建（register_and_jsonl_r6.py 的 output 注入逻辑等效重放）

- 受影响 8 组件条目按 `meta/*.json` instruction 匹配逐条替换 output，条目行号 75/76/78/80/82/83/86/88；
- 回读校验：88 行全部 json.loads PASS；8 条 output 与对应 .st **sha256 逐字节一致**；未改动 80 条与备份（`daoli_st_sft_dataset.jsonl.backup_AUDIT_R6`）**逐字节一致**；
- sha256 台账：FB_DL_VacuumEjector 28d9be42…｜FB_DL_StarDeltaMotor 5daffeb4…｜FB_DL_VfdGeneric 1d5594d0…｜FB_DL_AnalogValve b6a1c711…｜FB_DL_ThreePointValve e2020fb9…｜FB_DL_AxisHomingSeq 09b7b720…｜FB_DL_EnthalpyCompareCtrl 7d08d058…｜FB_DL_RampSoakProfile cc339eab…。

### 改动文件清单（8 个 .st → 1.0.1 + 2 个授权文档/工具）

| 文件 | 变更性质 |
|---|---|
| DL_Device/FB_DL_VacuumEjector.st | 致命修复（TP 触发时序） |
| DL_Device/FB_DL_VfdGeneric.st | 致命修复（TP 触发时序）+ 点动频率注释 + 头注释归一对齐 |
| DL_Device/FB_DL_StarDeltaMotor.st | 逻辑级修复（0208 码位归一） |
| DL_Device/FB_DL_AnalogValve.st | 工程语义修复（对调 NaN 穿透）+ 头注释归一对齐 |
| DL_Device/FB_DL_ThreePointValve.st | 注释级（头注释对齐 + 观察项留档），逻辑零变更 |
| DL_Motion/FB_DL_AxisHomingSeq.st | 严重修复（三终态死锁） |
| DL_Process/FB_DL_EnthalpyCompareCtrl.st | 工程语义修复（参数 NaN 防御 + 对调穿透） |
| DL_Algo/FB_DL_RampSoakProfile.st | 故障码族段归位（0110~0113/0220 → 1801~1804/1810） |
| DL_Algo/VERSION.md | （授权范围内）族段口径行补记 17xx/18xx |
| _Staging_Raw/2026-11-15/machine_check_r6.py | 机检白名单登记 0208 归一裁定 |

registry / ROADMAP / 其他文档未触碰（按边界约定由文档线同步；文档线对齐要点：DL_Device 三块信息级码位、DL_Motion HomingSeq v1.0.1、DL_Process EnthalpyCompareCtrl v1.0.1、DL_Algo RampSoakProfile 18xx 族段与 v1.0.1）。

## 六、终审沉淀（供 AGENT_EVOLUTION_LOG 追加，文档线统一入册）

**R24（建议编号）· TP/定宽脉冲触发范式**：TP/自实现定宽脉冲的「单拍触发请求」标志，自清语句必须紧随实例调用之后、且置位点必须在实例调用之前（跨拍传递）——禁止「同拍置位 + 主体末尾自清」（实例永远采不到 TRUE）。验收向量必须含「触发拍 → 脉冲输出持续 PT → 自动回落」三段逐拍推演。来源：本轮 VacuumEjector/VfdGeneric 双文件同模板致命缺陷。

**终审总结论：16/16 PASS（8 个修后），R6 准入文档同步阶段。**

—— 终审签署：工控代码库产品总监（架构定稿与终审双职责）；编码与自检：PLC 编程专家（兜底会话）。修后机检 ALL PASS + JSONL 一致性断言 ALL PASS，双签齐备。
