# RAW_NOTES_R54 — R54 轮源使用留痕（2026-11-20）

## 一、检索执行

- **WebSearch：0 次（零检索轮，配额 0/3 未动用）**。本轮全部源信息复用 `SOURCE_HUNTING_MATRIX.md` 第 5 节既有 ◐ 行、`RAW_NOTES_R39~R53` 历轮留痕与 `ROUND_PLAN_R53.md` 差额清单，零新建源组、零重复挖掘已收口组。

## 二、本轮所用源（组/条目/许可证/提取点）

| # | 组件 | 源组 | 条目/待挖子族 | 许可证 | 提取点 | 状态 |
|---|---|---|---|---|---|---|
| 1 | BitArrayMultiSegMove | T2-1 LGF · Bit Logic | 「LWORD 单字版与多段一次搬仍待挖」（矩阵 151 行） | MIT（Siemens LGF 公开库） | 只借「批量段=独立层级」组内切分语义，段表结构与搬移实现自有 clean-room | ◐ |
| 2 | ChecksumLwordSum | T2-1 LGF · Data Handling | 「校验族尚余 CRC-16 反射 / LWORD 累加和待挖」（矩阵 156 行） | MIT | 只借「校验和独立成族」分类事实；累加回卷用条件加减（R55 教训）自有 | ◐ |
| 3 | HealthStatusArbiter | T2-8 ISA-88/ISA-18.2/NE107 | 「NE107 实现块仲裁件（多源健康聚合）待挖」（矩阵 166 行） | 公开标准条款 | 只借 NE107 六态健康语言与「编号即仲裁优先级」既立契约（I_DL_DeviceHealth 唯一属主），聚合算法自有 | ◐ |
| 4 | PrbsSignal | T1-1 OSCAT Basic ◐/自研 | PRBS 伪随机激励行为定义 | 公共域/行为定义借用 | 只借 PRBS 输出-宽度行为定义；LFSR 抽头/全零注入/相位保持实现 100% 自有 | ◐ |
| 5 | PidRelayAutoTune | 自研-公开方法 | Åström–Hägglund 继电器反馈自整定公开公式 | 公开文献公式 | 只借公开公式（Ku=4d/πa、Tu=振荡周期）；状态机/码位/引脚 100% 自有 | 新借用线 |
| 6 | HistogramBinTally | T2-1 LGF · Measurement | 「统计与峰值检测族待挖」（矩阵 160 行） | MIT | 只借「滤波/统计归测量」组边界；分箱/钳边/占比实现自有 | ◐ |
| 7 | PnDiagAlarmDecode | T1-7 PLCnext Community | 「PROFINET 诊断（PN_ALARM_DIAG 语义）族待挖」（矩阵 175 行） | Apache-2.0 公开资料 | 只借 PN 告警位语义与严重度分档公开语义；码表/枚举/文本样板（R37）自有 | ◐ |
| 8 | SweepFreqGen | T2-1 LGF · Signal Generators | 「频率发生族待挖（需评估与 PulseGenerator 职责）」（矩阵 158 行） | MIT | 只借「发生器按波形形状切块」组内切分语义；扫频相位积分/驻留表自有，职责分立声明在案 | ◐ |
| 9 | FirstOrderIdent | 自研 | 与 4/5/8 号激励源配套的 FOPDT 三点法辨识 | —（自研） | 全自有；输出供 PidRelayAutoTune / SmithPredictor 取参，属主边界声明 | 自研线 |
| 10 | CamTableLiveTrim | T1-6 PLCopen Motion | 「凸轮动态修调待挖」（矩阵 171 行） | 公开规范条款 | 只借 MC_CamIn 凸轮表组织公开语义；运行中修调/单调性回滚实现自有 | ◐ |
| 11 | NightFlushPurge | T1-2 OSCAT Building | 「夜间吹扫仍待挖」（矩阵 169 行） | EPL-2.0 公开资料 | 只借行为定义（低温窗吹扫）；三相编排/降级退出自有，日历窗复用库内 WeekOfYearCalc | ◐ |
| 12 | AirCompressorLoadUnload | T2-2 LBP 基础工艺 ◐/行业池 | 「命令→监视→判定」分层骨架借用（矩阵 161 行同 R13 纪律） | 公开资料 | 只借三段分层骨架；双阈迟滞/卸载联锁/最小驻留判据自有 | ◐ |
| 13 | RecipeSwitchHandover | T2-7 PackML/OMAC + T2-8 ISA-88 | 「配方切换/批次编排（ISA-88 衔接）待挖」（矩阵 165 行） | ISA-TR88 公开规范 | 只借公开相状态模型与「低优先丢弃不排队」既立语义（BatchPhaseBase）；交接时序自有 | ◐ |
| 14 | EnthalpyPrioritySwitch | T1-2 OSCAT Building | 「焓值优先切换仍待挖」（矩阵 169 行） | EPL-2.0 | 只借行为定义；与 R6 EnthalpyCompareCtrl 职责分立（切换 vs 判定）已写入规格 | ◐ |
| 15 | TankAgitationSeq | T2-8 ISA-88 相语义扩族 | 相语义新工艺载体（搅拌时序） | 公开标准条款 | 只借公开相模型；液位/扭矩联锁判据行业池自有 | ◐ |
| 16 | AxisTorqueRippleWatch | T1-6 PLCopen Motion ◐/自研 | 运动诊断缺口（矩阵 171 行外延） | 公开规范/自研 | 只借「轴状态归运动层」纪律（R31）；纹波/周期性判据自有 | ◐ |

## 三、返修与终审用源（非新组件）

- `FB_DL_ControlOutputSlewWatch.st`（DL_Algo，实测定位）：R52 五抽「严重」返修核验，源 = 本库存量件本体。
- R53 五抽终审 5 件（PumpSurgeGuard / BearingVibTrend / WetBulbCalc / SensorDriftBaseline / AxisBacklashStepComp）：源 = 本库 R53 存量件本体，零外部源。

## 四、合规结论

- 27 个候选名零外部代码行复制；全部 clean-room 或公开标准/公式借用，许可证口径与矩阵既有登记一致（MIT / EPL-2.0 / Apache-2.0 / 公开规范条款）。
- T0 快车道零动用（八组已收口）；T1-3 OSCAT Network 已收口（✔）未触碰；packml/modbus 线按 M-E2 勘误不开组，13 号走 ISA-88 相语义借用不重复记账。
