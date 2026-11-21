# R45 轮次规划（ROUND_PLAN_R45）｜2026-11-19｜零检索轮（WebSearch 预算 0~3/3，本轮目标 0）

> 前置状态（已核实）：总库 **785 件 / v2.36.0**（Base 84 / MathData 198 / Algo 82 / Device 152 / Motion 77 / Process 192）；JSONL 语料 786 行；今日新增 115/200。
> 本轮定位：**规划 + 派单轮**（R44 战报已移交），编码与终审由后续轮次内完成。首位产能 = 2 件 P0 返修（`FB_DL_CalenderRollPress` 中危 / `FB_DL_IvCurveScan` 轻危），其后 20 件编码分 4 批。
> 选题纪律：宁少勿滥，严禁凑数变体。品类纠偏（R270/R280）本轮实测 → MathData **1**、Base **3**、Algo **5**、Motion **5**、Device **3**、Process **3**。
> 避让声明：R42~R44 已出 60 件（见 `BATTLE_REPORT_R42/43/44.md`）本轮零同题；`FB_DL_MotionBlendZone` 类 R22 已裁定「Blending 系列不立」的方向不翻案。

---

## 0 T0 快车道实测结论（本轮 T0 = 0 件的依据）

来源标签 `iec-std-wrapper` 的 T0 快车道 7 组 + T0-8 在源矩阵台账中**已全部标 ✔**，本轮逐名实测复核：

| T0 组 | 标准函数 | 库内在册件（registry 实测） | 余量 |
|---|---|---|---|
| T0-1 双稳态/边沿 | SR / RS / R_TRIG / F_TRIG | `FB_DL_SRBistable` / `RSBistable` / `SrEx` / `RsEx` / `RTrigEx` / `FTrigEx` / `DualEdgeTrig` / `EdgeDivider` | 0 |
| T0-2 定时器 | TON / TOF / TP / RTO | `FB_DL_TonEx` / `TofEx` / `TpEx` / `RtoEx` / `ExtendedTimer` / `PulseStretch` | 0 |
| T0-3 计数器 | CTU / CTD / CTUD | `FB_DL_CtuEx` / `CtdEx` / `CtudEx` / `PresetCounterSat` / `BidirectionalCounter` / `RolloverCounter` | 0 |
| T0-4 数学函数 | ABS…EXPT、MIN/MAX/LIMIT/MUX/SEL | `FC_DL_AbsEx` / `SqrtEx` / `LnEx` / `LogEx` / `ExpEx` / `ExptEx` / `SinEx` / `CosEx` / `TanEx` / `AsinEx` / `AcosEx` / `AtanEx` / `Atan2Ex` / `MinEx` / `MaxEx` / `LimitEx` / `SelEx` / `Mux2Ex` / `Mux4Ex` / `MinNanEx` / `MaxNanEx` | 0 |
| T0-5 类型转换 | TRUNC/ROUND/FLOOR/CEIL/BCD/`*_TO_*` | `FC_DL_TruncEx` / `RoundSat` / `FloorEx` / `CeilEx` / `BcdTo*` / `*ToBcd` / 15 件饱和转换族 | 0 |
| T0-6 字符串九函数 | LEN/LEFT/RIGHT/MID/CONCAT/INSERT/DELETE/REPLACE/FIND | `FC_DL_StringLenEx` / `StringLeftEx` / `StringRightEx` / `StringMidEx` / `StringConcatEx` / `StringInsertEx` / `StringDeleteEx` / `StringReplaceAtEx` / `StringReplaceAll` / `StringFindEx` + 大小写/修剪/分词 | 0 |
| T0-7 位串操作 | SHL/SHR/ROL/ROR | `FC_DL_ShlEx` / `ShrEx` / `RolEx` / `RorEx` / `ShlLwordEx` / `ShrLwordEx` / `RolLwordEx` / `RorLwordEx` | 0 |
| T0-8 同步/互斥 | SEMA | `FB_DL_SemaMutex` + `MutexOwnerAudit` | 0 |

**裁定**：本轮**不产任何 `iec-std-wrapper` 件**，20 件全部取自「ROADMAP 未注册真缺口 + 源矩阵既有 ◐ 行深化」。此为实测结论而非主观跳过（R85 禁虚账）。

---

## 1 R45 编码 20 件派单（4 批 × 5）

> 码位口径：**头部 ∪ 全文**双扫描（R39 教训）。本轮**不预发码位**——R22 已实证「交接游标同向 +1 偏差」，故派单只给约束（见 §2 #12），码位由编码侧落盘前当场实测自取，避免二次勘误。

| 序号 | 组件名 | 分类 | 前缀 | 一句话功能 | 来源标签 | 复杂度 | 批次 | 反证句 |
|---|---|---|---|---|---|---|---|---|
| 1 | `FB_DL_Vote2oo3` | DL_Base | FB | 三取二表决器：2oo3 多数表决 + 单通道失效自动降级 1oo2 + 全失配锁故障（表决结构惯例，零代码行） | 自研线（表决结构惯例） | 中 | 1 | grep 'Vote2oo3' registry+文件树零匹配 |
| 2 | `FB_DL_EdgeOrderCheck` | DL_Base | FB | 双信号先后顺序与最小间隔监视：防「先到位后指令」逆序（含逆向顺序计数与锁存） | 自研线（现场联锁惯例） | 低 | 1 | grep 'EdgeOrderCheck' 零匹配 |
| 3 | `FB_DL_AlarmFloodLimiter` | DL_Base | FB | 报警泛滥抑制：滑动窗同源计数 + 超限归并 + 抑制期首末计数台账（只做闸不替代 `AlarmManager`） | t2-8-isa182 报警生命周期 | 中 | 1 | grep 'AlarmFloodLimiter' 零匹配 |
| 4 | `FC_DL_CubicBezierEval` | DL_MathData | FC | 三次贝塞尔曲线求值与切线：De Casteljau 稳定求值，t∈[0,1] 越域钳制 | t2-1-lgf Math 子族 | 低 | 1 | grep 'CubicBezierEval' 零匹配 |
| 5 | `FB_DL_KalmanFilter1D` | DL_Algo | FB | 一维（标量）卡尔曼滤波：预测-更新两步 + 新息门限拒野值 + 协方差发散复位 | 自研线（公开 Kalman 递推式） | 高 | 1 | grep 'KalmanFilter1D' 零匹配 |
| 6 | `FB_DL_TensionObserver` | DL_Algo | FB | 张力观测器：由转矩/卷径/角加速度反算材料张力 + 摩擦与惯量项补偿（只观不算控） | t2-1-lgf Technology 子族 | 高 | 2 | grep 'TensionObserver' 零匹配 |
| 7 | `FB_DL_StictionCompensator` | DL_Algo | FB | 黏滞死区补偿：脉动叠加 + 死区宽度在线估计 + 补偿幅值钳位（与 `ValveStictionDetect` 分工：补 vs 诊） | t2-5-modpid 参数域 | 中 | 2 | grep 'StictionCompensator' 零匹配；同义邻件 `FB_DL_ValveStictionDetect` 已判「诊断 vs 补偿」分工 |
| 8 | `FB_DL_LoopPerfIndex` | DL_Algo | FB | 回路性能指标：IAE/ISE/超调/衰减比 + 振荡计数分级（只出指标与建议档，不做自整定） | t2-5-modpid 参数域 | 中 | 2 | grep 'LoopPerfIndex' 零匹配 |
| 9 | `FB_DL_ThermalRampPredict` | DL_Algo | FB | 一阶热模型预测前馈：升温斜率预测 + 到达目标提前量 + 时间常数在线修正 | t2-1-lgf Technology 子族 | 中 | 2 | grep 'ThermalRampPredict' 零匹配 |
| 10 | `FB_DL_AxisDualFeedbackGuard` | DL_Motion | FB | 轴双反馈交叉校核：电机编码器 vs 负载侧尺偏差分级（打滑/磨损/极性装反） | t1-6-plcopen | 中 | 2 | grep 'AxisDualFeedbackGuard' 零匹配 |
| 11 | `FB_DL_AxisSs1StopSeq` | DL_Motion | FB | SS1 类安全停止时序：受控减速→到位判定→延时 STO 请求（只做时序，不实现安全认证功能） | t1-6-plcopen + IEC 60204-1 公开语义 | 中 | 3 | grep 'AxisSs1StopSeq' 零匹配 |
| 12 | `FB_DL_AxisTeachOffset` | DL_Motion | FB | 位置示教与偏移量管理：示教锁存 + 配方偏移应用 + 越软限拦截 | t1-6-plcopen | 低 | 3 | grep 'AxisTeachOffset' 零匹配 |
| 13 | `FB_DL_AxisInertiaIdent` | DL_Motion | FB | 轴惯量辨识：加速段转矩-加速度回归 + 置信度门限 + 结果冻结与历史保持 | t2-4-s7-motion | 高 | 3 | grep 'AxisInertiaIdent' 零匹配 |
| 14 | `FB_DL_AxisRotaryShortPath` | DL_Motion | FB | 旋转轴最短路径定位：圈数台账 + 180° 边界约定 + 软限圈域钳制 | t1-6-plcopen | 中 | 3 | grep 'AxisRotaryShortPath' 零匹配 |
| 15 | `FB_DL_SafetyRelayFeedback` | DL_Device | FB | 安全继电器双通道反馈一致性监视：K1/K2 动作不同步与单通道常闭失效判定 | t2-8-isa182 安全回路语义 | 中 | 3 | grep 'SafetyRelayFeedback' 零匹配 |
| 16 | `FB_DL_ContactorWeldDetect` | DL_Device | FB | 接触器/主触点熔焊检测：断开指令后反馈仍为 1 的判定窗与分级 | t2-6-rockwell-aoi 设备级粒度 | 低 | 4 | grep 'ContactorWeldDetect' 零匹配 |
| 17 | `FB_DL_FlowSwitchResponseCheck` | DL_Device | FB | 流量开关响应确认：泵/阀启动后响应窗内无流量信号 → 判开关或管路故障（校验器件本身，非干转保护） | t2-2-lbp 命令-监视-判定三段 | 低 | 4 | grep 'FlowSwitchResponseCheck' 零匹配 |
| 18 | `FB_DL_SlurryMixingSeq` | DL_Process | FB | 浆料搅拌顺控：加料→高速分散→真空脱泡→出料四相 + 转速/真空/时间三重判定 + 温升保护 | 自研行业池（锂电前段） | 高 | 4 | grep 'SlurryMixingSeq' 零匹配；同义邻件 `FB_DL_SlurryStirrerCtrl`（Device）已判「单机控制 vs 批次顺控」分工 |
| 19 | `FB_DL_FrameSealDispenseSeq` | DL_Process | FB | 装框打胶顺控：轨迹分段打胶→胶量校核→压合→固化窗，胶路断点即判 NG | 自研行业池（光伏组件） | 中 | 4 | grep 'FrameSealDispenseSeq' 零匹配 |
| 20 | `FB_DL_BoilerBlowdownSeq` | DL_Process | FB | 锅炉排污顺控：定时/电导率双触发 + 排污时长 + 低水位联锁禁止排污 | t1-2-oscat-building 公用工程语义 | 中 | 4 | grep 'BoilerBlowdownSeq' 零匹配 |

### 1.1 候选剔除记录（反证机制战果 · 11 条）

| 候选名 | 剔除原因 |
|---|---|
| `FB_DL_CasePackerPatternVerify` | 同义邻件：registry 已注册 `FB_DL_CasePackerPattern`（同域装箱模式） |
| `FB_DL_PalletizerStation` | **registry 已注册**（Process），ROADMAP 仍空勾 → 三向一致差额样本 |
| `FB_DL_TrackBarcodeTrace` | 同上（已注册未勾） |
| `FB_DL_StringBarcodeTrace` | 同上（已注册未勾） |
| `FB_DL_WindingAlignEdge` | 同上（已注册未勾，Motion） |
| `FB_DL_FrequencyChirpGen` | 同义邻件：`FB_DL_FrequencyGenerator` 已覆盖扫频/变频语义 |
| `FC_DL_WelfordStdDev` | 同义邻件：`FB_DL_SignalStatistics` 已在册（在线统计） |
| `FB_DL_HeaterElementDiag` | 职责重叠：R44 新件 `FB_DL_HeaterSsrBank` 已含断偶/电流诊断 |
| `FB_DL_MotionBlendZone` | R22 已裁定「Blending 系列明确不立」，不得翻案 |
| `FC_DL_ShlDwordEx` | ROADMAP 自记「疑似与存量 `ShlEx` 同义」，按 R61 拒立项 |
| `FC_DL_ShrDwordEx` | 同上 |

**反证句（终稿）**：**20 名 grep registry + 文件树 + ROADMAP 三处零匹配，另拒 11 条同名/同义候选**；实测脚本 `_Staging_Raw/2026-11-19/check_r45.py`，结果落 `_check_r45_result.json`（`exact_collisions = 0`）。

### 1.2 批次依赖说明

- **批 1（5 件）**：Level 0 + 纯函数 + 单体高复杂度算法。`Vote2oo3` / `EdgeOrderCheck` / `AlarmFloodLimiter` 只依赖 Standard.library；`CubicBezierEval` 纯函数零状态；`KalmanFilter1D` 只调自身算术，不引库内其他件。
- **批 2（5 件）**：`TensionObserver` / `ThermalRampPredict` 可组合调用 `FB_DL_LowPassFilter`（库内低层复用不复制）；`StictionCompensator` 与 `LoopPerfIndex` 引脚化输入，不内联 PID；`AxisDualFeedbackGuard` 只消费位置快照，**不定义轴状态枚举**（轴状态唯一属主仍为 `I_DL_MotionAxis`）。
- **批 3（5 件）**：Motion 四件同族，`AxisSs1StopSeq` 不得与传统状态机并存（只做停止时序 + 输出 STO 请求位）；`SafetyRelayFeedback` 是 Device 侧安全回路一致性件，与 `GuardLockDoor`/`UnlockHoldTimeout` 无引脚交叉。
- **批 4（5 件）**：Device 两件 + Process 三件；Process 三件均以「命令-监视-判定」三段骨架承载，**不自造 PackML 17 态全集**（属主仍为 `FB_DL_PackMlStateMachine`），只做最小子集 + 明确终止态。

### 1.3 品类纠偏核对（R270/R280）

| 子库 | 本轮 | 约束 | 判定 |
|---|---|---|---|
| DL_MathData | 1（`CubicBezierEval`） | ≤1 | PASS；且为**低复杂度纯函数**，不触 R195「编解码/数学/转换类高复杂度件」禁入闸 |
| DL_Algo | 5 | 优先补池（存量最小 82） | PASS |
| DL_Motion | 5 | 优先补池 | PASS |
| DL_Base | 3 | 2~4 | PASS |
| DL_Device | 3 | 适量 | PASS |
| DL_Process | 3 | 适量（存量 192 已最大） | PASS |

---

## 2 机检验收口径（先写死，跑时不改）

> 扫描口径：**头部 ∪ 全文**。沿用 R44 的 14 项，本轮按终审教训**增补 3 项**（#15~#17），共 17 项；每件全 PASS 才算过机检。

| # | 判定项 | 最小判定标准 |
|---|---|---|
| 1 | 命名红线 | POU 名 = 文件名；前缀 FB_DL_/FC_DL_/I_DL_；变量前缀 b/n/u/f/s/t/a/st/e/fb/i 与声明逐行一致 |
| 2 | 零全局耦合 | 全文零命中 `GVL`、`VAR_EXTERNAL` |
| 3 | 零硬编码地址 | 全文零命中 `%IX`/`%QX`/`%IW`/`%QW`/`%MW`（注释示范亦不允许） |
| 4 | 可移植性 | 仅 Standard.library 类型；零厂商库；零 `POINTER TO`/`REFERENCE TO`；零隐式转换 |
| 5 | 状态机 | ENUM + CASE 结构；每个 CASE 必须 ELSE 兜底且落故障/安全态 |
| 6 | 防御性 | 浮点判等一律 `ABS(x-y)<eps`；NaN 自反判 `x<>x` 须在头注释声明为**唯一例外**；除法先判除子；数组先判边界；WHILE 带守卫计数 |
| 7 | 注释红线 | 100% 中文；头部七要素齐全；声明区逐变量同行中英双语注释含工程单位 |
| 8 | 无魔法数 | 阈值/限幅/超时提常量（带单位后缀）或引脚；无非零裸数值比较 |
| 9 | R228A | TON/TOF/TP/R_TRIG/CTU 实例在主周期路径**无条件刷新**，不得位于任何 IF/CASE 分支内 |
| 10 | R228B | 每个故障锁存位写明解除式并自证可满足；禁 `NOT bEnable AND NOT _bFaultLatch` 恒假式 |
| 11 | 占位符禁词 | 零命中 `TODO`/`FIXME`/`XXX`/`待补`/`placeholder` |
| 12 | 码位独占 | 头部∪全文实测码位与本轮其余 19 件及全库 785 件零撞车；Device 件避开 `0590~0599`；新件码段与子库既有段不连续须在头注释写明分段理由（R192） |
| 13 | 整数进位点 | ceil/round/钳制/圈数件对「正好整除」与「上限+1」两点各推一条向量；禁 `TRUNC(x)+1` 写法 |
| 14 | 溯源短语 | 头部 Origin 二选一（见 §3 固化要求），与 `RAW_NOTES_R45.md` 可对齐 |
| **15** | **枚举 ⊆ CASE 标签（R128）** | 枚举全部成员在 CASE 中出现显式标签；`eFault` 不得只靠 ELSE 兜底（R44 台账已挂 6 件同类缺陷） |
| **16** | **安全侧赋值来源** | 安全侧（故障/越界/退化分支）赋的值不得引用本闸判定集合内的量（R124/R127） |
| **17** | **单拍脉冲撤销点** | 信息码/完成沿类单拍输出，必须在段 1 预清零且仅在唯一分支置位，禁止跨拍残留（R44 范式） |

- 逐类加权：纯函数件（序 4）最小判定 = #1~#8、#11~#14；FB 状态机件 = 全 17 项。
- 记账格式：`件名 | PASS/FAIL | 失败项号`；FAIL 件当场返修，不得带入终审。

---

## 3 P0 返修（2 件，排在 20 件编码之前）

详见 `DISPATCH_R45.md` §2 的逐行返修规格。摘要：

| 件 | 缺陷 | 危级 | 目标版本 | 引脚契约 |
|---|---|---|---|---|
| `DL_Process/FB_DL_CalenderRollPress.st` | 双侧同步判据 L138 缺相位因子，`eIdle`/`eRelease` 可误锁 `039F`（中危，R281） | 中 | v1.0.0 → **v1.0.1** | 零变更（PATCH） |
| `DL_Process/FB_DL_IvCurveScan.st` | 复位沿作用域越界，L121~132 在非故障相清窗内极值（轻危，R283）；顺带修 `fFfPu` 在 `eDone` 相输出恒 0 | 轻 | v1.0.0 → **v1.0.1** | 零变更（PATCH） |

- 返修后义务：两件各自单独回写 registry（`version` 字段）+ JSONL 对应行**替换**（不追加）+ 两库 `VERSION.md` / `MANUAL_DL_Process.md` 该节同步。

---

## 4 债务与三向一致对账（本轮实测）

| 项 | 实测 | 处置 |
|---|---|---|
| ROADMAP 空勾条目 | **98 条**（`^- \[ \] \`名\`` 口径），其中 **35 条 registry 已注册** → 三向一致差额 35 条 > 10 | 按 R192 出**专项回写脚本**（下轮首位 P0 非编码任务），本轮只记账不改 ROADMAP |
| ROADMAP 真待办 | 63 条（≥30） | **不补写新条目**（判定条件未触发），本轮只做「只追加不重写」的例外：无 |
| 编译验证债 | 连挂 40+ 轮（R44 已判 R195 触发条件满足） | R45 首位 P0 应为**实编译抽样**；闸未开则本轮 20 件须回避高复杂度转换/编解码件（已回避，MathData 仅 1 件低复杂度） |
| 手册补录债 | Device/Motion/Process 历史件接口表仍欠多轮 | 按 ≤10 件/轮倒序推进，本轮挂账不新增 |

---

## 5 本轮源配额与回写预告

- **零检索轮目标 WebSearch 0/3**：20 件全部复用源矩阵既有 ◐ 行（`t1-2` / `t1-6` / `t2-1-lgf` / `t2-2-lbp` / `t2-4-s7-motion` / `t2-5-modpid` / `t2-6-rockwell-aoi` / `t2-8-isa182`）+ 自研行业池（锂电/光伏/公用工程）与自研线 2 件（表决/顺序联锁惯例）。**无 ☐→◐ 开组、无 ◐→✔ 收口**（T0 八行已 ✔，本轮零触碰）。
- 配额满足：「≥1 个 T2 非 ST 源」（t2-1 / t2-5 / t2-8 多行）+「≥1 个 T1 ST 原生源」（t1-2 / t1-6）。
- 收尾回写义务：SOURCE_HUNTING_MATRIX §4 追加 R45 实测行；两件返修件所属 `VERSION.md` / `MANUAL` / 顶层 `CHANGELOG`（v2.37.0 预置节）/ `README` / `LIBRARY_MANUAL` 五件套同步；`AGENT_EVOLUTION_LOG` 复盘；三向一致逐条对账（差额 35 条挂下轮专项）。
