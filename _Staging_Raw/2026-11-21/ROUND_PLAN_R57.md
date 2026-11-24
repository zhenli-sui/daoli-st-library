# R57 轮次计划（ROUND_PLAN_R57，2026-11-21 02:10）

20 件 / 4 批。选型结构：T0 防御性包装 15 件（`iec-std-wrapper`，委托平台内建/标准语义，禁重实现数学内核）+ ROADMAP R56 评估转正 2 件（ESD 族）+ T2 1 件（t2-lbp 三段联锁骨架）+ T1 2 件（t1-oscat 域外行为纪律 / t1-oscat-building ROOM_CONTROL 深化）。配额说明：本轮非纯 T0 轮，含 1 个 T2 组件族（Passbox 联锁，借 LBP「命令-监视-判定」三段分层）与 1 个 T1 组（OSCAT Building ROOM_CONTROL 待挖子项夜间吹扫），满足「≥1 T2 或 T1」双保险。

| 序号 | 组件名 | 分类 | 前缀 | 一句话功能 | 来源标签 | 复杂度 | 批次 |
|---|---|---|---|---|---|---|---|
| 1 | FB_DL_TpRetrigger | DL_Base | FB_DL_ | 可重触发 TP 脉冲定时变体：触发窗内重触发刷新 ET，与 PulseStretch（脉宽拉伸）分工声明 | iec-std-wrapper | 3 | 1 |
| 2 | FB_DL_EdgeMasterSlaveSync | DL_Base | FB_DL_ | 主从双通道沿同步判定：主/从沿落在同窗 ±tSync 才出有效脉冲（安全回路通道一致性） | iec-std-wrapper | 4 | 1 |
| 3 | FB_DL_EncoderQuadCount | DL_Base | FB_DL_ | 正交 A/B 两相四倍频加减计数，溢出饱和不回绕、计数与方向分离出口 | iec-std-wrapper | 5 | 1 |
| 4 | FB_DL_SignalStagnationWatch | DL_Base | FB_DL_ | 信号呆滞检测：值纹波消失 + 边沿计数归零双判据持续 tStall 判卡死，与 SignalDebounce（抑制）分工为（检出） | iec-std-wrapper | 3 | 1 |
| 5 | FB_DL_SensorDropoutHold | DL_Base | FB_DL_ | 传感器掉线/无效拍保持上次有效值 + 保持时长出口，超窗置级；域外行为显式化纪律 | t1-oscat | 3 | 1 |
| 6 | FC_DL_AsinSafe | DL_MathData | FC_DL_ | 反正弦防御包装：入参 [-1,1] 钳位 + 钳位发生标志，内部委托 ASIN | iec-std-wrapper | 3 | 2 |
| 7 | FC_DL_AcosSafe | DL_MathData | FC_DL_ | 反余弦防御包装：入参 [-1,1] 钳位 + 钳位发生标志，内部委托 ACOS | iec-std-wrapper | 3 | 2 |
| 8 | FC_DL_LogSafe | DL_MathData | FC_DL_ | 自然对数防御包装：x<=0 拦截 + 非有限拦截 + 下界钳 1E-300 出错误码，内部委托 LN | iec-std-wrapper | 3 | 2 |
| 9 | FC_DL_ExpSat | DL_MathData | FC_DL_ | 指数防御包装：上溢饱和至 LREAL 域上界不出 Inf + 非有限拦截，内部委托 EXP | iec-std-wrapper | 3 | 2 |
| 10 | FC_DL_PowIntSat | DL_MathData | FC_DL_ | 整数幂防御包装：指数域钳位 + 底数零/负分支明确 + 溢出饱和，不依赖 EXPT 浮点路径 | iec-std-wrapper | 4 | 2 |
| 11 | FC_DL_SignumCalc | DL_MathData | FC_DL_ | 三态符号函数：负/零/正 + 浮点容差 fEps 判零 + 非有限拦截 | iec-std-wrapper | 2 | 3 |
| 12 | FC_DL_RmsCalc | DL_MathData | FC_DL_ | 窗口均方根：逐样本平方累加防溢出（除以窗长后开方）、窗长 1..4096 钳位 | iec-std-wrapper | 3 | 3 |
| 13 | FC_DL_ParityCalc | DL_MathData | FC_DL_ | 奇/偶校验位计算（WORD/DWORD 位串），位宽显式参数、无效位宽拒算 | iec-std-wrapper | 3 | 3 |
| 14 | FC_DL_PeakToPeakCalc | DL_MathData | FC_DL_ | 峰峰值（窗口 max−min）+ 占量程百分比出口，非有限样本剔除计数 | iec-std-wrapper | 2 | 3 |
| 15 | FC_DL_InterpStepNearest | DL_MathData | FC_DL_ | 查表最近邻（阶梯保持）插值：与 Hermite/CubicSpline/Lagrange/Linear 分工为离散保持口径，越界端点钳位不外插 | iec-std-wrapper | 4 | 3 |
| 16 | FB_DL_EsdGroundMonitor | DL_Device | FB_DL_ | ESD 接地连续性监视：接地电阻窗 + 双阈值迟滞判级，NE107 健康语言出口（ROADMAP R56 评估项转正） | self-esc（次源 t2-8 NE107） | 4 | 4 |
| 17 | FB_DL_IonizerAirflowInterlock | DL_Device | FB_DL_ | 离子风机风速联锁：风速低于下限持续确认后锁存，放行门控出口与消电离有效性分离 | self-esc（ROADMAP R56 评估项转正） | 4 | 4 |
| 18 | FB_DL_PassboxInterlockSeq | DL_Process | FB_DL_ | 传递窗（Passbox）A/B 门三段互锁顺控：单门互斥 → 传递就绪 → 对侧放行，反馈矛盾按安全侧拒动 | t2-lbp | 5 | 4 |
| 19 | FB_DL_NightPurgeSeq | DL_Process | FB_DL_ | 夜间免费制冷吹扫顺控：温差闸 + 时段窗 + 开窗许可三重判据，与 FrostProtectFreeze（防冻）分工为（利用冷量） | t1-oscat-building | 5 | 4 |
| 20 | FB_DL_ProofTestSeq | DL_Device | FB_DL_ | 联锁功能证明试验顺控：周期性激励-反馈回路验证，试验失败挂 NE107 eCheckFunction/eMaintenanceReq | t2-isa-ne107 | 4 | 4 |

## 边界安全条件（逐条，派单必带）

1. TpRetrigger：PT 钳位非负；重触发只刷新 ET 不叠加；首扫无假触发（Q 初值 FALSE）；PT=0 时 Q 单拍脉冲且 ET=0。
2. EdgeMasterSlaveSync：tSyncWindow 钳位 [T#1MS, T#1S]；同拍双沿判有效；窗内多从沿只受理一次；非有限输入拍出无效并冻结。
3. EncoderQuadCount：A/B 同拍跳变（非法 00↔11）按状态保持丢步计数；计数饱和 ±DL_TURNS_MAX 口径不回绕；方向出口按格雷序状态机，禁 MOD。
4. SignalStagnationWatch：纹波死区 fEps 显式参数；tStall 期间边沿计数窗独立重置；使能断开即复位不锁存。
5. SensorDropoutHold：首拍无历史值时输出安全侧 0 并置 bNoValid；保持窗超窗后输出保持但置级（不回 0，防联锁误动——与 NtcTempScan 口径一致声明）；无效判据 = 非有限双判据。
6. AsinSafe：|x|>1 钳到边界并置 bClamped；非有限拦截返回 0 + 错误码；不新增输出域外值。
7. AcosSafe：同 6 口径（镜像件，边界向量取 ±1 两点）。
8. LogSafe：x<=0 判错误且返回安全下界不返回 NaN；x→0⁺ 钳下界 1E-300；非有限拦截。
9. ExpSat：x > 709.78（LREAL 上溢界）饱和不 Inf；结果非有限二次复核；x 负大 → 下饱和钳 ≥0。
10. PowIntSat：指数钳位 [0, 63]（LREAL 安全幂界）；底 0 的 0 次幂判错误；负底奇偶幂符号显式分支；溢出饱和。
11. SignumCalc：|x|<fEps 判零（禁 `=` 判等）；fEps<=0 组态错误；非有限返回 0 + 错误码。
12. RmsCalc：平方和用增量式 sum += x²/n 防大数溢出；窗长钳 1..4096；非有限样本剔除并计数出口。
13. ParityCalc：位宽参数 1..64 钳位；位宽非法拒算置错误；奇偶两模式枚举参数。
14. PeakToPeakCalc：窗长 1 起步（单样本峰峰值 0）；非有限样本不参与且计数；fSpan<=0 时百分比出口置 0 并置无效标志（防除零）。
15. InterpStepNearest：n 点表 ≥2 否则拒算；x 越界钳端点不外插；相邻 x 相等（表非单调）取先见点并置告警；距离并列取左邻（`<` 严格判据，正中不摇摆）。
16. EsdGroundMonitor：电阻窗上下限组态闸（下限>0 且上限>下限）；迟滞收窄口径；传感失效锁存优先于判级。
17. IonizerAirflowInterlock：风速下限>0 组态闸；确认窗 tConfirm 内持续低于才锁存（单拍毛刺不动作）；失能即解锁回 Idle 且输出安全侧断开放行。
18. PassboxInterlockSeq：双侧开门命令同拍互斥仲裁（复位优先）；反馈矛盾按门未关（保守侧）；超时窗>确认窗配比约束（R100 口径）；ENUM+CASE 含 ELSE 兜底。
19. NightPurgeSeq：温差闸带 0.5 K 回差；开窗许可失效即回驻留不中断执行中段；时段窗跨午夜用年内序数法（禁 MOD）；最小执行时长防反复启停。
20. ProofTestSeq：试验周期窗与试验持续窗配比约束；试验中真实故障与试验失败码分段；试验请求仅在设备空闲相受理（运行相拒并置信息级）。

## 拒单记录（撞名三查命中即拒，R214/R228）

| 拒单候选 | 命中位置 | 处置 |
|---|---|---|
| FB_DL_RtoTimer | _names_r57.txt：FB_DL_RtoEx（同义 RTO 已收口） | 淘汰 |
| FB_DL_WatchdogKick | FB_DL_WatchdogMonitor / FB_DL_WatchdogPulseMon（看门狗族） | 淘汰 |
| FC_DL_RolDwordEx / FC_DL_RorDwordEx | FC_DL_RolEx / FC_DL_RorEx（通用口径已覆盖）+ ROADMAP L948 查重提示 | 淘汰 |
| FC_DL_ConcatBounded | FC_DL_StringConcatEx | 淘汰 |
| FC_DL_ReplaceFirst | FC_DL_StringReplaceAtEx（nth 替换已覆盖首次） | 淘汰 |
| FC_DL_Atan2Safe | FC_DL_Atan2Ex / FC_DL_AtanEx | 淘汰 |
| FC_DL_MidStrBounded / FC_DL_InsertStrBounded | FC_DL_StringMidEx / FC_DL_StringInsertEx | 淘汰 |
| FC_DL_TruncToUintSat | FC_DL_RealToUintSat / FC_DL_DintToUintSat | 淘汰 |
| FC_DL_SqrtSafe / FC_DL_TanSafe | FC_DL_SqrtEx / FC_DL_TanEx | 淘汰 |
| FC_DL_LeftStrBounded / FC_DL_RightStrBounded | FC_DL_StringLeftEx / FC_DL_StringRightEx | 淘汰 |
| FB_DL_BistableArbiter | FB_DL_SRBistable / FB_DL_RSBistable（仲裁已收口） | 淘汰 |
| FB_DL_MajorityVote3 | FB_DL_Vote2oo3 | 淘汰 |
| FC_DL_ModSignedNorm | FC_DL_ModLrealSafe | 淘汰 |
| FB_DL_EdgePrescaler | FB_DL_EdgeDivider | 淘汰 |
| FB_DL_HeartbeatDuplex | FB_DL_HeartbeatGen | 淘汰 |
| FC_DL_MeanCalc | FC_DL_WeightedMeanCalc / FB_DL_SignalStatistics（均值出口） | 淘汰 |
| FB_DL_SignalChatterDetect | FB_DL_PressureSwitchChatter（chatter 族） | 淘汰 |
| FB_DL_StatDevCalc 系 | FC_DL_StdDevOnline / FC_DL_QuantileCalc / FC_DL_MedianAbsDev / FC_DL_GeoMeanCalc | 淘汰 |

## 批次说明

- **批 1（DL_Base 信号/时序底座）**：TP/主从沿/四倍频/呆滞/掉线保持——零依赖，先行为上层提供干净信号语义。
- **批 2（DL_MathData T0-4 数学防御核心）**：Asin/Acos/Log/Exp/PowInt 五件同构防御样板（钳位+错误码+委托内建），批 1 无依赖可并行。
- **批 3（DL_MathData 统计/插值补口）**：Signum/Rms/Parity/PeakToPeak/StepNearest——Rms 复用批 2 惯性（无依赖，仅排期顺延），StepNearest 与插值族分工声明在头注释互引。
- **批 4（Device/Process 工艺与设备层）**：ESD 双件 + ProofTest（Device ×3）、Passbox/NightPurge（Process ×2）——依赖批 1 信号底座语义（呆滞/掉线保持/沿同步）与批 2 数值闸惯例，故排末批。
