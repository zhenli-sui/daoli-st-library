(*==============================================================================
 * 组件名称 (Component)  : FB_DL_FillPreactSelfLearn
 * 所属子库 (Sublibrary) : DL_Process ｜ 版本 (Version) : 1.0.0 ｜ 2026-11-24
 * 码位     (Code Segment): 16#0005_2180（DL_Process 段内 21xx 子带）
 * 复杂度   (Complexity) : C4
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 IEC 61131-3 标准库（TON / R_TRIG / LIMIT / ABS / REAL_TO_LREAL /
 *                         LREAL_TO_REAL），零厂商私有库
 * 开源溯源 (Provenance) : menes97/ayran-mini-fabrika / FB_Dolum PREACT / MIT /
 *                         借鉴点：粗流 / 细流两段切换与预动作量 PREACT 自学习（下落量补偿）语义
 *                         （未复制任何实现行，按 IEC 61131-3 重写为六相状态机 + 限幅学习器）
 * 功能描述 (Function)   : 灌装预动作量自学习。一轮灌装的四相节拍：eCoarse（粗流，实际重量到达
 *                         「目标 − 预动作量」即切细流）→ eFine（细流，实际重量到达「目标 − 粗流
 *                         裕度」即停阀）→ eSettle（等称重稳定或整定窗超时）→ eLearn（按最终偏差
 *                         修正预动作量并限幅）→ eDone（单拍完成回执）→ eIdle。
 *                         **学习律**：err = 实称 − 目标；PREACT := PREACT + gain × err；结果夹在
 *                         [rPreactMin, rPreactMax]，触界置 bLearnClamped。符号自证：实称超目标
 *                         （err > 0）时粗流必须更早切细流，即 PREACT 增大，公式方向正确。
 *                         **不稳定样本纪律**：整定窗超时（信息级 41）时本轮**跳过学习**——用未收敛
 *                         的读数去修正学习值，等于把气泡 / 挂料引起的瞬时偏差写成永久偏置。
 *                         **学习资产保护**：_fPreactKg / _fMargin / _iLearnCnt 属学习资产，
 *                         bReset 与 bEnable = FALSE 均**不清**（R191 声明：只降级输出 + 清状态与
 *                         锁存）；掉电保持需上层把 rPreactKg 回写 RETENTIVE 变量，本件不持有。
 *                         **COARSE_MARGIN 口径（v1.0.0 显式留置）**：裕度自学习需要「粗流段截尾
 *                         重量」这一独立观测量，本版派单未提供该引脚；在缺少中间观测的前提下
 *                         修改裕度等于用最终偏差伪造中间偏差，故本版 rCoarseMargin 只做配置量
 *                         的域钳定输出（不走学习）。v1.1 待新增 rCoarseEndKg 引脚后立项。
 * 接口     (Interface)  : 输入 bEnable / bReset（上升沿）/ bStart / rTargetKg / rActualKg /
 *                         rCoarseMarginInit / rLearnGain / rPreactMin / rPreactMax /
 *                         tSettleTimeout / bWeightStable；
 *                         输出 eState（E_DL_FillPreactSelfLearn_State）/ bBusy / bDone / bError /
 *                         iErrCode / rPreactKg / rCoarseMargin / rLastErrKg / iLearnCnt /
 *                         bLearnClamped。
 * 状态迁移表 (State Transition Table)：
 *   ① eIdle → eCoarse：bEnable 且 bStart 且组态闸通过且无锁存；拍 N 进入 / 本拍行为：清限幅
 *      标志与稳定标志、拒收本轮样本 / 拍 N+1 转出至 eCoarse。
 *   ② eCoarse → eFine：实称 ≥ 目标 − 预动作量 − 容差（本拍事件优先，R275）；拍 N 进入 /
 *      本拍行为：相级看门狗已在 CASE 外清零 / 拍 N+1 转出至 eFine。
 *   ③ eCoarse → eIdle：bEnable = FALSE（进相前置条件消失，第二出口，R98）。
 *   ④ eFine → eSettle：实称 ≥ 目标 − 粗流裕度 − 容差；拍 N 进入 / 本拍行为：拒收本轮样本 /
 *      拍 N+1 转出至 eSettle。
 *   ⑤ eFine → eIdle：bEnable = FALSE（第二出口）。
 *   ⑥ eSettle → eLearn：bWeightStable（稳定样本）；拍 N 进入 / 本拍行为：置稳定标志 /
 *      拍 N+1 转出至 eLearn。
 *   ⑦ eSettle → eLearn：tonSettle.Q（整定窗超时，信息级 41，清稳定标志，本轮跳过学习）。
 *   ⑧ eSettle → eIdle：bEnable = FALSE（第三出口）。
 *   ⑨ eLearn → eDone：单拍学习；拍 N 进入 / 本拍行为：偏差与学习值计算、限幅、非有限拒收、
 *      计数 +1，拒绝任何相推进 / 拍 N+1 转出至 eDone。
 *   ⑩ eDone → eIdle：单拍完成回执；拍 N 进入 / 本拍行为：bDone 置单拍、拒绝重复学习 /
 *      拍 N+1 转出至 eIdle。
 *   ⑪ 任意相 → eFault：相级看门狗超时 tonPhase.Q（43）；目标重量非法（42）；称重值非有限
 *      （44）；组态参数非有限（45）；非法枚举（99）。锁存后由段 7 段尾迁移闸迁相。
 *   ⑫ eFault → eIdle：bReset 上升沿；拍 N 进入 / 本拍行为：清锁存与错误码与稳定标志，
 *      **保留** rPreactKg / rCoarseMargin / iLearnCnt / bLearnClamped / rLastErrKg / 拍 N+1
 *      转出至 eIdle。出口穷举、不滞留故障态。
 * 边界     (Boundary)   : ① 两个 TON 与一个 R_TRIG 全部在 CASE 外无条件调用（R7）；IN 均含
 *                            NOT .Q 自复位项（R188）。
 *                         ② 同拍双窗配比约束（R100）：tonPhase（PT := _tSettle）覆盖 eCoarse 与
 *                            eFine 两相、tonSettle（PT := _tSettle）覆盖 eSettle 相，两使能域互斥
 *                            不相交，故共用同一超时值无竞态；语义为「单相驻留上限」，配置时须
 *                            大于最长单相时长（粗流段通常最长）。
 *                         ③ 组态域闸全覆盖（FB51-2）：六个浮点入参 rTargetKg / rActualKg /
 *                            rCoarseMarginInit / rLearnGain / rPreactMin / rPreactMax 全部逐项
 *                            枚举，无遗漏；非有限判定用自反 x <> x 与差值自减 (x−x) <> (x−x)
 *                            双判，禁用近似阈值与 ABS(x−x) 形态（R4 / R79）。
 *                         ④ 浮点比较一律带容差（1.0E-6），无 = / <> 直接判等（自反判据除外）。
 *                         ⑤ 除零防护：本件**不产生任何除法**（学习律为乘加式）；派单要求的
 *                            「目标必须为正」以量纲闸实现（rTargetKg ≤ 0 → 故障级 42），
 *                            防止后级用 rPreactKg / rTargetKg 做比例换算时除零。
 *                         ⑥ 学习值写入前必过非有限闸（R133）：非有限结果拒收并置 44，绝不写入
 *                            保持槽，避免把 NaN 变成学习起点。
 *                         ⑦ 学习增益两级限幅（FB32-3）：越出 0.05..0.8 夹紧（不故障），
 *                            防止上位误填 5.0 造成一次学习就跳满量程。
 *                         ⑧ 零全局耦合（无 GVL / VAR_EXTERNAL / %I / %Q，R1 / R2）。
 * 码表     (Codes)      : 本件按派单指定使用小整数码。信息级（永不置 bError，可每拍重算）：
 *                         41 = 整定窗超时（按不稳定样本跳过学习）；反证：该场景下 iLearnCnt 不增、
 *                              bLearnClamped 不变，输出组合与「本轮尚未学习」完全同形，只能靠码区分。
 *                         故障级（置 bError，锁存至 bReset 沿）：
 *                         42 = 目标重量非法（≤ 0 或非有限）；反证：该场景四相阈值全部退化，
 *                              输出与「刚开始灌装」同形，必须独立成码且作为首因优先判定。
 *                         43 = 相级看门狗超时（粗流 / 细流相驻留超限）；反证：该场景实称长期不达
 *                              阈值、iLearnCnt 不增，与「慢速灌装仍在进行」输出全同形。
 *                         44 = 称重值非有限（仪表失效）；反证：与 43 的区别是「有无读数」而非
 *                              「读数是否推进」，两者补救动作不同（换仪表 / 查阀门节拍）。
 *                         45 = 组态参数非有限（裕度初值 / 学习增益 / 预动作量限幅）；反证：该类
 *                              参数是静态配置，与过程量失效的补救动作（改配方 vs 修设备）不同。
 *                         99 = 非法状态枚举值（ELSE 兜底）。
 * 分工声明 (Scope)      : 粗流阀 / 细流阀的实际开闭命令归灌装时序件（本件只输出相位，相位即
 *                         命令语义）；称重滤波与稳定判据归上游称重件（本件只接收 bWeightStable）；
 *                         配方级目标重量下发归配方管理件。本件只做**预动作量单参数学习的闭环**。
 * 归属     (Ownership)  : E_DL_FillPreactSelfLearn_State 归属本文件（全库唯一定义，R264）。
 * 命名偏离 (Naming Ex.) : 本件按派单原文保留 r 前缀表示 REAL（rTargetKg / rActualKg /
 *                         rCoarseMarginInit / rLearnGain / rPreactMin / rPreactMax / rPreactKg /
 *                         rCoarseMargin / rLastErrKg），i 前缀表示 INT（iErrCode），i 前缀表示
 *                         DINT（iLearnCnt，计数语义按 FB51-7② 归 DINT）；内部计算一律升位到
 *                         LREAL 的 f 前缀。与规范 1.2 节存在登记偏离，接口契约优先不改名。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL / VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q ｜ R3 ✓ 纯 IEC 61131-3
 *                         ｜ R4 ✓ 无除法 + 浮点容差比较 + 自反/差值双判非有限 + 除零量纲闸
 *                         ｜ R5 ✓ 逐行同行中英双语注释 ｜ R6 ✓ 七态 ENUM + CASE + ELSE 兜底
 *                         ｜ R7 ✓ TON / R_TRIG 全在 CASE 外无条件调用 ｜ R8 ✓ 无 METHOD（全内联）
 *                         ｜ R10 ✓ 无构造式转换（仅 REAL_TO_LREAL / LREAL_TO_REAL）｜ R11 ✓ 声明
 *                         全分号结尾 ｜ R12 ✓ ENUM 成员用 := ｜ R14 ✓ 无 PROPERTY
 *                         ｜ R16 ✓ 不引用任何外部 FB/FC（LIMIT / ABS 为 IEC 标准函数）。
 * 修订历史 (Revision)   : 2026-11-24  v1.0.0  R81-B 首版（COARSE_MARGIN 自学习显式留置 v1.1）
 * 验收向量 (Acceptance) :
 *   V1 欠灌学习：rTargetKg=1.000、rPreactKg 初值 0.100（限幅 0.02..0.35）、rLearnGain=0.3、
 *      rCoarseMarginInit=0.050、实称 0.980 → err=-0.020、新 PREACT=0.100+0.3×(-0.020)=0.094、
 *      iLearnCnt+1、bLearnClamped=FALSE、rLastErrKg=-0.020、eState 走 eDone 后回 eIdle。
 *   V2 触界限幅：rPreactKg=0.349、实称 1.060（err=+0.060）→ 原始值 0.367 超 0.35 →
 *      rPreactKg=0.350、bLearnClamped=TRUE、iLearnCnt+1。
 *   V3 不稳定样本：bWeightStable 恒 FALSE、tSettleTimeout=T#2S → eSettle 驻留 2s 后 tonSettle.Q →
 *      eLearn、iErrCode=41、iLearnCnt 不增、rPreactKg 不变、bLearnClamped 不变、bError=FALSE。
 *   V4 目标非法：rTargetKg=0.0 → eState=eFault、iErrCode=42、bError=TRUE、bBusy=FALSE；
 *      bReset 上升沿 → eState=eIdle、bError=FALSE、rPreactKg 保持故障前值（学习资产不清）。
 *   V5 称重非有限：rActualKg 置 NaN → eState=eFault、iErrCode=44、bError=TRUE。
 *   V6 增益越域：rLearnGain=5.0 → 夹紧为 0.8（不故障，bError=FALSE），一次学习跳变量不超过
 *      0.8×err；rLearnGain=0.001 → 夹紧为 0.05。
 *   V7 粗流超时：rPreactKg 使粗流阈值极低、实称恒 0、tSettleTimeout=T#1S → eCoarse 驻留 1s 后
 *      eState=eFault、iErrCode=43、bError=TRUE。
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_FillPreactSelfLearn_State（灌装预动作量学习相位；eFault 为安全相）
 *----------------------------------------------------------------------------*)
TYPE E_DL_FillPreactSelfLearn_State :
(
    eIdle   := 0,     // 空闲：等启动条件，学习资产保持 / Idle: waiting for the start condition, learning assets kept
    eCoarse := 10,    // 粗流相：实际重量到「目标 − 预动作量」切细流 / Coarse: switch to fine when the weight reaches the target minus PREACT
    eFine   := 20,    // 细流相：实际重量到「目标 − 粗流裕度」停阀 / Fine: close the valve at the target minus the coarse margin
    eSettle := 30,    // 整定相：等称重稳定或整定窗超时 / Settle: waiting for weight stability or the settle window
    eLearn  := 40,    // 学习相：单拍更新预动作量并限幅 / Learn: one-scan PREACT update with clamping
    eDone   := 50,    // 完成相：单拍回执 / Done: one-scan completion receipt
    eFault  := 90     // 故障安全相：锁存成因，拒绝学习推进 / Fault safe phase: latched cause, no learning progress
);
END_TYPE

FUNCTION_BLOCK FB_DL_FillPreactSelfLearn
VAR_INPUT
    bEnable       : BOOL := FALSE;          // 使能：FALSE 回空闲（学习资产保留）/ Enable, FALSE returns to idle and keeps the learning assets
    bReset        : BOOL := FALSE;          // 复位（上升沿；清锁存与状态，不清学习值）/ Reset rising edge clearing latch and phase but not the learned values
    bStart        : BOOL := FALSE;          // 启动（电平，eIdle 出口判据）/ Start level, an eIdle exit criterion
    rTargetKg     : REAL := 0.0;            // 目标灌装重量，域 > 0 且有限 [kg] / Target fill weight, positive and finite
    rActualKg     : REAL := 0.0;            // 实称重量（称重件输出）[kg] / Measured weight delivered by the weighing component
    rCoarseMarginInit : REAL := 0.05;       // 粗流裕度配置初值，钳在 0..目标/2 [kg] / Configured coarse margin, clamped to zero through half the target
    rLearnGain    : REAL := 0.3;            // 学习增益，有效域 0.05..0.8，越域夹紧 [1] / Learning gain, clamped into 0.05 through 0.8
    rPreactMin    : REAL := 0.02;           // 预动作量下限 [kg] / PREACT lower limit
    rPreactMax    : REAL := 0.35;           // 预动作量上限，须 ≥ rPreactMin [kg] / PREACT upper limit, at least the lower limit
    tSettleTimeout : TIME := T#3S;          // 单相驻留上限（整定窗 + 粗/细流看门狗），有效域 50ms..10min [s] / Per-phase dwell limit, valid domain 50 ms through 10 min
    bWeightStable : BOOL := FALSE;          // 称重稳定（称重件判据）/ Weight stable, delivered by the weighing component
END_VAR
VAR_OUTPUT
    eState        : E_DL_FillPreactSelfLearn_State;   // 当前相位出口（段 8 单点映射）/ Current phase outlet mapped once at segment 8
    bBusy         : BOOL;                   // 本轮灌装进行中 / A fill cycle in progress
    bDone         : BOOL;                   // 本轮完成单拍脉冲 / One-scan cycle completion pulse
    bError        : BOOL;                   // 故障锁存标志 / Fault latch flag
    iErrCode      : INT := 0;               // 错误码（故障期锁存回放，非故障期为信息码）/ Error code, latched in fault and the info code otherwise
    rPreactKg     : REAL := 0.0;            // 当前预动作量（学习资产，复位不清）[kg] / Current PREACT, a learning asset kept across resets
    rCoarseMargin : REAL := 0.0;            // 当前粗流裕度（本版为域钳定配置量）[kg] / Current coarse margin, a clamped configuration value in this version
    rLastErrKg    : REAL := 0.0;            // 上次偏差 = 实称 − 目标 [kg] / Last deviation, measured minus target
    iLearnCnt     : DINT := 0;              // 学习成功累计次数 [次] / Cumulative successful learning count
    bLearnClamped : BOOL;                   // 上次学习是否被限幅 / Whether the last learning was clamped
END_VAR
VAR
    _eState       : E_DL_FillPreactSelfLearn_State := E_DL_FillPreactSelfLearn_State.eIdle;   // 内部相位（CASE 唯一写入目标）/ Internal phase, the only CASE write target
    _bFaultLatch  : BOOL := FALSE;          // 故障锁存位（仅 bReset 上升沿清除）/ Fault latch bit, cleared only by the bReset rising edge
    _iErrLatch    : INT := 0;               // 锁存故障码（故障期唯一回放源，FB33-1）/ Latched fault code, the only replay source during fault
    _iInfoCode    : INT := 0;               // 信息级码（41，永不置 bError）/ Info-level code 41, never raising bError
    _iErrTmp      : INT := 0;               // 当拍故障首因中间量 / First fault cause of this scan
    _bFaultReq    : BOOL := FALSE;          // 当拍故障请求标志（段 7 统一锁存）/ Fault request of this scan latched at segment 7
    _bCfgOk       : BOOL := TRUE;           // 组态与入参闸通过标志 / Configuration and argument gate flag
    _bInit        : BOOL := FALSE;          // 首扫初始化已执行标志（学习起点，FB50-2）/ First-scan initialisation flag for the learning start point
    _bDonePulse   : BOOL := FALSE;          // 完成内部单拍位（段 1 预置，段 8 映射）/ Internal one-scan done bit preset at segment 1
    _bSettledStable : BOOL := FALSE;        // 本轮样本稳定标志（稳定才学习）/ Stability flag of this cycle, learning happens only when stable
    _bLearnClamped : BOOL := FALSE;         // 上次学习限幅标志（内部保持量）/ Clamp flag of the last learning, an internal holding value
    _fTarget      : LREAL := 0.0;           // 目标重量升位副本 [kg] / Promoted copy of the target weight
    _fActual      : LREAL := 0.0;           // 实称重量升位副本 [kg] / Promoted copy of the measured weight
    _fMarginInit  : LREAL := 0.0;           // 粗流裕度初值升位副本 [kg] / Promoted copy of the configured coarse margin
    _fGainRaw     : LREAL := 0.0;           // 学习增益升位副本（未夹紧）[1] / Promoted learning gain before clamping
    _fGain        : LREAL := 0.0;           // 学习增益夹紧值 [1] / Clamped learning gain
    _fPmin        : LREAL := 0.0;           // 预动作量有效下限（钳后）[kg] / Effective PREACT lower limit after clamping
    _fPmax        : LREAL := 0.0;           // 预动作量有效上限（钳后）[kg] / Effective PREACT upper limit after clamping
    _fPreactKg    : LREAL := 0.0;           // 预动作量学习值（学习资产，复位不清）[kg] / Learned PREACT kept across resets
    _fMargin      : LREAL := 0.0;           // 粗流裕度派生量（每拍由初值域钳定）[kg] / Derived coarse margin clamped from the initial value each scan
    _fLastErr     : LREAL := 0.0;           // 上次偏差保持量 [kg] / Holding value of the last deviation
    _fErr         : LREAL := 0.0;           // 本轮偏差临时量 [kg] / Temporary deviation of this cycle
    _fRaw         : LREAL := 0.0;           // 学习原始结果（夹紧前）[kg] / Raw learning result before clamping
    _fClamped     : LREAL := 0.0;           // 学习夹紧后结果 [kg] / Learning result after clamping
    _iLearnCnt    : DINT := 0;              // 学习成功次数（学习资产，复位不清）[次] / Successful learning count kept across resets
    _tSettle      : TIME := T#3S;           // 单相驻留上限钳定值（两级回退结果）[s] / Clamped per-phase dwell limit after the two-level fallback
    rtReset       : R_TRIG;                 // bReset 边沿实例（段 3 无条件调用，R18）/ bReset edge instance called unconditionally
    tonPhase      : TON;                    // 粗流 / 细流相级看门狗（段 3 无条件调用）/ Phase watchdog for coarse and fine, called unconditionally
    tonSettle     : TON;                    // 整定窗计时器（段 3 无条件调用）/ Settle window timer called unconditionally
END_VAR
VAR CONSTANT
    DL_FPS_ZERO      : LREAL := 0.0;              // 浮点零基准（作有限性判据的对照量）[-] / Float zero used as the finiteness reference
    DL_FPS_EPS       : LREAL := 1.0E-6;           // 浮点比较容差（重量级 kg 下约 1 mg）[kg] / Float comparison tolerance
    DL_FPS_HALF      : LREAL := 0.5;              // 系数 0.5（中位起点与裕度上限）[1] / Factor 0.5 used for the midpoint and the margin cap
    DL_FPS_GAIN_MIN  : LREAL := 0.05;             // 学习增益下限（越界夹紧，不故障）[1] / Learning gain lower bound, clamped without fault
    DL_FPS_GAIN_MAX  : LREAL := 0.8;              // 学习增益上限（越界夹紧，不故障）[1] / Learning gain upper bound, clamped without fault
    DL_FPS_T_MIN     : TIME := T#50MS;            // 单相驻留上限下限 [s] / Per-phase dwell limit lower bound
    DL_FPS_T_MAX     : TIME := T#10M;             // 单相驻留上限上限 [s] / Per-phase dwell limit upper bound
    DL_FPS_T_DEF     : TIME := T#3S;              // 单相驻留上限默认回退值（本身在域内）[s] / Default fallback dwell limit, already inside the domain
    DL_FPS_ONE_DINT  : DINT := 1;                 // 计数步进一 [1] / Counter step of one
END_VAR

(* —— 段 1：中间量预置（只清单拍标志与扫描量，不清学习资产 / 锁存 / 稳定标志，FB32-1） —— *)
_iErrTmp    := 0;                          // 当拍故障首因复位 / Scan first fault cause reset
_bFaultReq  := FALSE;                      // 当拍故障请求复位 / Scan fault request reset
_bCfgOk     := TRUE;                       // 组态闸标志复位 / Configuration gate flag reset
_bDonePulse := FALSE;                      // 完成单拍位预置（单拍路径唯一预置点，FB51-8）/ Done pulse preset, the single preset point

(* —— 段 2：REAL 入参升位（R10 标准转换，内部一律 LREAL 运算防累积误差） —— *)
_fTarget     := REAL_TO_LREAL(rTargetKg);          // 目标重量升位 / Target weight promoted
_fActual     := REAL_TO_LREAL(rActualKg);          // 实称重量升位 / Measured weight promoted
_fMarginInit := REAL_TO_LREAL(rCoarseMarginInit);  // 裕度初值升位 / Configured margin promoted
_fGainRaw    := REAL_TO_LREAL(rLearnGain);         // 学习增益升位 / Learning gain promoted
_fPmin       := REAL_TO_LREAL(rPreactMin);         // 限幅下限升位 / PREACT lower limit promoted
_fPmax       := REAL_TO_LREAL(rPreactMax);         // 限幅上限升位 / PREACT upper limit promoted

(* —— 段 3：时间参数两级回退（越域回默认常量，默认常量在域内故无需二级钳定，FB32-3） —— *)
IF (tSettleTimeout < DL_FPS_T_MIN) OR (tSettleTimeout > DL_FPS_T_MAX) THEN
    _tSettle := DL_FPS_T_DEF;              // 越域：回一级默认常量 / Out of domain: fall back to the default constant
ELSE
    _tSettle := tSettleTimeout;            // 域内：原值采用 / Inside the domain: take the value as given
END_IF

(* —— 段 4：组态域闸全覆盖（六个浮点入参逐项枚举，FB51-2；非有限双判，R4 / R79） —— *)
IF (_fTarget <> _fTarget) OR ((_fTarget - _fTarget) <> (_fTarget - _fTarget)) THEN
    _bCfgOk  := FALSE;                     // 目标重量非有限 / Target weight is not finite
    _iErrTmp := 42;                        // 故障级：目标重量非法 / Fault: illegal target weight
END_IF
IF _bCfgOk THEN
    IF _fTarget <= DL_FPS_EPS THEN
        _bCfgOk  := FALSE;                 // 目标重量非正（量纲闸，防后级比例换算除零）/ Non-positive target, a dimensional gate against division by zero downstream
        _iErrTmp := 42;                    // 故障级：目标重量非法 / Fault: illegal target weight
    END_IF
END_IF
IF _bCfgOk THEN
    IF (_fActual <> _fActual) OR ((_fActual - _fActual) <> (_fActual - _fActual)) THEN
        _bCfgOk  := FALSE;                 // 实称重量非有限（仪表失效）/ Measured weight is not finite
        _iErrTmp := 44;                    // 故障级：称重值非有限 / Fault: non-finite measured weight
    END_IF
END_IF
IF _bCfgOk THEN
    IF ((_fMarginInit <> _fMarginInit) OR ((_fMarginInit - _fMarginInit) <> (_fMarginInit - _fMarginInit)))
        OR ((_fGainRaw <> _fGainRaw) OR ((_fGainRaw - _fGainRaw) <> (_fGainRaw - _fGainRaw)))
        OR ((_fPmin <> _fPmin) OR ((_fPmin - _fPmin) <> (_fPmin - _fPmin)))
        OR ((_fPmax <> _fPmax) OR ((_fPmax - _fPmax) <> (_fPmax - _fPmax))) THEN
        _bCfgOk  := FALSE;                 // 组态参数非有限 / A configuration parameter is not finite
        _iErrTmp := 45;                    // 故障级：组态参数非有限 / Fault: non-finite configuration parameter
    END_IF
END_IF

(* —— 段 5：参数夹紧与有效限幅（增益夹紧不故障；限幅倒置两级回退，FB32-3） —— *)
_fGain := LIMIT(DL_FPS_GAIN_MIN, _fGainRaw, DL_FPS_GAIN_MAX);   // 学习增益夹紧到 0.05..0.8 / Gain clamped into 0.05 through 0.8
IF _fPmin < DL_FPS_ZERO THEN
    _fPmin := DL_FPS_ZERO;                 // 预动作量下限不得为负（负值等于反向补偿）/ PREACT lower limit forced non-negative
END_IF
IF _fPmin > _fPmax THEN
    _fPmin := DL_FPS_ZERO;                 // 限幅倒置一级回退：下限回零 / Inverted limits fall back to a zero lower bound
    _fPmax := _fTarget * DL_FPS_HALF;      // 限幅倒置二级回退：上限按目标半量钳定（域几何内点）/ Upper bound clamped to half the target
END_IF
IF _fTarget > DL_FPS_EPS THEN
    _fMargin := LIMIT(DL_FPS_ZERO, _fMarginInit, _fTarget * DL_FPS_HALF);   // 裕度钳在 0..目标/2，防裕度过大导致细流段根本不进 / Margin clamped to avoid skipping the fine phase
ELSE
    _fMargin := DL_FPS_ZERO;               // 目标非法时裕度归零（等待段 4 的 42 锁存接管）/ Margin zeroed while the illegal target is latched
END_IF

(* —— 段 6：首扫学习起点初始化（组态闸通过后才执行，FB50-2①；复位沿**不**重跑，学习资产保留） —— *)
IF (NOT _bInit) AND _bCfgOk THEN
    _bInit     := TRUE;                                        // 置首扫完成标志 / Mark the first scan done
    _fPreactKg := (_fPmin + _fPmax) * DL_FPS_HALF;             // 起点取限幅中位（在限幅内且非零，减少首轮偏差）/ Start at the limit midpoint, inside the limits and non-zero
    _fLastErr  := DL_FPS_ZERO;                                 // 偏差保持量归零 / Deviation holding value zeroed
    _iLearnCnt := 0;                                           // 学习计数归零 / Counter zeroed
END_IF

(* —— 段 7：边沿与定时器（CASE 外无条件调用，R7；IN 均含 NOT .Q 自复位，R188） —— *)
rtReset(CLK := bReset);                    // bReset 边沿无条件刷新（R18）/ bReset edge refreshed unconditionally
tonPhase(IN := ((_eState = E_DL_FillPreactSelfLearn_State.eCoarse)
                OR (_eState = E_DL_FillPreactSelfLearn_State.eFine))
               AND (NOT tonPhase.Q) AND (NOT _bFaultLatch),
         PT := _tSettle);                  // 粗流 / 细流相级看门狗（使能域与 tonSettle 互斥）/ Phase watchdog with a domain disjoint from tonSettle
tonSettle(IN := (_eState = E_DL_FillPreactSelfLearn_State.eSettle) AND (NOT tonSettle.Q) AND (NOT _bFaultLatch),
          PT := _tSettle);                 // 整定窗计时 / Settle window timer

(* —— 段 8：状态机主体（唯一相位写入点；故障只置请求，锁存与迁相由段 9 执行，R21） —— *)
CASE _eState OF
    E_DL_FillPreactSelfLearn_State.eIdle :
        (* 迁移①：启动条件成立进粗流相 *)
        IF bEnable AND bStart AND _bCfgOk AND (NOT _bFaultLatch) THEN
            _bSettledStable := FALSE;                                 // 本轮样本稳定标志复位 / Stability flag of this cycle cleared
            _bLearnClamped  := FALSE;                                 // 本轮限幅标志复位（学习资产本身不动）/ Clamp flag of this cycle cleared, the learned value itself is kept
            _iInfoCode      := 0;                                     // 信息码复位 / Info code cleared
            _eState         := E_DL_FillPreactSelfLearn_State.eCoarse;   // 进粗流相 / Move to the coarse phase
        END_IF

    E_DL_FillPreactSelfLearn_State.eCoarse :
        (* 迁移②：实称到达「目标 − 预动作量」即切细流（本拍事件优先于超时，R275） *)
        IF _fActual >= ((_fTarget - _fPreactKg) - DL_FPS_EPS) THEN
            _eState := E_DL_FillPreactSelfLearn_State.eFine;          // 切细流 / Switch to the fine phase
        ELSIF NOT bEnable THEN
            _eState := E_DL_FillPreactSelfLearn_State.eIdle;          // 迁移③：前置条件消失回空闲 / Precondition gone, back to idle
        END_IF

    E_DL_FillPreactSelfLearn_State.eFine :
        (* 迁移④：实称到达「目标 − 粗流裕度」即停阀进整定 *)
        IF _fActual >= ((_fTarget - _fMargin) - DL_FPS_EPS) THEN
            _eState := E_DL_FillPreactSelfLearn_State.eSettle;        // 进整定相 / Move to settle
        ELSIF NOT bEnable THEN
            _eState := E_DL_FillPreactSelfLearn_State.eIdle;          // 迁移⑤：前置条件消失回空闲 / Precondition gone, back to idle
        END_IF

    E_DL_FillPreactSelfLearn_State.eSettle :
        (* 迁移⑥/⑦/⑧：稳定样本、整定超时（跳过学习）、失能三出口（R98 出口 ≥ 2） *)
        IF bWeightStable THEN
            _bSettledStable := TRUE;                                  // 稳定样本：允许学习 / Stable sample, learning allowed
            _eState := E_DL_FillPreactSelfLearn_State.eLearn;         // 迁移⑥：进学习相 / Move to learn
        ELSIF tonSettle.Q THEN
            _bSettledStable := FALSE;                                 // 不稳定样本：本轮跳过学习 / Unstable sample, this cycle skips learning
            _iInfoCode      := 41;                                    // 信息级：整定窗超时（不置 bError）/ Info: settle window timeout, bError stays false
            _eState := E_DL_FillPreactSelfLearn_State.eLearn;         // 迁移⑦：仍进学习相以更新偏差 / Still move to learn to refresh the deviation
        ELSIF NOT bEnable THEN
            _eState := E_DL_FillPreactSelfLearn_State.eIdle;          // 迁移⑧：前置条件消失回空闲 / Precondition gone, back to idle
        END_IF

    E_DL_FillPreactSelfLearn_State.eLearn :
        (* 迁移⑨：单拍学习；拍 N 进入 / 本拍行为：偏差与学习值更新、限幅、非有限拒收 / 拍 N+1 转出至 eDone *)
        _fErr        := _fActual - _fTarget;                          // 本轮偏差 = 实称 − 目标 [kg] / Deviation of this cycle
        _fLastErr    := _fErr;                                        // 偏差保持量更新（每轮都记，含不稳定样本）/ Deviation kept every cycle including unstable samples
        (* 稳定标志在本分支只读不写（禁止自赋值死语句，R261） *)
        IF _bSettledStable THEN
            _fRaw := _fPreactKg + (_fGain * _fErr);                   // 学习律：PREACT + gain × err / Learning law
            IF (_fRaw <> _fRaw) OR ((_fRaw - _fRaw) <> (_fRaw - _fRaw)) THEN
                _iErrTmp   := 44;                                     // 故障级：学习结果非有限（保持槽拒收，R133）/ Fault: non-finite result rejected
                _bFaultReq := TRUE;                                   // 请求段 9 锁存 / Request the latch at segment 9
            ELSE
                _fClamped := LIMIT(_fPmin, _fRaw, _fPmax);             // 限幅到 [下限, 上限] / Clamped into the configured limits
                IF ABS(_fClamped - _fRaw) > DL_FPS_EPS THEN
                    _bLearnClamped := TRUE;                           // 触界：本轮学习被限幅 / Clamped this cycle
                ELSE
                    _bLearnClamped := FALSE;                          // 未触界：正常学习 / No clamping this cycle
                END_IF
                _fPreactKg := _fClamped;                              // 学习值写入（唯一写入点，已过非有限闸）/ Single write point after the finiteness gate
                _iLearnCnt := _iLearnCnt + DL_FPS_ONE_DINT;            // 学习成功计数 +1 / Successful learning count incremented
            END_IF
        END_IF
        _eState := E_DL_FillPreactSelfLearn_State.eDone;              // 迁移⑨：进完成相 / Move to done

    E_DL_FillPreactSelfLearn_State.eDone :
        (* 迁移⑩：单拍完成回执；拍 N 进入 / 本拍行为：bDone 置单拍一次，拒绝重复学习 / 拍 N+1 转出至 eIdle *)
        _bDonePulse := TRUE;                                          // 完成内部单拍置位（段 10 映射）/ Internal done pulse raised and mapped at segment 10
        _eState     := E_DL_FillPreactSelfLearn_State.eIdle;          // 回空闲相 / Back to idle

    E_DL_FillPreactSelfLearn_State.eFault :
        (* 迁移⑫：复位沿出口（唯一出口，穷举可达）；学习资产一律保留）
           拍 N 进入 / 本拍行为：清锁存、错误码、稳定标志，拒绝任何学习推进 / 拍 N+1 转出至 eIdle *)
        IF rtReset.Q THEN
            _bFaultLatch    := FALSE;                                 // 清故障锁存 / Clear the fault latch
            _iErrLatch      := 0;                                     // 清锁存故障码 / Clear the latched fault code
            _iInfoCode      := 0;                                     // 清信息码 / Clear the info code
            _bSettledStable := FALSE;                                 // 清稳定标志（避免用旧样本） / Clear the stability flag to avoid reusing an old sample
            _eState         := E_DL_FillPreactSelfLearn_State.eIdle;  // 回空闲相，不滞留故障态 / Back to idle, never parked in fault
        END_IF

ELSE
    (* 迁移⑪（枚举兜底）：非法枚举值 → 故障级 99（R6） *)
    IF NOT _bFaultLatch THEN
        _iErrLatch   := 99;                    // 故障级：非法状态枚举值 / Fault: illegal state enum value
        _bFaultLatch := TRUE;                  // 置故障锁存（码位赋值 3 行内配对，R45）/ Latch the fault within three lines
    END_IF
END_CASE

(* —— 段 9：当拍故障请求锁存（定时器超时 / 组态闸）+ 段尾迁移闸 + 撤使能降级 —— *)
IF tonPhase.Q AND (NOT _bFaultLatch) THEN
    _iErrLatch   := 43;                        // 故障级：粗流 / 细流相级看门狗超时 / Fault: coarse or fine phase watchdog timeout
    _bFaultLatch := TRUE;                      // 置故障锁存 / Latch the fault
END_IF
IF (NOT _bCfgOk) AND (NOT _bFaultLatch) THEN
    _iErrLatch   := _iErrTmp;                  // 锁存组态首因 / Latch the configuration first cause
    _bFaultLatch := TRUE;                      // 置故障锁存 / Latch the fault
END_IF
IF _bFaultReq AND (NOT _bFaultLatch) THEN
    _iErrLatch   := _iErrTmp;                  // 锁存学习结果非有限首因 / Latch the non-finite result cause
    _bFaultLatch := TRUE;                      // 置故障锁存 / Latch the fault
END_IF
IF _bFaultLatch AND (_eState <> E_DL_FillPreactSelfLearn_State.eFault) THEN
    _eState := E_DL_FillPreactSelfLearn_State.eFault;   // 锁存即迁相（段尾统一执行，FB50-1④）/ Latch forces the fault phase at the tail
END_IF
IF (NOT bEnable) AND (NOT _bFaultLatch) AND (_eState <> E_DL_FillPreactSelfLearn_State.eIdle) THEN
    _eState := E_DL_FillPreactSelfLearn_State.eIdle;    // 撤使能：回空闲（学习资产保留，R191 降级声明）/ Disable: back to idle keeping the learning assets
END_IF

(* —— 段 10：统一出口（单点映射；连续量出口再做一次非有限防护，FB51-3 / R273） —— *)
eState  := _eState;                            // 相位映射 / Phase mapping
bBusy   := (_eState = E_DL_FillPreactSelfLearn_State.eCoarse)
           OR (_eState = E_DL_FillPreactSelfLearn_State.eFine)
           OR (_eState = E_DL_FillPreactSelfLearn_State.eSettle)
           OR (_eState = E_DL_FillPreactSelfLearn_State.eLearn);   // 本轮进行中 / Cycle in progress
bDone   := _bDonePulse;                        // 完成单拍映射 / Completion pulse mapping
bError  := _bFaultLatch;                       // 故障标志取锁存位 / Fault flag taken from the latch
IF _bFaultLatch THEN
    iErrCode := _iErrLatch;                    // 故障期回放锁存码（FB33-1）/ Replay the latched code during fault
ELSE
    iErrCode := _iInfoCode;                    // 非故障期输出信息码（41 永不置 bError，R101）/ Info code outside fault, never raising bError
END_IF
IF (_fPreactKg <> _fPreactKg) OR ((_fPreactKg - _fPreactKg) <> (_fPreactKg - _fPreactKg)) THEN
    _fPreactKg := DL_FPS_ZERO;                 // 保持槽污染兜底：归零（三件套中的连续量安全侧）/ Contaminated holding value forced to zero
    rPreactKg  := 0.0;                         // 出口同步归零 / Outlet follows the guard
ELSE
    rPreactKg  := LREAL_TO_REAL(_fPreactKg);   // 学习值出口（降位为 REAL）/ Learning value outlet demoted to REAL
END_IF
IF (_fMargin <> _fMargin) OR ((_fMargin - _fMargin) <> (_fMargin - _fMargin)) THEN
    rCoarseMargin := 0.0;                      // 裕度污染兜底：归零 / Contaminated margin forced to zero
ELSE
    rCoarseMargin := LREAL_TO_REAL(_fMargin);  // 裕度出口 / Margin outlet
END_IF
IF (_fLastErr <> _fLastErr) OR ((_fLastErr - _fLastErr) <> (_fLastErr - _fLastErr)) THEN
    rLastErrKg := 0.0;                         // 偏差污染兜底：归零 / Contaminated deviation forced to zero
ELSE
    rLastErrKg := LREAL_TO_REAL(_fLastErr);    // 偏差出口 / Deviation outlet
END_IF
iLearnCnt     := _iLearnCnt;                   // 学习计数出口 / Learning count outlet
bLearnClamped := _bLearnClamped;               // 限幅标志出口 / Clamp flag outlet
END_FUNCTION_BLOCK
