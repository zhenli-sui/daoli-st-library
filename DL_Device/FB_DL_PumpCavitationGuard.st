(*==============================================================================
 * 组件名称 (Component)  : FB_DL_PumpCavitationGuard
 * 所属子库 (Sublibrary) : DL_Device
 * 当前版本 (Version)    : 1.0.1
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Schneider
 *                         Machine Expert；纯 IEC 61131-3（第 3 版）语法，
 *                         仅依赖 Standard.library（R_TRIG / TON）
 * 组件分类 (Category)   : 功能块（FUNCTION_BLOCK）· 设备本体退化诊断 · 泵汽蚀
 * 功能描述 (Function)   : 泵汽蚀的在线判据与**降速请求**。三判据并发：
 *                         (a) 流量偏低（低于额定的比例）；(b) 扬程跌落（低于额定的
 *                         跌幅）；(c) 振动超限**或**电流波动超限。三者同拍成立并
 *                         持续 tConfirm 才升级为锁存故障；单条成立只到「嫌疑」。
 * 降速语义 (Derate)     : 本件**不直接给变频器频率**，只输出 `fDerateRatio`
 *                         （1.0 = 不降）与 `bDerateRequest`。执行归上层
 *                         `FB_DL_RateLimiter` / `FB_DL_VfdGeneric`——诊断件一旦
 *                         自己写频率，就会与工艺主控的速率限制打架，且无法在
 *                         不同变频器之间移植。
 *                         每次确认汽蚀事件比率递减一步（下限 0.3），**只减不自动
 *                         增**：回升由上层斜坡完成，避免本件与上层同时调节同
 *                         一个量（双写冲突）。
 * 边界声明 (Limits)     : ① **不做 NPSH 计算**：需介质饱和蒸汽压与吸入侧压力，
 *                         属选型设计而非在线判据；② 振动阈值默认取 ISO 10816
 *                         C 区边界 4.5 mm/s（**公知阈值，引脚可改**），头注释
 *                         注明出处与「仅参考」定位；③ 本件**不声称**符合
 *                         ISO 10816 认证，阈值只是工程默认值；④ 停泵（bRunning
 *                         为 FALSE）时全部判据抑制，不产生任何降速请求。
 * 段序 (Cycle order)   : 段 1 默认值与单拍预清零 → 段 2 首扫初始化 →
 *                         段 3 参数闸门与输入域检查 → 段 4 定时器与边沿无条件刷新 →
 *                         段 5 判据计算 → 段 6 复位通道与故障锁存（**CASE 前置，
 *                         不做状态变量赋值**）→ 段 7 监视相位机 → 段 8 降速执行与
 *                         事件锁存 → 段 9 健康仲裁、出口钳位与保持重写 → 段 10 码位链。
 * 拍间依赖 (Cycle dep)  : 确认定时器在段 4 调用，而其 IN 里的「三判据同拍」在段 5
 *                         才算出，故定时器读到的是**上一拍照**的判据值（一拍滞后）。
 *                         对 3 秒量级的确认判据无实质影响，换来的是「所有定时器
 *                         实例都在同一段无条件调用」这一更强的纪律；此处显式登记，
 *                         避免后人误以为是笔误。
 * 定时器清单 (R40)      : 实例名 / IN 表达式 / 断输入拍标志 / 自清位置
 *                         fbConfirmWatch / 三判据同拍 AND 状态为嫌疑 AND
 *                                        NOT _bConfirmBreak / _bConfirmBreak
 *                                        （进/出嫌疑态与复位时置位）
 *                         fbRippleWatch  / 泵运行 AND NOT _bRippleBreak
 *                                        / _bRippleBreak（窗满后置位重启）
 *                         fbHoldOffWatch / 状态为降速 AND NOT _bHoldBreak
 *                                        / _bHoldBreak（进/出降速态置位）
 *                         三个实例全部在段 4 无条件调用，断输入拍一律在调用后自清。
 * 单拍标志清单 (R25)    : `_bResetPulse` 预清段 1 / 置位段 6 / 消费段 6；
 *                         `_bDerateStep`（降速单拍）预清段 1 / 置位段 8 / 消费段 8；
 *                         `_bConfirmEvent` 预清段 1 / 置位段 7 / 消费段 8；
 *                         三个断输入标志就地置位、段 4 调用后自清。
 * 保持位清单 (R27)      : `bDerateRequest` 与 `fDerateRatio`、`bCavitation`、
 *                         `nEventCount` 四个保持量，全部由段 9 每拍重写出口；
 *                         降速请求在 eDerate 与抑制窗内**保持为 TRUE**，不靠
 *                         进入那一拍的脉冲（R27 的典型场景）。
 * 三元一致表 (R35)      : 量 / 守卫封顶 / 判据运算符
 *                         fFlowLowRatio   / 钳到 0.2~0.95 / 判据用 <
 *                         fHeadDropRatio  / 钳到 0.05~0.5 / 判据用（1 减比值）>
 *                         fVibLimit       / 钳到 1~20     / 判据用比值 > 1，急停用 > 2
 *                         振动比值输出上限 / 钳到 5.0     / 必须高于急停倍率 2（R35 同向）
 *                         fDerateStep     / 钳到 0.02~0.3 / 递减后与 0.3 取大
 * 验收向量 (Acceptance) :
 *   V1 单判据：流量 0.5 倍额定（其余判据不成立）→ eSuspect + 0164，**不锁存**
 *   V2 三判据：三判据同拍持续 3 s → eConfirm → eDerate、0326、比率每次 −0.10
 *      （下限 0.3）
 *   V3（V-C 跨段 R40）：tConfirm 定时器在 eSuspect 与 eMonitor 来回时必须断输入，
 *      否则三次 1 s 的孤立嫌疑会被误判成「持续 3 s」
 *   V4（V-D 恢复）：bReset 后 fDerateRatio **不得**直接回 1.0（R41），且必须夹进
 *      0.3~1.0（R43）
 *   V5（V-A 域外）：fFlowNominal 为 0 → 0328 锁存，fFlowRatio 输出 0（不输出无穷大）
 * 规格偏离 (Deviation)  :
 *   ① 规格 V1 给的是「流量 0.5 倍额定、扬程 0.8 倍额定、振动 2.0、电流平稳 →
 *      只有流量判据」。按默认 fHeadDropRatio 为 0.15 计算，扬程 0.8 倍额定的跌幅
 *      为 20%，**会同时触发扬程判据**。本件按判据定义实现（跌幅 > 15% 即成立），
 *      复现 V1 需把 fHeadDropRatio 调到 ≥0.25；此处不改判据语义以迁就向量。
 *   ② 规格未给「电流波动率」的确切口径。本件取滑动窗内「(最大 − 最小) ÷ 平均」
 *      作为波动率，窗长 tRippleWindow，窗满即出值并重启窗；该口径与现场常见的
 *      「电流摆动幅度百分比」一致，且不依赖频谱。
 *   ③ 规格要求 bReset 后比率不直接回 1.0。本件在 bReset 且三判据全部消失时让
 *      比率**回升一步**（不直接回 1.0），其余恢复速率仍交上层斜坡；这是「不得
 *      重头恢复」与「不能让比率永久卡死」之间的折中，已在此登记。
 *   ④ 参数非法（额定值非正、阈值倒置）统一用 0328，未分更细码位（本轮未分配）。
 * 开源溯源 (Origin)     : 来源标签 namur-ne107 / lbp-basic-process / pump-diag。
 *                         原创 clean-room 实现。**仅借鉴**：① NAMUR NE107（公开
 *                         推荐规范）的健康分级语义；② LBP（Library of Basic
 *                         Process）公开文档所呈现的「命令—监视—判定」三段式
 *                         分层惯例，作为本件「判据—定级—降速请求」的组织参照。
 *                         汽蚀三判据（流量低 / 扬程跌 / 振动或电流波动）属泵
 *                         行业公开的通行定性认识；ISO 10816 的 4.5 mm/s 为公知
 *                         阈值。本件未复制任何源码行、未沿用其命名体系，窗口
 *                         口径、状态机、宽限与降速规则、全部码位 100% 本库独立
 *                         设计，无许可证传染风险。
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（R13 · 泳道 A · 泵汽蚀判据与降速请求）
 *   2026-11-16  v1.0.1  终审修复五处：① `_bHoldActive` 由「窗满那一拍」改为
 *                       「整个降速相」——原实现下 0165 仅在抑制窗到期瞬间可见、
 *                       判据在窗内并未被真正抑制；② 流量/扬程比值改用**原始
 *                       额定值的域**做门（原实现拿兜底值 1.0 当分母，额定为 0
 *                       时输出的是伪比值而非 0，违 V5）；③ 汽蚀确认补写
 *                       `_uErrFault := 16#0003_0326`（原实现 bError 为真而
 *                       uErrorId 恒 0，违 R21 一致性）；④ 急停级 0327 加
 *                       bRunning/bEnable 门（停泵时邻近设备振动不得拉锁存）；
 *                       ⑤ 停泵清 `_fRipple`，防停泵前旧波动率跨停机存活到
 *                       重启后的首个取样窗。
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_CavitationState（归属本功能块，同文件发布）
 * 含义: 汽蚀监视相位。6 个成员在段 6 各有唯一标签，ELSE 只接脏值。
 *-----------------------------------------------------------------------------*)
TYPE E_DL_CavitationState :
(
    eIdle    := 0,     // 待机：未使能或停泵 / Idle, disabled or the pump is stopped
    eMonitor := 10,    // 监视：泵运行，判据全部不成立 / Monitoring, no criterion active
    eSuspect := 20,    // 嫌疑：单判据成立，未确认 / Suspect, one criterion active
    eConfirm := 30,    // 确认：三判据同拍且持续满足 / Confirm, all three held long enough
    eDerate  := 40,    // 降速：已请求降速，处于抑制窗 / Derate, request held during the hold-off
    eFault   := 99     // 故障：参数非法或振动急停级，锁存 / Fault, latched
);
END_TYPE

FUNCTION_BLOCK FB_DL_PumpCavitationGuard
VAR_INPUT
    bEnable             : BOOL;                      // 使能 [-] / Enable
    bReset              : BOOL;                      // 复位锁存，上升沿有效 [-] / Rising edge resets the latch
    bRunning            : BOOL;                      // 泵运行中，停泵时全部判据抑制 [-] / Pump running, criteria suppressed when stopped
    fFlow               : REAL;                      // 实测流量 [m³/h]，范围 0~100000 / Measured flow
    fHead               : REAL;                      // 实测扬程 [m]，范围 0~1000 / Measured head
    fVibration          : REAL;                      // 振动速度有效值 [mm/s]，范围 0~50 / Vibration RMS velocity
    fCurrent            : REAL;                      // 电机电流 [A]，范围 0~10000 / Motor current
    fFlowNominal        : REAL;                      // 额定流量 [m³/h]，域大于 0 / Nominal flow, must exceed zero
    fHeadNominal        : REAL;                      // 额定扬程 [m]，域大于 0 / Nominal head, must exceed zero
    fFlowLowRatio       : REAL := 0.60;              // 流量低于额定的比例 [-]，范围 0.2~0.95 / Low-flow ratio
    fHeadDropRatio      : REAL := 0.15;              // 扬程跌落比例 [-]，范围 0.05~0.5 / Head-drop ratio
    fVibLimit           : REAL := 4.5;               // 振动上限 [mm/s]，ISO 10816 C 区边界，范围 1~20 / Vibration limit
    fCurrentRippleLimit : REAL := 0.15;              // 电流波动率上限 [-]，范围 0.02~0.5 / Current ripple limit
    tRippleWindow       : TIME := T#2S;              // 电流波动统计窗 [毫秒]，范围 0.5~30 s / Ripple window
    tConfirm            : TIME := T#3S;              // 三判据同拍持续判据 [毫秒]，范围 0.5~30 s / Confirmation time
    tHoldOff            : TIME := T#30S;             // 降速后抑制判据时长 [毫秒]，范围 5 s~10 min / Hold-off after a derate
    fDerateStep         : REAL := 0.10;              // 每次降速步长 [-]，范围 0.02~0.3 / Derate step
END_VAR
VAR_OUTPUT
    eHealth             : E_DL_Ne107Status;          // NE107 健康态（引用自 I_DL_DeviceHealth）[-] / NE107 health
    uDiagCode           : UDINT;                     // 当前诊断码，0=无码 [代码] / Active diagnostic code
    uErrorId            : UDINT;                     // 末次故障码，仅故障级 [代码] / Last fault code
    bError              : BOOL;                      // 故障锁存 [-] / Fault latched
    bCavitation         : BOOL;                      // 汽蚀确认（三判据同拍成立，锁存）[-] / Cavitation confirmed, latched
    bDerateRequest      : BOOL;                      // 降速请求（保持语义）[-] / Derate request, held
    fDerateRatio        : REAL;                      // 降速比例 [-]，范围 0.3~1.0，1.0=不降 / Derate ratio
    fFlowRatio          : REAL;                      // 实测/额定流量比值 [-]，钳 0~2 / Flow ratio
    fHeadRatio          : REAL;                      // 实测/额定扬程比值 [-]，钳 0~2 / Head ratio
    fVibRatio           : REAL;                      // 振动/上限比值 [-] / Vibration ratio
    nEventCount         : UDINT;                     // 汽蚀事件累计 [次]，锁存 / Event counter
    fRippleMeas         : REAL;                      // 窗内电流波动率实测值 [-] / Measured ripple
END_VAR
VAR
    fbTrigReset     : R_TRIG;                        // 复位沿检测，段 4 无条件刷新 [-] / Reset edge detector
    fbConfirmWatch  : TON;                           // 三判据持续计时，段 4 刷新 [毫秒] / Confirmation timer
    fbRippleWatch   : TON;                           // 电流波动统计窗，段 4 刷新 [毫秒] / Ripple window timer
    fbHoldOffWatch  : TON;                           // 降速后抑制窗，段 4 刷新 [毫秒] / Hold-off timer
    _eState         : E_DL_CavitationState := E_DL_CavitationState.eIdle; // 当前相位 [-] / Current phase
    _bInit          : BOOL := FALSE;                 // 首扫标志，初值 FALSE [-] / First-scan flag
    _bFaultLatch    : BOOL;                          // 故障锁存，仅复位清 [-] / Fault latch
    _uErrFault      : UDINT;                         // 首出故障码 [代码] / First-out fault code
    _uDiagCode      : UDINT;                         // 当前诊断码（单一链产出）[代码] / Active diagnostic code
    _bResetPulse    : BOOL;                          // 复位单拍 [-] / One-shot reset
    _bParamBad      : BOOL;                          // 参数非法标志 [-] / Illegal parameter flag
    _bConfirmBreak  : BOOL;                          // 确认定时器断输入一拍 [-] / Confirmation timer break
    _bRippleBreak   : BOOL;                          // 波动窗断输入一拍 [-] / Ripple window break
    _bHoldBreak     : BOOL;                          // 抑制窗断输入一拍 [-] / Hold-off break
    _fFlowNomUse    : REAL := 1.0;                   // 生效额定流量 [m³/h] / Effective nominal flow
    _fHeadNomUse    : REAL := 1.0;                   // 生效额定扬程 [m] / Effective nominal head
    _fFlowLowUse    : REAL := 0.60;                  // 生效流量比例 [-] / Effective low-flow ratio
    _fHeadDropUse   : REAL := 0.15;                  // 生效扬程跌幅 [-] / Effective head-drop ratio
    _fVibUse        : REAL := 4.5;                   // 生效振动上限 [mm/s] / Effective vibration limit
    _fRippleLimUse  : REAL := 0.15;                  // 生效波动率上限 [-] / Effective ripple limit
    _fStepUse       : REAL := 0.10;                  // 生效降速步长 [-] / Effective derate step
    _tRippleUse     : TIME := T#2S;                  // 生效波动窗 [毫秒] / Effective ripple window
    _tConfirmUse    : TIME := T#3S;                  // 生效确认时长 [毫秒] / Effective confirmation time
    _tHoldUse       : TIME := T#30S;                 // 生效抑制窗 [毫秒] / Effective hold-off
    _diMs           : DINT;                          // 时间换算中间量 [毫秒] / Time conversion working value
    _fFlowRatio     : REAL;                          // 流量比值 [-]，钳 0~2 / Flow ratio
    _fHeadRatio     : REAL;                          // 扬程比值 [-]，钳 0~2 / Head ratio
    _fVibRatio      : REAL;                          // 振动比值 [-] / Vibration ratio
    _bCritFlow      : BOOL;                          // 流量判据 [-] / Flow criterion
    _bCritHead      : BOOL;                          // 扬程判据 [-] / Head criterion
    _bCritVib       : BOOL;                          // 振动判据 [-] / Vibration criterion
    _bCritRipple    : BOOL;                          // 电流波动判据 [-] / Ripple criterion
    _bCritVibGroup  : BOOL;                          // 振动或波动（第三判据）[-] / Vibration or ripple, the third criterion
    _bAllThree      : BOOL;                          // 三判据同拍成立 [-] / All three criteria in one scan
    _bAnyCrit       : BOOL;                          // 任一判据成立 [-] / Any criterion active
    _bVibEmergency  : BOOL;                          // 振动超上限两倍（急停级）[-] / Vibration above twice the limit
    _fCurrMin       : REAL;                          // 窗内电流最小值 [A] / Minimum current in the window
    _fCurrMax       : REAL;                          // 窗内电流最大值 [A] / Maximum current in the window
    _fCurrSum       : REAL;                          // 窗内电流累加 [A] / Current sum in the window
    _nCurrCount     : UDINT;                         // 窗内电流样本数 [个] / Current sample count
    _fRipple        : REAL;                          // 窗内波动率实测值 [-] / Measured ripple
    _bHoldActive    : BOOL;                          // 抑制窗生效中 [-] / Hold-off active
    _bDerateStep    : BOOL;                          // 本次确认需降一步 [-] / Step down this scan
    _bConfirmEvent  : BOOL;                          // 本拍确认事件 [-] / Confirmation event this scan
    _bCavLatch      : BOOL;                          // 汽蚀锁存 [-] / Cavitation latch
    _fDerateRatio   : REAL := 1.0;                   // 保持的降速比例 [-] / Held derate ratio
    _bDerateHeld    : BOOL;                          // 保持的降速请求 [-] / Held derate request
    _uEventCount    : UDINT;                         // 保持的事件计数 [次] / Held event counter
    _eHealthInt     : E_DL_Ne107Status := E_DL_Ne107Status.eUnknown; // 健康态内部量 [-] / Internal health state
END_VAR
VAR CONSTANT
    DL_VAL_LIM      : REAL := 1.0E6;                 // 有限性判定绝对值上限 [-] / Finiteness limit
    DL_EPS          : REAL := 1.0E-6;                // 浮点比较容差 [-] / Float comparison tolerance
    DL_RATIO_MAX    : REAL := 2.0;                   // 流量扬程比值上限 [-]，防噪声放大 / Flow and head ratio ceiling
    DL_VIB_RATIO_MAX: REAL := 5.0;                   // 振动比值上限 [-]，须高于急停倍率 2 倍（R35 同向） / Vibration ratio ceiling
    DL_VIB_EMERG    : REAL := 2.0;                   // 振动急停级倍率 [-] / Emergency vibration multiplier
    DL_DERATE_MIN   : REAL := 0.3;                   // 降速比例下限 [-] / Lower derate bound
    DL_DERATE_MAX   : REAL := 1.0;                   // 降速比例上限 [-] / Upper derate bound
    DL_RIPPLE_MIN_MS: DINT := 500;                   // 波动窗下限 [毫秒] / Minimum ripple window
    DL_RIPPLE_MAX_MS: DINT := 30000;                 // 波动窗上限 [毫秒] / Maximum ripple window
    DL_CONFIRM_MIN  : DINT := 500;                   // 确认时长下限 [毫秒] / Minimum confirmation
    DL_CONFIRM_MAX  : DINT := 30000;                 // 确认时长上限 [毫秒] / Maximum confirmation
    DL_HOLD_MIN     : DINT := 5000;                  // 抑制窗下限 [毫秒] / Minimum hold-off
    DL_HOLD_MAX     : DINT := 600000;                // 抑制窗上限 [毫秒] / Maximum hold-off
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜确定性默认值与单拍标志预清零（R25 第一律）
 *      Deterministic defaults and one-shot flags pre-cleared
 *-----------------------------------------------------------------------------*)
_bResetPulse   := FALSE;                              // 复位单拍预清零（Reset pre-cleared）
_bParamBad     := FALSE;                              // 参数非法预清零（Illegal parameter pre-cleared）
_bDerateStep   := FALSE;                              // 降速单拍预清零（Derate step pre-cleared）
_bConfirmEvent := FALSE;                              // 确认事件预清零（Confirmation event pre-cleared）
_bCritFlow     := FALSE;                              // 流量判据预清零（Flow criterion pre-cleared）
_bCritHead     := FALSE;                              // 扬程判据预清零（Head criterion pre-cleared）
_bCritVib      := FALSE;                              // 振动判据预清零（Vibration criterion pre-cleared）
_bCritRipple   := FALSE;                              // 波动判据预清零（Ripple criterion pre-cleared）
_bVibEmergency := FALSE;                              // 振动急停预清零（Emergency pre-cleared）

(*------------------------------------------------------------------------------
 * 段 2｜首扫初始化（R19：bInit 初值 FALSE，判据取非；首拍只装基准）
 *      First-scan initialisation, baseline only
 *-----------------------------------------------------------------------------*)
IF NOT _bInit THEN
    _eState       := E_DL_CavitationState.eIdle;      // 相位待机（Phase idle）
    _bFaultLatch  := FALSE;                           // 故障锁存清零（Latch cleared）
    _uErrFault    := 16#0000_0000;                    // 首出码清零（First-out code cleared）
    _bCavLatch    := FALSE;                           // 汽蚀锁存清零（Cavitation latch cleared）
    _fDerateRatio := DL_DERATE_MAX;                   // 冷启动比率 1.0，落在有效域内（Cold start at 1.0）
    _bDerateHeld  := FALSE;                           // 降速请求清零（Derate request cleared）
    _uEventCount  := 0;                               // 事件计数清零（Event counter cleared）
    _fRipple      := 0.0;                             // 波动率初值 0（Ripple starts at zero）
    _fCurrMin     := DL_VAL_LIM;                      // 最小值先置上界（Minimum preset to the ceiling）
    _fCurrMax     := 0.0;                             // 最大值先置 0（Maximum preset to zero）
    _fCurrSum     := 0.0;                             // 电流累加清零（Current sum cleared）
    _nCurrCount   := 0;                               // 样本数清零（Sample count cleared）
    _fFlowNomUse  := 1.0;                             // 额定流量兜底（Nominal flow fallback）
    _fHeadNomUse  := 1.0;                             // 额定扬程兜底（Nominal head fallback）
    _bInit        := TRUE;                            // 首扫只做一次（First scan runs once）
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜参数闸门与输入域检查（额定值非正或阈值倒置属故障级）
 *      Parameter gate: non-positive nominals or inverted thresholds latch a fault
 *-----------------------------------------------------------------------------*)
IF (fFlowNominal <= DL_EPS) OR (fHeadNominal <= DL_EPS) OR (fVibLimit <= DL_EPS) THEN
    _bParamBad := TRUE;                               // 额定值或振动上限非正（Non-positive nominals）
END_IF
IF (fFlowLowRatio <= 0.0) OR (fFlowLowRatio >= 1.0) OR (fHeadDropRatio <= 0.0) OR (fHeadDropRatio >= 1.0) THEN
    _bParamBad := TRUE;                               // 比例阈值倒置（Inverted ratios）
END_IF
IF (fCurrentRippleLimit <= 0.0) OR (fDerateStep <= 0.0) OR (fDerateStep > 0.5) THEN
    _bParamBad := TRUE;                               // 波动限或步长非法（Illegal ripple limit or step）
END_IF

IF fFlowNominal > DL_EPS THEN
    _fFlowNomUse := fFlowNominal;                     // 额定流量直通（Nominal flow passed through）
ELSE
    _fFlowNomUse := 1.0;                              // 非正：兜底为 1，防除零（Fallback avoids a zero divisor）
END_IF
IF fHeadNominal > DL_EPS THEN
    _fHeadNomUse := fHeadNominal;                     // 额定扬程直通（Nominal head passed through）
ELSE
    _fHeadNomUse := 1.0;                              // 非正：兜底为 1（Fallback）
END_IF

_fFlowLowUse   := LIMIT(0.2, fFlowLowRatio, 0.95);    // 流量比例钳进 0.2~0.95（Clamped）
_fHeadDropUse  := LIMIT(0.05, fHeadDropRatio, 0.5);   // 跌幅比例钳进 0.05~0.5（Clamped）
_fVibUse       := LIMIT(1.0, fVibLimit, 20.0);        // 振动上限钳进 1~20 mm/s（Clamped）
_fRippleLimUse := LIMIT(0.02, fCurrentRippleLimit, 0.5); // 波动限钳进 0.02~0.5（Clamped）
_fStepUse      := LIMIT(0.02, fDerateStep, 0.3);      // 降速步长钳进 0.02~0.3（Clamped）

_diMs         := LIMIT(DL_RIPPLE_MIN_MS, TIME_TO_DINT(tRippleWindow), DL_RIPPLE_MAX_MS); // 波动窗钳位（Clamped）
_tRippleUse   := DINT_TO_TIME(_diMs);                 // 生效波动窗（Effective ripple window）
_diMs         := LIMIT(DL_CONFIRM_MIN, TIME_TO_DINT(tConfirm), DL_CONFIRM_MAX); // 确认时长钳位（Clamped）
_tConfirmUse  := DINT_TO_TIME(_diMs);                 // 生效确认时长（Effective confirmation）
_diMs         := LIMIT(DL_HOLD_MIN, TIME_TO_DINT(tHoldOff), DL_HOLD_MAX); // 抑制窗钳位（Clamped）
_tHoldUse     := DINT_TO_TIME(_diMs);                 // 生效抑制窗（Effective hold-off）

(*------------------------------------------------------------------------------
 * 段 4｜定时器与边沿实例无条件刷新（红线：实例一律在 CASE 之外每拍必调）
 *      Timers and edge detectors refreshed unconditionally outside the CASE
 *-----------------------------------------------------------------------------*)
fbTrigReset(CLK := bReset);                           // 复位沿刷新（Reset edge refreshed）

fbConfirmWatch(IN := _bAllThree AND (_eState = E_DL_CavitationState.eSuspect) AND (NOT _bConfirmBreak), PT := _tConfirmUse); // 三判据持续计时
_bConfirmBreak := FALSE;                              // 断输入拍在调用后自清（Break self-cleared）

fbRippleWatch(IN := bRunning AND (NOT _bRippleBreak), PT := _tRippleUse); // 波动统计窗
_bRippleBreak := FALSE;                               // 断输入拍在调用后自清（Break self-cleared）

fbHoldOffWatch(IN := (_eState = E_DL_CavitationState.eDerate) AND (NOT _bHoldBreak), PT := _tHoldUse); // 抑制窗计时
_bHoldBreak := FALSE;                                 // 断输入拍在调用后自清（Break self-cleared）
_bHoldActive := (_eState = E_DL_CavitationState.eDerate) OR fbHoldOffWatch.Q; // 抑制生效 = 整个降速相（不是窗满那一拍）

(*------------------------------------------------------------------------------
 * 段 5｜判据计算（比值前置守卫，绝不输出无穷大；V5）
 *      Criteria, ratios guarded against division by zero
 *-----------------------------------------------------------------------------*)
(* 比值口径：额定值非正时**输出 0**，绝不拿兜底值 1.0 去算伪比值（V5 明确要求） *)
IF fFlowNominal > DL_EPS THEN
    _fFlowRatio := LIMIT(0.0, fFlow / _fFlowNomUse, DL_RATIO_MAX); // 流量比值，钳 0~2（Clamped）
ELSE
    _fFlowRatio := 0.0;                               // 额定流量非法：输出 0，不给伪比值（Never a pseudo ratio）
END_IF
IF fHeadNominal > DL_EPS THEN
    _fHeadRatio := LIMIT(0.0, fHead / _fHeadNomUse, DL_RATIO_MAX); // 扬程比值，钳 0~2（Clamped）
ELSE
    _fHeadRatio := 0.0;                               // 额定扬程非法：输出 0（Never a pseudo ratio）
END_IF
IF _fVibUse > DL_EPS THEN
    _fVibRatio := LIMIT(0.0, fVibration / _fVibUse, DL_VIB_RATIO_MAX); // 振动比值，上限须容得下急停倍率（Clamped）
ELSE
    _fVibRatio := 0.0;                                // 分母不可用：输出 0（Never infinity）
END_IF

(* 三判据：停泵或抑制窗内一律不成立（Suppressed when stopped or within the hold-off） *)
IF bRunning AND bEnable AND (NOT _bHoldActive) THEN
    _bCritFlow   := _fFlowRatio < _fFlowLowUse;                       // 流量偏低（Low flow）
    _bCritHead   := _fHeadRatio < (1.0 - _fHeadDropUse);              // 扬程跌落（Head drop）
    _bCritVib    := _fVibRatio > 1.0;                                 // 振动超限（Vibration above limit）
    _bCritRipple := _fRipple > _fRippleLimUse;                        // 电流波动超限（Ripple above limit）
END_IF
_bCritVibGroup := _bCritVib OR _bCritRipple;                          // 第三判据：振动或波动（Third criterion）
_bAllThree     := _bCritFlow AND _bCritHead AND _bCritVibGroup;       // 三判据同拍（All three in one scan）
_bAnyCrit      := _bCritFlow OR _bCritHead OR _bCritVibGroup;         // 任一判据（Any criterion）
(* 急停级：仅在泵运行且使能时成立。停泵时邻近设备振动/传感器卡值不得把本件拉进锁存，
 * 与「bRunning 为 FALSE 时全部判据抑制」同一条纪律；降速抑制窗内仍照判（等级高于判据） *)
IF bRunning AND bEnable AND (_fVibRatio > DL_VIB_EMERG) THEN
    _bVibEmergency := TRUE;                                           // 振动超两倍上限（Emergency level）
END_IF

(* 电流波动统计：窗满出一值并重启窗（Window closes, one value produced, window restarts） *)
IF bRunning THEN
    IF fCurrent < _fCurrMin THEN
        _fCurrMin := fCurrent;                        // 更新最小（Update the minimum）
    END_IF
    IF fCurrent > _fCurrMax THEN
        _fCurrMax := fCurrent;                        // 更新最大（Update the maximum）
    END_IF
    _fCurrSum := _fCurrSum + fCurrent;                // 累加（Accumulate）
    IF _nCurrCount < 16#FFFF_FFFF THEN
        _nCurrCount := _nCurrCount + 1;               // 计数防上溢（Guard the counter）
    END_IF
    IF fbRippleWatch.Q THEN
        IF _nCurrCount > 0 THEN
            IF (_fCurrSum / UDINT_TO_REAL(_nCurrCount)) > DL_EPS THEN
                _fRipple := (_fCurrMax - _fCurrMin) / (_fCurrSum / UDINT_TO_REAL(_nCurrCount)); // 波动率，分母已守卫
            ELSE
                _fRipple := 0.0;                      // 平均近零：不判波动（No meaningful ripple）
            END_IF
        END_IF
        _fCurrMin   := DL_VAL_LIM;                    // 窗重启：最小值复位（Window restarted）
        _fCurrMax   := 0.0;                           // 窗重启：最大值复位（Window restarted）
        _fCurrSum   := 0.0;                           // 窗重启：累加清零（Window restarted）
        _nCurrCount := 0;                             // 窗重启：计数清零（Window restarted）
        _bRippleBreak := TRUE;                        // 断输入一拍后重新计时（One-scan break restarts the timer）
    END_IF
ELSE
    _fCurrMin   := DL_VAL_LIM;                        // 停泵清零（Cleared while stopped）
    _fCurrMax   := 0.0;                               // 停泵清零（Cleared while stopped）
    _fCurrSum   := 0.0;                               // 停泵清零（Cleared while stopped）
    _nCurrCount := 0;                                 // 停泵清零（Cleared while stopped）
    _fRipple    := 0.0;                               // 停泵清实测值，防停泵前旧值跨停机存活（Stale ripple must not survive a stop）
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜复位通道 + 故障锁存（CASE 前置；**不做状态变量赋值**，R39）
 *      Reset channel and fault latching before the CASE, with no state write
 *-----------------------------------------------------------------------------*)
IF fbTrigReset.Q THEN
    _bResetPulse := TRUE;                             // 复位单拍（One-shot reset）
END_IF

IF _bResetPulse THEN
    _bFaultLatch := FALSE;                            // 清故障锁存（Latch cleared）
    _uErrFault   := 16#0000_0000;                     // 清首出码（First-out code cleared）
    _bCavLatch   := FALSE;                            // 清汽蚀锁存（Cavitation latch cleared）
    _bDerateHeld := FALSE;                            // 撤降速请求，交给上层斜坡（Release the request to the upper ramp）
    IF _bAnyCrit THEN
        _fDerateRatio := LIMIT(DL_DERATE_MIN, _fDerateRatio, DL_DERATE_MAX); // 判据仍在：比率保持并夹域（Held while criteria persist）
    ELSE
        _fDerateRatio := LIMIT(DL_DERATE_MIN, _fDerateRatio + _fStepUse, DL_DERATE_MAX); // 判据已消：回升一步，不直接回 1.0（R41）
    END_IF
    _bConfirmBreak := TRUE;                           // 确认计时重启（Confirmation timer restarted）
    _bRippleBreak  := TRUE;                           // 波动窗重启（Ripple window restarted）
    _bHoldBreak    := TRUE;                           // 抑制窗重启（Hold-off restarted）
END_IF

IF _bParamBad AND (NOT _bFaultLatch) THEN
    _uErrFault   := 16#0003_0328;                     // 0328 额定值非正或阈值倒置（Illegal nominals or thresholds）
    _bFaultLatch := TRUE;                             // 锁存（Latched）
END_IF

(*------------------------------------------------------------------------------
 * 段 7｜监视相位机（6 个成员各一标签 + ELSE 兜底）
 *      Monitoring state machine, one label per member plus a trailing fallback
 *-----------------------------------------------------------------------------*)
CASE _eState OF

    E_DL_CavitationState.eIdle: // 待机：起泵后进入监视
        IF _bFaultLatch THEN
            _eState := E_DL_CavitationState.eFault;   // 已锁故障（Already latched）
        ELSIF bEnable AND bRunning THEN
            _bConfirmBreak := TRUE;                   // 确认计时从 0 起算（Confirmation restarts）
            _bRippleBreak  := TRUE;                   // 波动窗从 0 起算（Ripple window restarts）
            _bHoldBreak    := TRUE;                   // 抑制窗从 0 起算（Hold-off restarts）
            _eState := E_DL_CavitationState.eMonitor; // 进监视（Enter monitoring）
        END_IF

    E_DL_CavitationState.eMonitor: // 监视：任一判据即进嫌疑
        IF _bFaultLatch THEN
            _eState := E_DL_CavitationState.eFault;   // 转故障（Enter the fault state）
        ELSIF (NOT bEnable) OR (NOT bRunning) THEN
            _eState := E_DL_CavitationState.eIdle;    // 停泵或掉使能回待机（Stopped or disabled, back to idle）
        ELSIF _bAnyCrit AND (NOT _bHoldActive) THEN
            _bConfirmBreak := TRUE;                   // 进嫌疑：确认计时从 0 起算（R40 段边界断输入）
            _eState := E_DL_CavitationState.eSuspect; // 进嫌疑（Enter suspect）
        END_IF

    E_DL_CavitationState.eSuspect: // 嫌疑：三判据同拍并持续满足才确认
        IF _bFaultLatch THEN
            _eState := E_DL_CavitationState.eFault;   // 转故障（Enter the fault state）
        ELSIF (NOT bEnable) OR (NOT bRunning) THEN
            _eState := E_DL_CavitationState.eIdle;    // 停泵回待机（Stopped, back to idle）
        ELSIF NOT _bAnyCrit THEN
            _bConfirmBreak := TRUE;                   // 判据消失：确认计时断输入（Criterion cleared, timer broken）
            _eState := E_DL_CavitationState.eMonitor; // 回监视（Back to monitoring）
        ELSIF fbConfirmWatch.Q THEN
            _bConfirmEvent := TRUE;                   // 确认事件单拍（Confirmation event）
            _eState := E_DL_CavitationState.eConfirm; // 进确认（Enter confirmation）
        END_IF

    E_DL_CavitationState.eConfirm: // 确认：本拍锁存并请求降速，随后进入降速相
        _bConfirmBreak := TRUE;                       // 确认计时清零（Confirmation cleared）
        _bHoldBreak    := TRUE;                       // 抑制窗从 0 起算（Hold-off restarts）
        _eState := E_DL_CavitationState.eDerate;      // 进降速（Enter derate）
        IF (NOT bEnable) OR (NOT bRunning) THEN
            _eState := E_DL_CavitationState.eIdle;    // 停泵中止（Stopped, abort）
        END_IF

    E_DL_CavitationState.eDerate: // 降速：抑制窗内忽略判据，窗满且判据消失才回监视
        IF _bFaultLatch THEN
            _eState := E_DL_CavitationState.eFault;   // 转故障（Enter the fault state）
        ELSIF (NOT bEnable) OR (NOT bRunning) THEN
            _bHoldBreak := TRUE;                      // 抑制窗中断（Hold-off stopped）
            _eState := E_DL_CavitationState.eIdle;    // 停泵回待机（Stopped, back to idle）
        ELSIF fbHoldOffWatch.Q THEN
            (* 抑制窗内判据被强制为假，故出口条件只看窗满；窗满后判据在
             * eMonitor 重新评估，若仍成立会再次进入嫌疑并再降一步 *)
            _bHoldBreak := TRUE;                      // 抑制窗结束重启（Hold-off finished）
            _bDerateHeld := FALSE;                    // 撤降速请求，交由上层斜坡（Request released to the upper ramp）
            _bConfirmBreak := TRUE;                   // 确认计时重启（Confirmation restarted）
            _eState := E_DL_CavitationState.eMonitor; // 回监视（Back to monitoring）
        END_IF

    E_DL_CavitationState.eFault: // 故障：等复位
        IF _bResetPulse THEN
            _eState := E_DL_CavitationState.eIdle;    // 复位受理（Reset accepted）
        END_IF

    ELSE
        _uErrFault   := 16#0003_0329;                 // 0329 非法状态兜底（Illegal state fallback）
        _bFaultLatch := TRUE;                         // 兜底锁存（Fallback latched）
        _eState      := E_DL_CavitationState.eFault;  // 进终端安全态（Terminal safe state）
END_CASE

(*------------------------------------------------------------------------------
 * 段 8｜降速执行与事件锁存（确认事件、步进、急停级）
 *      Derate execution and event latching
 *-----------------------------------------------------------------------------*)
IF _bConfirmEvent THEN
    _bCavLatch := TRUE;                               // 汽蚀锁存（Cavitation latched）
    IF NOT _bFaultLatch THEN
        _uErrFault := 16#0003_0326;                   // 汽蚀确认亦属故障级：写入末次故障码，防 bError 为真而 uErrorId 为 0（R21 一致性）
    END_IF
    _bDerateHeld := TRUE;                             // 降速请求保持（Request held）
    _bDerateStep := TRUE;                             // 本拍降一步（Step down this scan）
    IF _uEventCount < 16#FFFF_FFFF THEN
        _uEventCount := _uEventCount + 1;             // 事件计数（Event counter incremented）
    END_IF
    _bConfirmEvent := FALSE;                          // 单拍消费后自清（Event consumed）
END_IF

IF _bDerateStep THEN
    _fDerateRatio := LIMIT(DL_DERATE_MIN, _fDerateRatio - _fStepUse, DL_DERATE_MAX); // 递减一步并夹域（Step down, clamped）
    _bDerateStep := FALSE;                            // 单拍消费后自清（Step consumed）
END_IF

IF _bVibEmergency AND (NOT _bFaultLatch) THEN
    _uErrFault   := 16#0003_0327;                     // 0327 振动超两倍上限（Emergency vibration）
    _bFaultLatch := TRUE;                             // 锁存（Latched）
    _bCavLatch   := TRUE;                             // 急停级同样置汽蚀（Treated as cavitation evidence）
END_IF

IF (_eState = E_DL_CavitationState.eDerate) OR _bFaultLatch THEN
    _bDerateHeld := TRUE;                             // 降速态与故障态内请求保持（Request held in derate and fault）
END_IF

(*------------------------------------------------------------------------------
 * 段 9｜健康仲裁、出口钳位与保持重写（R27 + R43）
 *      Health arbitration, clamping and hold semantics
 *-----------------------------------------------------------------------------*)
IF _bFaultLatch OR _bCavLatch THEN
    _eHealthInt := E_DL_Ne107Status.eFailure;         // 失效：含汽蚀确认（Failure, including confirmed cavitation）
ELSIF _eState = E_DL_CavitationState.eSuspect THEN
    _eHealthInt := E_DL_Ne107Status.eOutOfSpec;       // 嫌疑：超出规格但未确认（Suspect, out of specification）
ELSIF NOT bEnable THEN
    _eHealthInt := E_DL_Ne107Status.eUnknown;         // 未使能（Disabled）
ELSE
    _eHealthInt := E_DL_Ne107Status.eOk;              // 正常（OK）
END_IF

eHealth        := _eHealthInt;                        // 健康态出口（Health outlet）
bCavitation    := _bCavLatch;                         // 汽蚀锁存保持重写（Held cavitation flag）
bDerateRequest := _bDerateHeld;                       // 降速请求保持重写（Held request rewritten）
fDerateRatio   := LIMIT(DL_DERATE_MIN, _fDerateRatio, DL_DERATE_MAX); // 比率钳进 0.3~1.0（Clamped, R43）
fFlowRatio     := LIMIT(0.0, _fFlowRatio, DL_RATIO_MAX); // 流量比值钳位（Clamped）
fHeadRatio     := LIMIT(0.0, _fHeadRatio, DL_RATIO_MAX); // 扬程比值钳位（Clamped）
fVibRatio      := LIMIT(0.0, _fVibRatio, DL_VIB_RATIO_MAX); // 振动比值钳位（Clamped）
nEventCount    := _uEventCount;                       // 事件计数出口（Event counter outlet）
fRippleMeas    := LIMIT(0.0, _fRipple, 10.0);          // 波动率出口钳进 0~10（Clamped）
bError         := _bFaultLatch OR _bCavLatch;          // 汽蚀确认亦属失效级（Confirmed cavitation is a failure）

(*------------------------------------------------------------------------------
 * 段 10｜码位单一优先级链（全拍只写一次 uDiagCode）
 *      Single priority chain, the diagnostic code is written exactly once
 *-----------------------------------------------------------------------------*)
IF _bFaultLatch THEN
    _uDiagCode := _uErrFault;                         // 故障级优先，保留首出码（Fault level, first-out code）
ELSIF _bCavLatch THEN
    _uDiagCode := 16#0003_0326;                       // 0326 汽蚀确认（Cavitation confirmed）
ELSIF (_eState = E_DL_CavitationState.eSuspect) THEN
    _uDiagCode := 16#0003_0164;                       // 0164 单判据嫌疑（Single criterion, suspect only）
ELSIF _bHoldActive THEN
    _uDiagCode := 16#0003_0165;                       // 0165 抑制窗内判据被忽略（Criteria ignored in the hold-off）
ELSE
    _uDiagCode := 16#0000_0000;                       // 无码（No code）
END_IF

uDiagCode := _uDiagCode;                              // 诊断码出口（Diagnostic code outlet）
uErrorId  := _uErrFault;                              // 末次故障码出口（Last fault code outlet）

END_FUNCTION_BLOCK
