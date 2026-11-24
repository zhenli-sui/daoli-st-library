# ROUND_PLAN_R58（第 58 轮 · 2026-11-21 04:41 · 无人值守 · 阶段一锁定件）

> 主控纪律：R249 生效 → 本轮新件 = **16**；R214 撞名三查已执行（registry 全文反证 + ROADMAP 全文 + 六库文件树 ls），16/16 全部 0 命中。
> 零检索轮：T0 八组 8/8 ✔ 余量 0 不立项；全部来源标签回指既有 ◐ 行 / ROADMAP 评估项 / 公开标准条款，100% clean-room。

## 一、R58 新件派单表（16 件 · 4 批 · 批内按序 1→4）

| 序号 | 组件名 | 分类 | 前缀 | 一句话功能 | 来源标签 | 复杂度 | 批次 |
|---|---|---|---|---|---|---|---|
| 1 | FB_DL_VoteKooN | DL_Base | FB_ | N 中取 K 安全表决器（MooN 架构，通道故障掩码注入 + K 可组态 + IEC 61508 公开语义，与 Vote2oo3 固定 2oo3 分工互引） | self-std（IEC 61508 MooN 条款） | 中 | 1 |
| 2 | FB_DL_SimInputBank | DL_Base | FB_ | 调试仿真输入注入组（8 通道手动假值旁路真实输入 + 仿真标志锁存 + 退出自动回真实值，与 OutputForcingBank 输出侧成对） | self（库内对称件，R216 互引） | 中 | 1 |
| 3 | FC_DL_ThermocoupleLinearization | DL_MathData | FC_ | 热电偶 mV↔温度双向线性化（K/N/S 型 NIST ITS-90 公开系数多项式，与 RtdLinearization / TempUnitConvert / NtcTempScan 三分工边界按 ROADMAP 1083 行写死） | roadmap-p1（R56 评估项落地） | 中 | 1 |
| 4 | FB_DL_SkewKurtosisCalc | DL_MathData | FB_ | 在线偏度/峰度统计（Welford 高阶矩递推，非有限样本剔除计数，与 StdDevOnline/CovarOnline 同族补口） | t2-1-lgf-math（统计族待挖项） | 中 | 1 |
| 5 | FC_DL_SolveLinear3 | DL_MathData | FC_ | 三阶线性方程组求解（部分主元高斯消元 + 相对奇异判据，与 Matrix3Inverse 分工互引：Ax=b 直接解 vs 求逆） | t2-1-lgf-math（公开数值教材 clean-room） | 中 | 2 |
| 6 | FC_DL_PmvComfortIndex | DL_Algo | FC_ | PMV/PPD 热舒适指标计算（ISO 7730 公开六参数公式链，域闸门四段式 R45，供 HVAC 优化目标函数） | t1-oscat-building（热舒适域） | 中 | 2 |
| 7 | FB_DL_SoftStarterDrive | DL_Device | FB_ | 软启动器驱动封装（晶闸管斜坡启停 + 旁路接触器反馈校验 + 启动超时保护，实现既有 I_DL_MotorDriver 接口，补齐 DOL/星三角/软启/变频四启动家族，不新建接口） | t2-2-lbp（cmd/ind 分离范式） | 中高 | 2 |
| 8 | FB_DL_ElectricLinearActuator | DL_Device | FB_ | 电动推杆驱动（到位电流窗判定 + 堵转超时 + 行程两端限位互锁，无位置反馈纯时间/电流双模） | t2-2-lbp（三段分层骨架） | 中 | 2 |
| 9 | FB_DL_OptimalStartStop | DL_Algo | FB_ | 最优启停预调度（按建筑热惯性差值提前/推迟启停，_learned 系数在线修正，与 EnergySavingMode 空闲节能分工互引） | t1-oscat-building（HVAC optimal start 公开语义） | 中高 | 3 |
| 10 | FB_DL_PeriodicDisturbComp | DL_Algo | FB_ | 周期性扰动重复控制补偿器（内模原理逐拍正反馈累加 + 收敛增益与遗忘因子钳位，轧辊偏心/卷筒周期张力场景，与 DisturbanceObserver 非周期观测分工互引） | self（控制理论公开，重复控制/内模） | 中高 | 3 |
| 11 | FB_DL_CondensateDrainSeq | DL_Device | FB_ | 储气罐/空压机冷凝水自动排污阀时序（定时+液位双触发 + 排放确认反馈 + 排放超时诊断） | t2-2-lbp（命令→监视→判定三段） | 中 | 3 |
| 12 | FC_DL_CamTableGenSeg | DL_Motion | FC_ | 凸轮表段型自动生成（线性/五次多项式/修正正弦三类段型按边界点生成点列，单调性自检，供 CamTableValidate 前置） | t1-6-plcopen（凸轮族补口） | 中 | 3 |
| 13 | FB_DL_AxisSafetyStateMon | DL_Motion | FB_ | 轴安全功能状态字监视（STO/SLS/SOS 反馈一致性 + 仅监视不发令，与 AxisSs1StopSeq 执行件分工互引） | t1-6-plcopen（轴侧安全层同层扩展） | 中 | 4 |
| 14 | FB_DL_GowningRoomSeq | DL_Process | FB_ | 洁净室更衣室顺控（更衣流程状态 + 更衣时限 + 双门互锁，与 AirShowerInterlockSeq / PassboxInterlockSeq 构成人流三件，ROADMAP 1087 行评估项落地） | roadmap-p2（R56 评估项落地） | 中 | 4 |
| 15 | FB_DL_MaterialHoldTimeEnforce | DL_Process | FB_ | 物料保持时限强制（中间品/批次超时限判 NG 锁存 + 复检放行沿 + 时限台账，ISA-88 批次语境次源） | self（GMP 保持时限公开语义） | 中 | 4 |
| 16 | FB_DL_FirstArticleLock | DL_Process | FB_ | 首件检验锁定（首件未放行禁止批量运行 + 换型自动重锁 + 放行沿台账，汽车/电子行业公开流程） | self（行业公开流程） | 中 | 4 |

### 撞名三查拒绝记录（R214，拒 5 件留痕）
| 被拒候选 | 拒绝理由 |
|---|---|
| FC_DL_ShlDwordEx / FC_DL_ShrDwordEx | ROADMAP 948 行自标「疑似与存量同义」；FC_DL_ShlEx/ShrEx 已覆盖 DWORD 口径，R61 式实测查重未过 → 同义邻件拒 |
| FB_DL_QcSamplingTrigger | 与 DL_Base 存量 FB_DL_SamplingTrigger 同义邻件 → 拒 |
| FC_DL_Matrix3Multiply | R13 RAW_NOTES 明文「矩阵乘法/特征值方向不立」（PLC 侧无用例）→ 重复立项拒 |
| FB_DL_Matrix2Invert | 与 FC_DL_Matrix3Inverse 尺寸变体凑数风险（R228 枯竭阈值纪律）→ 拒 |
| FC_DL_Crc16Reflected | Crc16Modbus/Crc16Ccitt/Crc16Generic 校验族已三件，反射变体挖潜价值低 → 拒 |

## 二、R58 返修清单（R57 五抽挂账 6 件，编码专家单调用执行；R333：本轮只挂账不改码）

### ① FB_DL_EncoderQuadCount · 中项：首拍假步进 + _bInit 死代码
- 路径：`C:\Library\DL_Base\FB_DL_EncoderQuadCount.st`，缺陷现场段 1（72~75 行）与段 4（95 行）。
- 机理：段 1 只写 `_eGrayNow := eQ0` 且立刻被段 3 无条件重锁存覆盖 → `_bInit` 无实效（死代码）；`_eGrayPv` 保持声明初值 eQ0，若上电时编码器停在非 00 态，首拍段 4 用陈旧 `_eGrayPv` 判转移 → 假 ±1 步进甚至假丢步。
- 修法（行级）：段 1 改为 `IF NOT _bInit THEN _bInit := TRUE; _bFirst := TRUE; END_IF`（删除对 `_eGrayNow` 的赋值，删除该行注释「预置后由段 2 按当拍 AB 重锁存」）；新增 VAR `_bFirst : BOOL := FALSE; // 首拍跳过步进判定标记`；段 4 判式 95 行改为 `IF bEnable AND (NOT _bFirst) AND (_eGrayNow <> _eGrayPv) THEN`，段 4 末尾（END_IF 之后、段 5 之前）加 `_bFirst := FALSE; // 首拍标记仅豁免一拍`；头注释修订历史补 v1.0.1 记录。

### ⑥ FB_DL_EncoderQuadCount · 轻项（同族第二缺陷）：丢步判式
- 路径同上，缺陷现场段 4 ELSE 分支（103/112/121/130/134 行）与段 5（155~160 行）。
- 机理：对角非法跳变（如 00→11）实际丢失 2 个四分之一周期步，段 5 仅 `nMissCnt + 1`；需核对 `nMissCnt` 声明注释单位——若注释为「丢步计数 [步]」则与实现「事件数」矛盾（单位标注红线）。
- 修法（行级）：二选一并落头注释——A 案：对角跳变 `nMissCnt := nMissCnt + 2`（步口径，四分支逐处改）；B 案：声明注释改为「非法跳变事件计数 [次]」（零代码语义变化，仅注释）。编码专家按 MANUAL 既有引用检索后择一（检索到手册引用即选 B 案最小改动），修订历史补记。

### ② FC_DL_RmsCalc · 中项：非有限输入静默不置 eErr
- 路径：`C:\Library\DL_MathData\FC_DL_RmsCalc.st`，缺陷现场段 3（74~79 行）。
- 机理：非有限样本剔除仅 `nNanCnt+1`，部分剔除（nUsed>0 且 nNanCnt>0）时 eErr 保持 0，调用方无法得知口径已收窄（违反「信息码随事件置位」惯例，对照同轮 PowIntSat 0201 范式）。
- 修法（行级）：段 4 之前插入：`IF (nNanCnt > 0) AND (nUsed > 0) AND (eErr = 16#0000_0000) THEN eErr := 16#0003_0005; bError := TRUE; END_IF // 信息级：非有限样本已剔除，口径为有效样本 RMS`；`bValid` 保持 TRUE（有效样本统计量仍可用，与 0303 钳位件 bValid=FALSE 的区别在头注释偏离段写明）；全剔除路径 0304 优先级在先不动；头注释修订历史补 v1.0.1。

### ③ FB_DL_PassboxInterlockSeq · 中项：bReqRejected 无清零路径
- 路径：`C:\Library\DL_Process\FB_DL_PassboxInterlockSeq.st`，缺陷现场声明（72 行）与段 4（131~132 行）。
- 机理：输出 `bReqRejected := TRUE`（132 行）后全文件无任何清零点——首次双侧同拍拒绝后该「单拍」信号永久保持，违反 R25 单拍标志生命周期三律（有置位点必须有同拍或明确沿的清零点）。
- 修法（行级）：段 1 预置区（与其它输出预置同行区域，约 49 行附近输出预置段）加 `bReqRejected := FALSE; // 单拍标志每拍预置清零（R25）/ informational reject pulse preset false each scan`；置位点 132 行不动；确认体内无其它读点依赖其锁存语义（已核：仅出口使用）；头注释修订历史补 v1.0.1。

### ④ FB_DL_NightPurgeSeq · 中项：缺夜窗末退出
- 路径：`C:\Library\DL_Process\FB_DL_NightPurgeSeq.st`，缺陷现场段 6 ePurge 相（163~170 行）。
- 机理：执行相退出条件只有「失能 / 许可失效 / 温差退出且 tMinRun 满足」三条；若温差始终满足，吹扫会持续到日间（把热空气灌进建筑），违背本件「利用夜间冷量」的存在理由——夜窗结束（`_bNight` 变假）必须退出。
- 修法（行级）：168 行 ELSIF 之后加 `ELSIF NOT _bNight THEN // 夜窗结束退出：外因一次性事件，不受 tMinRun 门控（不会抖振，头注释偏离段声明）/ the night window end exits without the minimum gate`，分支体 `_ePhase := E_DL_NpsPhase.eDwell;`；同步更新段 6 行首注释「退出条件 ≥3」→「退出条件 ≥4」；头注释功能描述补第五条边界、修订历史补 v1.0.1。

### ⑤ FC_DL_PowIntSat · 轻项：首事件码覆盖
- 路径：`C:\Library\DL_MathData\FC_DL_PowIntSat.st`，缺陷现场段 4（94 行）。
- 机理：指数先钳位（0202，66/72 行置码）后幅值循环又饱和（0206，94 行**无条件**置码）→ 0206 覆盖先发事件 0202；段 5 兜底有 `IF eErr = 16#0000_0000` 首事件闸（111 行）而段 4 没有，同件双轨不一致。
- 修法（行级）：94 行改为 `IF eErr = 16#0000_0000 THEN eErr := 16#0002_0006; END_IF // 首事件优先置码（对齐段 5 闸式）`；95~97 行 bError/bValid/bClamped 赋值保持无条件（标志级聚合，码级唯一）；头注释修订历史补 v1.0.1。

## 三、R193 三族扩面清账清单（供主控/编码专家复核，本轮不要求全部闭环）

### 族 1｜首拍初始化（R19~R21 范式族存量排查）
| 候选件 | 子库 | 判定 |
|---|---|---|
| FB_DL_KalmanFilter1D | DL_Algo | 疑似（状态/协方差初值首拍） |
| FC_DL_Kalman2DSmoother | DL_MathData | 疑似（2D 初值与 1D 口径一致性） |
| FB_DL_RlsEstimator | DL_Algo | 疑似（P0 矩阵首拍） |
| FB_DL_LuenbergerObserver | DL_Algo | 疑似（观测器状态初值） |
| FB_DL_PrbsSignal | DL_Base | 疑似（种子首拍装填） |
| FB_DL_SweepFreqGen | DL_Base | 疑似（相位首拍连续性） |
| FB_DL_FirstOrderIdent | DL_Algo | 疑似（输出初值/首拍样本） |
| FB_DL_MovingAverage | DL_MathData | 无需修（窗口填充范式已固化并终审过） |

### 族 2｜单拍位信号（R24/R25 三律族存量排查）
| 候选件 | 子库 | 判定 |
|---|---|---|
| FB_DL_MotionCmdQueue | DL_Motion | 疑似（指令单发入队） |
| FB_DL_DeviceParamWrite | DL_Device | 疑似（写回单发） |
| FB_DL_RecipeSwitchHandover | DL_Process | 疑似（切换握手单发） |
| FB_DL_SignalSeqGuard | DL_Base | 疑似（时序守卫单发） |
| FB_DL_PulseSeqVerify | DL_Base | 疑似（脉冲序验证） |
| FB_DL_CycleBarrierGate | DL_Base | 疑似（屏障门单拍） |
| FB_DL_AxisTeachOffset | DL_Motion | 疑似（示教单发） |
| FB_DL_OcvProbeDock | DL_Process | 疑似（探针对接单发） |

### 族 3｜非有限兜底（R79/R151 判式族存量排查）
| 候选件 | 子库 | 判定 |
|---|---|---|
| FC_DL_PolyEvalHorner | DL_MathData | 疑似（累乘溢出/非有限） |
| FC_DL_WetBulbCalc | DL_MathData | 疑似（迭代不收敛路径） |
| FC_DL_GeoMeanCalc | DL_MathData | 疑似（零/负值定义域） |
| FC_DL_CpkCalc | DL_MathData | 疑似（σ=0 除零） |
| FC_DL_FanLawMultiExpCalc | DL_MathData | 疑似（幂律非有限） |
| FC_DL_HumidAirEnthalpy | DL_Algo | 疑似（公式链非有限穿透） |
| FC_DL_HaversineDistance | DL_MathData | 疑似（大圆三角域） |
| FC_DL_CubicSplineInterp | DL_MathData | 疑似（区间外插域闸） |

## 四、统计快照（2026-11-21 04:41）
- 总库 1037 / 10,000（10.37%），registry v2.49.0，1037 名全唯一；counts 实测 sum = 1037，与 Base 118 / MathData 233 / Algo 121 / Device 188 / Motion 112 / Process 265 完全一致（零漂移）。
- 今日（11-21）已注册 40 / 200；距 1,050 差额 13（本轮 16 件收口后越线至 1053）。
- 矩阵覆盖率：台账 33 源组中 ✔ = 9（T0 八组 + T1-3），◐ = 24，☐ = 0 → 覆盖率 27%；本轮全部取自既有 ◐ 行 / ROADMAP 评估项 / 公开标准条款。
- 六库文件树 ls 实测：118/233/121/188/112/265 个 .st，与 registry 三向一致。
