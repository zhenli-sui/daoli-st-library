# R44 轮次规划（ROUND_PLAN_R44）｜2026-11-19｜零检索轮（WebSearch 预算 0~3/3，本轮目标 0）

> 前置状态：总库 765 件（v2.35.0）；R43 产出 20 件但终审线未启用。R44 首位任务 = **P0 非编码任务**（见第 2 节），编码 20 件在其后排程。
> 选题纪律：宁少勿滥，严禁凑数变体；品类纠偏 R270：MathData 限 0~2（本轮 1 件），Algo/Motion 优先补（本轮 3+5=8 件）。
> 码位口径：**头部 ∪ 全文**双扫描（R39 教训）；下表码位为建议值，**落盘前须逐件实测复验**（R22 游标勘误铁律）。
> 避让声明：实测游标 Algo 02_3_88 / Motion 04_0_A7 / Process 06_0_BC / Device 05xx 副带 052D（避开 0590~0599 判错位段）/ MathData 05_0_05；本轮码位全部续编于游标之后，不落入 R35 十件 B/C/D 三子带（06_0_8C~97、03_1/03_2 既有窗口）。

---

## 1. R44 编码 20 件派单（4 批 × 5）

| 序号 | 组件名 | 分类 | 前缀 | 一句话功能 | 来源标签 | 复杂度 | 批次 | 建议码位 | 反证句 |
|---|---|---|---|---|---|---|---|---|---|
| 1 | FC_DL_DewPointToPpmV | DL_MathData | FC | 露点温度→水分含量 ppmV 换算（复用 VaporPressureSat 属主，饱和压比值法，禁重复声明 Magnus 常数） | t2-1-lgf-converter 行为定义 | 低 | 1 | 05_0_06 | grep 'DewPointToPpmV' registry+ROADMAP 零匹配 |
| 2 | FB_DL_GainSchedPid | DL_Algo | FB | 增益调度 PID：按工况分区线性插值 Kc/Ti/Td 参数集，区间过渡加权平滑 | t2-5-modpid 参数域 | 中 | 1 | 02_3_89 | grep 'GainSchedPid' registry+ROADMAP 零匹配 |
| 3 | FB_DL_RelayAutoTune | DL_Algo | FB | 继电器反馈法 PID 自整定：极限环测临界增益/周期，输出 Z-N 公开判据初值（只出参数不闭环） | t2-5-modpid 参数域 + 公开 Z-N 判据 | 中 | 1 | 02_3_8A | grep 'RelayAutoTune' registry+ROADMAP 零匹配 |
| 4 | FB_DL_BumplessHandAuto | DL_Algo | FB | 手/自动无扰切换：双向跟踪 + 切换偏差限幅 + 跟踪失效报警（兑现 T2-5 行「手自动切换」剩余项） | t2-5-modpid（行内明记剩余项） | 中 | 1 | 02_3_8B | grep 'BumplessHandAuto' registry+ROADMAP 零匹配 |
| 5 | FB_DL_AxisBacklashComp | DL_Motion | FB | 轴反向间隙补偿：方向反转沿检测 + 间隙学习值注入 + 学习值越域冻结 | t1-6-plcopen | 中 | 1 | 04_0_A8 | grep 'AxisBacklashComp' registry+ROADMAP 零匹配 |
| 6 | FB_DL_AxisTorqueWatch | DL_Motion | FB | 轴转矩趋势监视：转矩带域 + 趋势斜率双判据，达限预警/堵转分级（与 TorqueLimitControl 分工：控 vs 监） | t2-4-s7-motion | 中 | 2 | 04_0_A9 | grep 'AxisTorqueWatch' registry+ROADMAP 零匹配 |
| 7 | FB_DL_AxisBrakeTest | DL_Motion | FB | 抱闸制动测试顺控：抱闸保持 + 轴零速判定 + 滑移量测量 + 定期测试到期计数 | t1-6-plcopen（与 AxisBrakeDistPredict 分工：预测制动距离 vs 周期测试） | 中 | 2 | 04_0_AA | grep 'AxisBrakeTest' registry+ROADMAP 零匹配 |
| 8 | FB_DL_AxisFrictionFf | DL_Motion | FB | 摩擦转矩前馈：静/动摩擦分段前馈 + 速度方向切换滞环 + 前馈系数钳位 | t2-4-s7-motion | 中 | 2 | 04_0_AB | grep 'AxisFrictionFf' registry+ROADMAP 零匹配 |
| 9 | FB_DL_CircInterp2Axis | DL_Motion | FB | 两轴圆弧插补：起终点+半径/圆心双模式、弓高误差弦长分段、象限跨越判据（与 LineInterp2Axis 同线直角补口） | t1-8-github motion 线 | 高 | 2 | 04_0_AC | grep 'CircInterp2Axis' registry+ROADMAP 零匹配 |
| 10 | FB_DL_LoadcellTareCtrl | DL_Device | FB | 称重传感器去皮/标定管理：去皮锁存 + 两点标定系数计算 + 标定超期计数 | t2-6-rockwell-aoi 设备级粒度 | 中 | 2 | 052E | grep 'LoadcellTareCtrl' registry+ROADMAP 零匹配 |
| 11 | FB_DL_ValvePartialStrokeTest | DL_Device | FB | 安全阀部分行程测试 PST：测试行程限幅 + 过程许可联锁 + 测试结果判级 | t2-8-ne107/ISA（NE107 健康出口引用唯一属主枚举） | 中 | 3 | 052F | grep 'ValvePartialStrokeTest' registry+ROADMAP 零匹配 |
| 12 | FB_DL_RotaryUnionWatch | DL_Device | FB | 旋转接头监视：转速/温升/泄漏三判据各带独立确认窗（T2-6 三分类诊断结构复用） | t2-6-rockwell-aoi 三分类诊断 | 中 | 3 | 0530 | grep 'RotaryUnionWatch' registry+ROADMAP 零匹配 |
| 13 | FB_DL_HeaterSsrBank | DL_Device | FB | SSR 调功器组：多路占空比分相输出 + 路间电流均衡 + 断偶降级策略 | t2-2-lbp 三段分层 | 中 | 3 | 0531 | grep 'HeaterSsrBank' registry+ROADMAP 零匹配 |
| 14 | FB_DL_ChillerStagingSeq | DL_Process | FB | 冷机加卸载顺控：按需量分级加/卸载 + 最短启停驻留 + 轮值均衡（与 ChillerTempStab/ChillerCondReset 分工：稳定判稳 vs 顺控编组） | t2-7-packml 最小子集 + t1-2-oscat 暖通语义 | 中 | 3 | 06_0_BD | grep 'ChillerStagingSeq' registry+ROADMAP 零匹配 |
| 15 | FB_DL_DesiccantRegenSeq | DL_Process | FB | 干燥剂吸附塔再生顺控：吸附/再生/吹冷/切换四相 + 塔间轮换 + 再生温度曲线监视 | t2-8-isa88 相语义 | 中 | 3 | 06_0_BE | grep 'DesiccantRegenSeq' registry+ROADMAP 零匹配 |
| 16 | FB_DL_VacuumBakeOutSeq | DL_Process | FB | 真空烘烤顺控：升温斜坡 → 保温保压 → 降温放气，压升率判漏终点判据 | 自研行业池（锂电/半导体共性） | 高 | 4 | 06_0_BF | grep 'VacuumBakeOutSeq' registry+ROADMAP 零匹配 |
| 17 | FB_DL_CellAgingRestSeq | DL_Process | FB | 电芯老化静置顺控：静置计时 + 电压/内阻抽测窗口 + 时限到期判级出柜 | 自研行业池（锂电） | 中 | 4 | 06_0_C0 | grep 'CellAgingRestSeq' registry+ROADMAP 零匹配 |
| 18 | FB_DL_LaserDescumStep | DL_Process | FB | 激光去渣（descum）工步：功率/扫速/圈数参数集 + 终点目视/反射率判据 + 工步超时 | 自研行业池（半导体） | 中 | 4 | 06_0_C1 | grep 'LaserDescumStep' registry+ROADMAP 零匹配 |
| 19 | FB_DL_AirLeakDecayTest | DL_Process | FB | 气密压降法泄漏测试：充压稳压测量三段 + 温度补偿 + 泄漏率换算判级（与 EscHeLeakCheck 分工：氦检 vs 空气压降） | 自研行业池（通用质量工装） | 中 | 4 | 06_0_C2 | grep 'AirLeakDecayTest' registry+ROADMAP 零匹配 |
| 20 | FB_DL_CoolingTowerReset | DL_Process | FB | 冷塔出水温度重置：逼近度目标 + 风机台数/频率两级执行 + 湿球下限保护（DewpointReset 同族、对象不同） | t1-2-oscat-building reset 族 | 中 | 4 | 06_0_C3 | grep 'CoolingTowerReset' registry+ROADMAP 零匹配 |

### 1.1 候选剔除记录（反证机制战果）

| 候选名 | 剔除原因 |
|---|---|
| FB_DL_NotchFilter | grep 实测 registry 已注册（DL_Algo）→ 同名撞车剔除 |
| FB_DL_LeadLagComp | grep 实测 registry 已注册 `FB_DL_LeadLagCompensator` → 同义邻件剔除 |

**剔除候选数：2**（28 候选池 → 20 终选）。终选 20 名均已对 registry + ROADMAP 双文件 grep 零匹配。

### 1.2 批次依赖说明

- **批 1**：纯函数/低耦合件，零跨库依赖（DewPointToPpmV 只引用既有属主、不复制常数）。
- **批 2**：Level 1 算法/运动执行件，可组合调用库内既有件（RateLimiter/LowPassFilter 等），不新增接口。
- **批 3**：设备级件，NE107 件必须引用 `E_DL_Ne107Status` 唯一属主；三分类确认窗范式沿用。
- **批 4**：工艺顺控高复杂度件，PackML 件只做最小子集 + 明确终止态（17 态全集属主仍为 PackMlStateMachine）。

---

## 2. 机检验收口径固化（先写死，跑时不改）

> 扫描口径：**头部 ∪ 全文**（R39 教训：仅扫头部漏报 11 码位）。每件 20 项判定全 PASS 才算过机检。

| # | 判定项 | 最小判定标准 |
|---|---|---|
| 1 | 命名红线 | POU 名 = 文件名；POU 前缀 FB_DL_/FC_DL_/I_DL_；变量前缀 b/n/u/f/s/t/a/st/e/fb/i 与声明逐行一致 |
| 2 | 零全局耦合 | 全文零命中 `GVL`、`VAR_EXTERNAL`、`%IX`/`%QX`/`%IW`/`%QW`/`%MW`（注释引用亦不允许出现绝对地址示范） |
| 3 | 可移植性 | 仅 Standard.library 类型；零厂商库 USING 声明；零专有类型（DTL 允许但须挂编译债声明） |
| 4 | 状态机 | ENUM + CASE 结构；每个 CASE 必须 ELSE 兜底且兜底落到故障/安全态 |
| 5 | 防御性 | 浮点判等一律 ABS(x-y)<eps 或 x<>x 判 NaN；除法先判除子；数组访问前边界检查；WHILE 带守卫计数器 |
| 6 | 注释红线 | 100% 中文注释；头部七要素齐全（组件名/子库/版本/兼容性/功能描述/开源溯源 Origin/修订历史）；声明区逐变量同行注释含工程单位 |
| 7 | 无魔法数 | 阈值/限幅/超时全部提为常量（带单位后缀）或输入引脚；全文无非零裸数值比较 |
| 8 | R228A | 每个内嵌 TON/TOF/TP/R_TRIG/CTU 实例在主周期路径**无条件刷新**（不得位于任何 IF/CASE 分支内；每实例首行刷新） |
| 9 | R228B | 故障/健康出口：库内不得自造 NE107 枚举，必须引用唯一属主；每个故障锁存位写明解除式并自证可满足（终审两式 1：禁 `NOT bEnable AND NOT _bFaultLatch` 恒假式） |
| 10 | 占位符禁词 | 全文零命中 `TODO`/`FIXME`/`XXX`/`待补`/`[TODO]`/`placeholder`（含头注释） |
| 11 | 溯源短语 | 头部 Origin 字段必含且二选一：「IEC 61131-3 标准语义的道莅防御性实现」/「道莅自研 clean-room（参考 XX 分类与参数域，零代码行复制）」；与 RAW_NOTES_R44 账目可对齐 |
| 12 | 码位独占 | 头部∪全文实测码位与本轮其余 19 件及全库 765 件零撞车；Device 件避开 0590~0599 |
| 13 | 整数进位点（终审两式 2） | ceil/round/钳制件对「正好整除」与「上限+1」两点各推一条验收向量；禁 TRUNC(x)+1 写法 |
| 14 | 故障码单轨（R34/R192） | 同件禁双前缀并存；新件码段与子库既有段不连续时头注释写明分段理由 |

- 逐类加权：纯函数件（序 1）最小判定 = #1~#3、#5~#7、#10~#14；FB 状态机件 = 全 14 项。
- 机检结果记账格式沿用 R41：`件名 | PASS/FAIL | 失败项号`；FAIL 件当场返修，不得带入终审。

---

## 3. R44 P0 非编码任务清单（排在 20 件编码之前执行）

### 3.1 终审 5 抽（必含 2 高复杂度 + 3 件跨子库覆盖）

| 抽检件 | 子库 | 抽检理由 |
|---|---|---|
| FB_DL_IvCurveScan | DL_Process | 高复杂度必抽（R43 终审线未启用风险件） |
| FB_DL_CalenderRollPress | DL_Process | 高复杂度必抽（R43） |
| FB_DL_AxisBrakeDistPredict | DL_Motion | 补 Motion 子库覆盖 |
| FB_DL_BoilerFlueCondenseGuard | DL_Device | 补 Device 子库覆盖（R43 新件，052C 码位实证在册） |
| FC_DL_TimeToCycleCeil | DL_MathData | 补 MathData 覆盖 + 终审两式 2（整数进位点）专项验证件 |

- 终审执行「终审两式」逐件：①锁存解除式可达自证；②整数进位点两向量（TimeToCycleCeil 为正考件，正好整除/上限+1 必推）。
- 挂账 ≥3 即按 R193/R194 扩为受影响族全量返修，本轮编码件数下调 20%（20→16）并记账。

### 3.2 CassetteMapVerify 轻度返修（R43 终审挂账项）

- 范围限定：仅按 R43 终审记录的挂账条目逐条返修，**不动引脚契约、不做功能性重写**。
- 返修要点（按挂账性质对号入座）：①锁存解除式可达自证（终审两式 1）；②信息码复位沿清除范式（借用 R44 范式：`FB_DL_DeviceParamVerify` v1.0.1 修法——信息码只在复位沿清除）；③TON 无条件刷新补查（R228A）；④占位符/注释补齐。
- 版本处理：PATCH 递增 v1.0.1，头注释修订历史 +1 行；机检复跑 + 该件单独回写 registry。

### 3.3 其他 P0 项

- 预算可行动归因（R196）：R43 编码超时主因按「返修轮次 × 串行角色」归因落账，砍件/拆调用动作同步写入。
- ROADMAP 补写判定：待办实测 <30 条时才补写（≤10 条），本轮预期**不补写**（R43 后行业池待办充足，以实测为准）。

---

## 4. 本轮源配额与回写预告

- **零检索轮目标 WebSearch 0/3**：20 件全部复用源矩阵既有 ◐ 行（t1-6/t1-8/t2-2/t2-4/t2-5/t2-6/t2-7/t2-8/t1-2/t2-1-converter）+ 自研行业池，无 ☐→◐ 开组、无 ◐→✔ 收口。
- 配额满足：「≥1 个 T2 非 ST 源」（t2-x 多行）+「≥1 个 T1 ST 原生源」（t1-2/t1-6/t1-8）。
- 收尾回写义务：SOURCE_HUNTING_MATRIX §4 追加 R44 实测行；各子库 VERSION.md / MANUAL / 顶层 CHANGELOG / README / LIBRARY_MANUAL 五件套同步；AGENT_EVOLUTION_LOG 复盘；三向一致（INDEX_REGISTRY ∪ 文件树 ∪ ROADMAP 勾选）逐条对账。
