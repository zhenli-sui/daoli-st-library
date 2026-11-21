(*==============================================================================
 * 组件名称 (Component)  : FB_DL_GripperForceVerify
 * 所属子库 (Sublibrary) : DL_Device
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG / ABS），零厂商私有库
 * 功能描述 (Function)   : 夹爪力窗判定——空夹 / 滑脱 / 超力三类特征判定，结果分档输出。
 *                         判定在"夹紧指令上升沿 → 验证窗结束"这一段内完成，三类特征用不同的
 *                         物理证据区分（这是本件的核心：三者混判会导致维护方向完全错误）：
 *                           ① **空夹**：整个验证窗内峰值力都没到 fForceLow —— 根本没夹到件
 *                              （或件不在位），属上料/定位问题；
 *                           ② **滑脱**：峰值曾达 fForceLow 以上，但窗末力已掉到 fForceLow 以下，
 *                              或窗内出现力衰减速率超过 fSlipRate 的快速下跌 —— 夹到了但滑了，
 *                              属夹爪面磨损/气压不足/件表面油污问题；
 *                           ③ **超力**：窗内峰值超过 fForceHigh —— 夹爪力过大，有压伤件的风险。
 *                         判定优先级：超力 > 滑脱 > 空夹 > 合格（超力是安全侧优先报）。
 *                         验证窗结束即出结论（eResult 分档），结论锁存到下一次夹紧指令或复位，
 *                         故 bOk 不会在窗口中途闪变。
 * 接口     (Interface)  : 输入 bGripCmd 夹紧指令、fForce 夹持力实测、fForceLow / fForceHigh 力窗
 *                         上下限（N）、fSlipRate 滑脱判定速率（N/s）、tVerify 验证窗（TIME）、
 *                         fVerifySec 同一窗的秒数值（REAL，与 tVerify 成对）、fDtS 采样周期（秒）、
 *                         bReset 复位；输出 eResult 判定结果、bOk 合格、bNg 不合格、fPeak 窗内
 *                         峰值力、fFellRate 窗内最大衰减速率、bVerified 结论已出、eState / eCause /
 *                         bError。
 * 边界     (Boundary)   : ① **属主边界（写死）：本件只判"夹持结果"，不控制夹爪电磁阀/伺服，
 *                         不做夹紧动作本身**。夹紧动作与到位属 `I_DL_Cylinder` / 夹爪执行件；
 *                         本件吃夹紧指令与力反馈，出判定结论供剔除与报警。
 *                         ② **PT 语义成对声明**：tVerify（TIME）与 fVerifySec（REAL）必须由调用方
 *                         成对给同一窗长。本件用 tVerify 驱动 TON，用 fVerifySec 参与速率换算
 *                         （fSlipRate × fVerifySec 的位移阈值思路相同），**全程不做 TIME→数值转换**。
 *                         ③ 组态闸：fForceLow <= 0.0、fForceHigh <= fForceLow、fSlipRate <= 0.0、
 *                         tVerify <= T#0S、fVerifySec <= eps、fDtS <= eps、任一 NaN → 故障锁存，
 *                         eResult 置 eFault 档（不宣称任何结论）。
 *                         ④ 单枚 TON（tonVerify）+ 两枚 R_TRIG（bGripCmd / bReset）段 0 无条件刷新；
 *                         tonVerify 用 IN :=（夹紧中 ∧ ¬Q）自复位，不靠外部沿清零（R188）。
 *                         ⑤ 故障相迁出唯一路径 = bReset 上升沿（R228B）。
 *                         ⑥ 零全局耦合（无 GVL / 无 VAR_EXTERNAL / 无物理地址）。
 * 分工声明 (Scope)      : 与 `FB_DL_AxisTorqueLimitGuard`（旋转轴力矩限）分工——那件是轴侧连续
 *                         力矩保护，本件是夹爪气动/电动夹持的**结果验证**；量程、时间尺度、
 *                         判据形态都不同，不可互替。
 * 来源标签 (Source Tag) : T2-6 ◐（开源参考：夹持力窗与滑脱判定特征参数域，零代码行复制）
 * 解除式   (Release)    : bReset 上升沿 ∧ 组态合法 → 清故障与结论，回等待相。
 *                         另：新的 bGripCmd 上升沿也会重开一次判定（正常工艺路径，非解除式）。
 * 码表     (Codes)      : 本件不占用任何全局数字码位。出口为 ENUM 结论分档 + BOOL 组；
 *                         数字码位待主控收口阶段统一派号。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 除零闸（fDtS）+ 力窗几何闸 + 浮点容差 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 ✓ ENUM+CASE 含 ELSE ｜ R7 ✓ TON/R_TRIG 段 0 无条件刷新
 * 修订历史 (Revision)   : 2026-11-19  v1.0.0  R46 首版（批次 4 · 序号 18）
 *==============================================================================*)

TYPE E_DL_GfvResult :
(
    ePending  := 0,    // 验证窗进行中，结论未出 / Verification window in progress
    eOk       := 10,   // 合格（力在窗内且未滑脱） / Passed, force inside the window with no slip
    eEmpty    := 20,   // 空夹（峰值力从未达到下限） / Empty grip, peak never reached the lower limit
    eSlip     := 30,   // 滑脱（曾建立夹持力但掉出下限） / Slipped, grip established then lost
    eOverforce:= 40,   // 超力（峰值力超上限） / Over-force, peak exceeded the upper limit
    eFault    := 90    // 组态故障，未判定 / Configuration fault, not judged
);
END_TYPE

TYPE E_DL_GfvState :
(
    eIdle  := 0,    // 等待夹紧指令 / Awaiting a grip command
    eVerify:= 10,   // 验证窗进行相 / Verification window active
    eDone  := 20,   // 结论已出相（锁存） / Conclusion latched
    eFault := 90    // 组态故障相 / Configuration fault phase
);
END_TYPE

TYPE E_DL_GfvCause :
(
    eNone       := 0,   // 无异常 / No anomaly
    eCfgIllegal := 1,   // 组态非法（力窗倒置/速率非正/窗长非正/非有限） / Illegal configuration
    eEmptyGrip  := 2,   // 空夹 / Empty grip
    eSlipped    := 3,   // 滑脱 / Slipped
    eOverForce  := 4,   // 超力 / Over-force
    ePhaseBad   := 5    // 非法相位兜底 / Illegal phase fallback
);
END_TYPE

FUNCTION_BLOCK FB_DL_GripperForceVerify
VAR_INPUT
    bGripCmd    : BOOL := FALSE;        // 夹紧指令，上升沿开启验证窗 [-] / Grip command, rising edge opens the window
    fForce      : REAL := 0.0;          // 夹持力实测 [N] / Measured grip force [N]
    fForceLow   : REAL := 10.0;         // 力窗下限，域 > 0.0 [N] / Force window lower limit, > 0.0 [N]
    fForceHigh  : REAL := 80.0;         // 力窗上限，域 > fForceLow [N] / Force window upper limit, > lower [N]
    fSlipRate   : REAL := 50.0;         // 滑脱判定衰减速率，域 > 0.0 [N/s] / Slip decay rate threshold, > 0.0 [N/s]
    tVerify     : TIME := T#300MS;      // 验证窗时长（TIME 侧），域 > T#0S [ms] / Verification window, TIME side [ms]
    fVerifySec  : REAL := 0.3;          // 同一窗的秒数值（REAL 侧），域 > eps [s] / Same window in seconds, REAL side [s]
    fDtS        : REAL := 0.001;        // 采样周期，域 > eps [s] / Sample period, > eps [s]
    bReset      : BOOL := FALSE;        // 复位，上升沿清结论与故障 [-] / Reset, rising edge clears result and fault
END_VAR
VAR_OUTPUT
    eResult   : E_DL_GfvResult;     // 判定结果分档 [-] / Verdict grade
    bOk       : BOOL;               // 合格 [-] / Passed
    bNg       : BOOL;               // 不合格（空夹/滑脱/超力任一） [-] / Failed, any of empty, slip or over-force
    fPeak     : REAL;               // 窗内峰值力 [N] / Peak force inside the window [N]
    fFellRate : REAL;               // 窗内最大衰减速率（正数表示下跌） [N/s] / Maximum decay rate in the window, positive means falling [N/s]
    bVerified : BOOL;               // 结论已出（本件已判定，非进行中） [-] / Verdict delivered
    eState    : E_DL_GfvState;      // 状态出口 [-] / State outlet
    eCause    : E_DL_GfvCause;      // 成因出口（R190 归因唯一） [-] / Cause outlet
    bError    : BOOL;               // 故障标志（组态非法或不合格） [-] / Error flag
END_VAR
VAR
    _eState  : E_DL_GfvState := E_DL_GfvState.eIdle;    // 内部相位（CASE 唯一写入目标） / Internal phase
    _eCause  : E_DL_GfvCause := E_DL_GfvCause.eNone;    // 成因锁存量 / Latched cause
    _eResult : E_DL_GfvResult := E_DL_GfvResult.ePending;    // 结论锁存量 / Latched verdict
    tonVerify: TON;                 // 验证窗计时（自复位），段 0 无条件调用 / Verification window, self-resetting
    rtGrip   : R_TRIG;              // 夹紧指令沿实例，段 0 无条件调用 / Grip edge instance
    rtReset  : R_TRIG;              // 复位沿实例，段 0 无条件调用 / Reset edge instance
    _fPeak   : REAL;                // 窗内峰值力（锁存量） [N] / Peak force in the window, latched [N]
    _fPrev   : REAL;                // 上拍力快照（锁存量） [N] / Previous force, latched [N]
    _fFell   : REAL;                // 窗内最大衰减速率（锁存量） [N/s] / Maximum decay rate, latched [N/s]
    _bSlipSeen : BOOL;              // 窗内已见滑脱特征（锁存量） / Slip feature seen in the window, latched
    _bFault  : BOOL;                // 组态故障锁存位（锁存量） / Latched configuration fault
    _bCfgBad : BOOL;                // 组态非法当拍量 [-] / Illegal configuration this scan
    _bNonFin : BOOL;                // 输入非有限当拍量 [-] / Non-finite input this scan
    _fRate   : REAL;                // 当拍力变化速率的负向幅值 [N/s] / Present decay rate magnitude [N/s]
END_VAR
VAR CONSTANT
    DL_GFV_EPS : REAL := 1.0E-9;    // 时间与速率判零容差 [无量纲] / Time and rate epsilon
END_VAR

(* —— 段 0：判据派生 + 三实例无条件周期刷新 —— *)
_bNonFin := (fForce <> fForce) OR (fForceLow <> fForceLow)                // NaN 自反判（判等禁令唯一例外） / NaN self-reflexive tests
         OR (fForceHigh <> fForceHigh) OR (fSlipRate <> fSlipRate)
         OR (fVerifySec <> fVerifySec) OR (fDtS <> fDtS);
_bCfgBad := (fForceLow <= 0.0) OR (fForceHigh <= fForceLow)               // 力窗几何闸 / Force-window geometry gate
         OR (fSlipRate <= 0.0) OR (tVerify <= T#0S)                       // 速率与窗长闸 / Rate and window gates
         OR (fVerifySec <= DL_GFV_EPS) OR (fDtS <= DL_GFV_EPS) OR _bNonFin;   // 成对秒值与非有限 / Paired seconds and non-finite
rtGrip(CLK := bGripCmd);                                                  // 夹紧沿，每拍必调（R228A） / Grip edge, every scan
rtReset(CLK := bReset);                                                   // 复位沿，每拍必调 / Reset edge, every scan
tonVerify(IN := (_eState = E_DL_GfvState.eVerify) AND (NOT tonVerify.Q), PT := tVerify);   // 验证窗，自复位（R188） / Verification window, self-resetting

(* —— 段 1：单拍量预清零（锁存量 _fPeak/_fFell/_bSlipSeen/_eResult/_bFault 不入清单） —— *)
bOk       := FALSE;     // 合格位预清 / Passed preset
bNg       := FALSE;     // 不合格位预清 / Failed preset
bVerified := FALSE;     // 结论已出位预清 / Verified preset
bError    := FALSE;     // 故障标志预清（R45 配对） / Error flag preset

(* —— 段 2：复位沿（清结论与故障，回等待相） —— *)
IF rtReset.Q THEN
    _bFault    := FALSE;                            // 清故障锁存 / Clear the fault latch
    _bSlipSeen := FALSE;                            // 清滑脱特征 / Clear the slip feature
    _fPeak     := 0.0;                              // 峰值清零 / Peak cleared
    _fFell     := 0.0;                              // 衰减速率清零 / Decay rate cleared
    _eCause    := E_DL_GfvCause.eNone;              // 清成因 / Clear cause
    _eResult   := E_DL_GfvResult.ePending;          // 结论回进行中位 / Verdict back to pending
    _eState    := E_DL_GfvState.eIdle;              // 回等待相（R228B 迁出路径） / Back to idle, the R228B exit
END_IF
IF _bCfgBad THEN
    _bFault  := TRUE;                               // 组态非法锁存 / Latch illegal configuration
    _eCause  := E_DL_GfvCause.eCfgIllegal;          // 归因：组态非法 / Cause: illegal configuration
    _eResult := E_DL_GfvResult.eFault;              // 结论置故障档（不宣称） / Verdict set to fault, nothing claimed
    _eState  := E_DL_GfvState.eFault;               // 入故障相 / Enter fault phase
END_IF

(* —— 段 3：夹紧沿开启新一次验证（工艺路径，不属解除式） —— *)
IF rtGrip.Q AND (NOT _bCfgBad) THEN
    _fPeak     := 0.0;                              // 峰值重置 / Peak reset
    _fFell     := 0.0;                              // 衰减速率重置 / Decay rate reset
    _bSlipSeen := FALSE;                            // 滑脱特征重置 / Slip feature reset
    _fPrev     := fForce;                           // 力快照对齐（防首拍伪速率） / Align the snapshot to avoid a spurious first-scan rate
    _eResult   := E_DL_GfvResult.ePending;          // 结论进行中 / Verdict pending
    _eState    := E_DL_GfvState.eVerify;            // 入验证相 / Enter the verification phase
END_IF

(* —— 段 4：验证窗内的峰值与衰减跟踪（单点写入锁存量，避免同拍抹除，R187） —— *)
IF (_eState = E_DL_GfvState.eVerify) AND (NOT _bCfgBad) THEN
    IF fForce > _fPeak THEN
        _fPeak := fForce;                                       // 峰值跟踪 / Track the peak
    END_IF
    _fRate := (_fPrev - fForce) / fDtS;                         // 衰减速率（正数=下跌），分母已闸 / Decay rate, denominator gated
    IF _fRate > _fFell THEN
        _fFell := _fRate;                                       // 记录窗内最大衰减速率 / Track the maximum decay rate
    END_IF
    IF (_fRate > fSlipRate) AND (_fPeak >= fForceLow) THEN
        _bSlipSeen := TRUE;                                     // 已达下限后快速下跌 = 滑脱特征 / Fast decay after reaching the limit means slip
    END_IF
    _fPrev := fForce;                                           // 力快照更新 / Update the snapshot
END_IF

(* —— 段 5：窗末判定（三类特征按 超力 > 滑脱 > 空夹 > 合格 的优先级） —— *)
IF (_eState = E_DL_GfvState.eVerify) AND tonVerify.Q AND (NOT _bCfgBad) THEN
    IF _fPeak > fForceHigh THEN
        _eResult := E_DL_GfvResult.eOverforce;                  // 超力（安全侧最高优先） / Over-force, highest priority
        _eCause  := E_DL_GfvCause.eOverForce;
    ELSIF _bSlipSeen OR ((_fPeak >= fForceLow) AND (fForce < fForceLow)) THEN
        _eResult := E_DL_GfvResult.eSlip;                       // 滑脱：曾达下限但已掉出 / Slipped: reached the limit then lost it
        _eCause  := E_DL_GfvCause.eSlipped;
    ELSIF _fPeak < fForceLow THEN
        _eResult := E_DL_GfvResult.eEmpty;                      // 空夹：峰值从未达下限 / Empty: peak never reached the limit
        _eCause  := E_DL_GfvCause.eEmptyGrip;
    ELSE
        _eResult := E_DL_GfvResult.eOk;                         // 合格 / Passed
        _eCause  := E_DL_GfvCause.eNone;
    END_IF
    _eState := E_DL_GfvState.eDone;                             // 结论相 / Verdict phase
END_IF

(* —— 段 6：锁存相位迁移闸 —— *)
IF _bFault AND (_eState <> E_DL_GfvState.eFault) THEN
    _eState := E_DL_GfvState.eFault;                            // 锁存即入故障相 / Latch enters fault phase
END_IF

(* —— 段 7：相位机（ENUM 全成员显式标签 + ELSE 兜底，R128） —— *)
CASE _eState OF

E_DL_GfvState.eIdle:
    IF _bCfgBad THEN                                            // 出口 1：组态非法 / Illegal configuration
        _eState := E_DL_GfvState.eFault;
    ELSIF rtGrip.Q THEN                                         // 出口 2：夹紧沿 / Grip edge
        _eState := E_DL_GfvState.eVerify;
    END_IF

E_DL_GfvState.eVerify:
    IF _bCfgBad THEN                                            // 出口 1：组态转非法 / Configuration went illegal
        _eState := E_DL_GfvState.eFault;
    ELSIF (_eResult <> E_DL_GfvResult.ePending) THEN            // 出口 2：结论已出 / Verdict delivered
        _eState := E_DL_GfvState.eDone;
    END_IF

E_DL_GfvState.eDone:
    IF _bCfgBad THEN                                            // 出口 1：组态转非法 / Configuration went illegal
        _eState := E_DL_GfvState.eFault;
    ELSIF rtGrip.Q THEN                                         // 出口 2：新一次夹紧 / A new grip
        _eState := E_DL_GfvState.eVerify;
    ELSIF rtReset.Q THEN                                        // 出口 3：复位回等待相 / Reset back to idle
        _eState := E_DL_GfvState.eIdle;
    END_IF

E_DL_GfvState.eFault:
    IF rtReset.Q AND (NOT _bCfgBad) THEN                        // 出口：复位且组态已合法才迁出（R228B） / Reset with legal config
        _eState := E_DL_GfvState.eIdle;
    END_IF

ELSE
    _eCause  := E_DL_GfvCause.ePhaseBad;                        // 归因：非法相位 / Cause: illegal phase
    _eState  := E_DL_GfvState.eFault;                           // 强拉故障相 / Force fault phase
    _eResult := E_DL_GfvResult.eFault;                          // 结论置故障档 / Verdict to fault
    bError   := TRUE;                                           // 故障标志 / Error flag

END_CASE

(* —— 段 8：出口单点映射（结论分档与 bOk/bNg 同源；名实双出口，R191） —— *)
eResult   := _eResult;                                          // 结论出口 / Verdict outlet
fPeak     := _fPeak;                                            // 峰值出口 / Peak outlet
fFellRate := _fFell;                                            // 衰减速率出口 / Decay rate outlet
bVerified := (_eResult <> E_DL_GfvResult.ePending) AND (_eResult <> E_DL_GfvResult.eFault);   // 已判定且非故障档 / Judged and not in the fault grade
bOk       := (_eResult = E_DL_GfvResult.eOk);                    // 合格 / Passed
bNg       := (_eResult = E_DL_GfvResult.eEmpty) OR (_eResult = E_DL_GfvResult.eSlip)
          OR (_eResult = E_DL_GfvResult.eOverforce);             // 三类不合格 / Any of the three failure types
bError    := _bFault OR bNg;                                     // 故障标志 = 组态故障或不合格 / Error = config fault or failed verdict
eState    := _eState;                                            // 状态出口 / State outlet
eCause    := _eCause;                                            // 成因出口 / Cause outlet

END_FUNCTION_BLOCK
