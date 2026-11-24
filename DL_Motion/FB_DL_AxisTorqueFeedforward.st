(*==============================================================================
 * 组件名称 (Component)  : FB_DL_AxisTorqueFeedforward
 * 所属子库 (Sublibrary) : DL_Motion
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（ABS），零厂商私有库
 * 功能描述 (Function)   : 转矩前馈合成（刚体动力学 + 黏性摩擦项）：
 *                           fTorqueFF = fJ × fAccel + fVisc × fVel
 *                         输出限幅 ±fMax（必填，域 > 0，超限钳位并置信息码
 *                         eClamped）；J <= 0 → 拒算直通 0 并置信息码 eJInvalid
 *                         （规格指定）；非有限输入 → 输出 0、信息码 eInputHold。
 * 接口     (Interface)  : 输入 fAccel 角加速度 [rad/s²]、fJ 转动惯量（域 > 0
 *                         参算，<=0 拒算） [kg·m²]、fVisc 黏性摩擦系数
 *                         [N·m·s/rad]、fVel 角速度 [rad/s]、fMax 输出限幅
 *                         （必填，域 > 0） [N·m]、bReset 复位；输出 fTorqueFF
 *                         转矩前馈 [N·m]、eErrCode 错误码、bError 故障标志。
 * 边界     (Boundary)   : ① **属主边界（写死）：本件只算前馈标量，不做摩擦
 *                         辨识、不接管轴使能**；辨识归 `FB_DL_AxisInertiaIdent`
 *                         / `FB_DL_AxisFrictionFf`。
 *                         ② J <= 0 拒算直通 0（规格指定，物理上负/零惯量
 *                         无刚体动力学意义）；fVisc/fVel 不参与拒算域闸
 *                         （黏性项可独立为零）。
 *                         ③ fMax 必填闸：fMax <= 0 或非有限 → 锁存故障
 *                         eCfgBad，输出 0（限幅缺失时钳位语义不成立，不得
 *                         放行无界前馈），解除沿 = bReset 上升沿（R45 配对）。
 *                         ④ 非有限判据（R79 双判）：四个动力学量逐一双判；
 *                         拒算/非有限输出 0 均为信息级（不置 bError）。
 *                         ⑤ 限幅对称 ±fMax，钳位后信息码 eClamped（信息级）。
 *                         ⑥ 零全局耦合（无 GVL / VAR_EXTERNAL / 物理地址）。
 * 分工声明 (Scope)      : 与 `FB_DL_AxisFrictionFf` 分工：摩擦辨识与库仑项归
 *                         那件，本件黏性项为线性合成（系数直传）；与
 *                         `FB_DL_AxisCoggingFf` 分工：齿槽补偿归那件。
 * 来源标签 (Source Tag) : 自研线（刚体动力学 τ=Jα+Bω 为公开物理定义 clean-room）
 * 码表     (Codes)      : 本件不占用任何全局数字码位。出口为 LREAL 转矩 +
 *                         ENUM 错误码；数字码位待主控收口阶段统一派号。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ J 域拒算 + fMax 必填锁存 + 非有限双判 + 限幅
 *                         ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 N/A（无 ENUM 状态机） ｜ R7 ✓ 一 R_TRIG 段 0 无条件刷新
 * 修订历史 (Revision)   : 2026-11-20  v1.0.0  R50 首版（批次 3 · 序号 15）
 * 验收向量 (Acceptance) : ① fJ=0.01, fAccel=100, fVisc=0.005, fVel=1000,
 *                         fMax=10 → 0.01×100 + 0.005×1000 = 1.0 + 5.0 =
 *                         6.0 N·m，eOk；② 同输入 fMax=5 → 钳 ±5 → 5.0 N·m，
 *                         eClamped；③ fJ=0 → 输出 0，eJInvalid（fVisc×fVel
 *                         项一并拒算，规格①口径）；④ fMax=0 → 锁存 eCfgBad，
 *                         输出 0。
 *==============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_TffErr（错误码；信息级不置 bError，故障级恒伴 bError=TRUE）
 *----------------------------------------------------------------------------*)
TYPE E_DL_TffErr :
(
    eOk        := 0,   // 正常 / Normal
    eCfgBad    := 1,   // 故障级：fMax 必填闸破约（<=0 或非有限） / Fault: fMax mandatory gate violated
    eClamped   := 2,   // 信息级：输出超 ±fMax 已钳位 / Info: output clamped
    eJInvalid  := 3,   // 信息级：J<=0 拒算直通 0 / Info: non-positive J, zero output
    eInputHold := 4    // 信息级：动力学量非有限，输出 0 / Info: non-finite input, zero output
);
END_TYPE

FUNCTION_BLOCK FB_DL_AxisTorqueFeedforward
VAR_INPUT
    fAccel : LREAL := 0.0;            // 角加速度 [rad/s2] / Angular acceleration
    fJ     : LREAL := 0.01;           // 转动惯量（<=0 拒算） [kg·m2] / Inertia, non-positive rejects
    fVisc  : LREAL := 0.005;          // 黏性摩擦系数 [N·m·s/rad] / Viscous friction coefficient
    fVel   : LREAL := 0.0;            // 角速度 [rad/s] / Angular velocity
    fMax   : LREAL := 10.0;           // 输出限幅（必填，对称 ±），域 > 0 [N·m] / Torque limit, mandatory
    bReset : BOOL := FALSE;           // 复位，上升沿清组态故障锁存 [-] / Reset, rising edge clears cfg latch
END_VAR
VAR_OUTPUT
    fTorqueFF : LREAL;                // 转矩前馈输出（已限幅） [N·m] / Torque feedforward output
    eErrCode  : E_DL_TffErr;          // 错误码出口 / Error code outlet
    bError    : BOOL;                 // 故障标志（fMax 必填锁存） [-] / Error flag, latched
END_VAR
VAR
    _fRaw     : LREAL;                // 未限幅合成转矩 [N·m] / Raw composed torque
    _bJBad    : BOOL;                 // J 拒算当拍量 [-] / J rejection this scan
    _bNonFin  : BOOL;                 // 动力学量非有限当拍量 [-] / Non-finite dynamics this scan
    _bClamped : BOOL;                 // 本拍发生限幅 [-] / Clamped this scan
    _bCfgBad  : BOOL;                 // fMax 必填闸破约当拍量 [-] / fMax gate violation
    _bErrLatch: BOOL;                 // 组态故障锁存位（解除沿 = bReset 上升沿） / Latched config fault
    rtReset   : R_TRIG;               // 复位沿实例，段 0 无条件调用 / Reset edge instance
END_VAR
VAR CONSTANT
    DL_TFF_ZERO : LREAL := 0.0;       // 拒算输出与判零基准 [N·m] / Zero output and base
END_VAR

(* —— 段 0：非有限判 + 必填闸 + 沿刷新 —— *)
_bNonFin := (fAccel <> fAccel) OR ((fAccel - fAccel) <> DL_TFF_ZERO)
         OR (fJ <> fJ) OR ((fJ - fJ) <> DL_TFF_ZERO)
         OR (fVisc <> fVisc) OR ((fVisc - fVisc) <> DL_TFF_ZERO)
         OR (fVel <> fVel) OR ((fVel - fVel) <> DL_TFF_ZERO);   // 动力学量非有限（R79 双判） / Non-finite dynamics
_bCfgBad := (fMax <= DL_TFF_ZERO) OR (fMax <> fMax) OR ((fMax - fMax) <> DL_TFF_ZERO);   // fMax 必填闸（域 + 非有限） / fMax mandatory gate
rtReset(CLK := bReset);               // 复位沿，每拍必调 / Reset edge, every scan

(* —— 段 1：复位沿与组态锁存 —— *)
IF rtReset.Q THEN
    _bErrLatch := FALSE;              // 清组态锁存（R188 声明：解除沿 = bReset 上升沿） / Clear cfg latch
END_IF
IF _bCfgBad AND (NOT _bErrLatch) THEN
    _bErrLatch := TRUE;               // 锁存 / Latch
END_IF

(* —— 段 2：拒算判据（J<=0 与非有限并行记录，信息级） —— *)
_bJBad := (fJ <= DL_TFF_ZERO);        // J 拒算判据（规格②） / J rejection test

(* —— 段 3：转矩合成与限幅（故障/J 拒算/非有限 → 输出 0） —— *)
IF _bErrLatch THEN
    fTorqueFF := DL_TFF_ZERO;         // 故障安全侧 0（头注释③） / Fault safe-side zero
ELSIF _bNonFin THEN
    fTorqueFF := DL_TFF_ZERO;         // 非有限输出 0（规格） / Non-finite zero
ELSIF _bJBad THEN
    fTorqueFF := DL_TFF_ZERO;         // J<=0 拒算直通 0（规格②） / J rejection zero
ELSE
    _fRaw := fJ * fAccel + fVisc * fVel;   // 刚体 + 黏性合成 [N·m] / Rigid + viscous synthesis
    _bClamped := FALSE;               // 限幅量预清 / Clamp preset
    IF _fRaw > fMax THEN
        _fRaw := fMax;                // 上限钳位 / Clamp high
        _bClamped := TRUE;            // 记钳位 / Mark clamp
    ELSIF _fRaw < (-fMax) THEN
        _fRaw := -fMax;               // 下限钳位（对称 ±） / Clamp low symmetric
        _bClamped := TRUE;            // 记钳位 / Mark clamp
    END_IF
    fTorqueFF := _fRaw;               // 前馈出口（已限幅） / Feedforward outlet
END_IF

(* —— 段 4：出口单点映射（错误码归约，R191） —— *)
IF _bErrLatch THEN
    bError := TRUE;                   // 故障标志（R45 配对） / Error flag
    eErrCode := E_DL_TffErr.eCfgBad;  // 故障级码 / Fault code
ELSE
    bError := FALSE;                  // 无故障级条件 / No fault
    IF _bNonFin THEN
        eErrCode := E_DL_TffErr.eInputHold;   // 信息级：非有限口径 / Info: non-finite
    ELSIF _bJBad THEN
        eErrCode := E_DL_TffErr.eJInvalid;    // 信息级：J 拒算口径 / Info: J rejected
    ELSIF _bClamped THEN
        eErrCode := E_DL_TffErr.eClamped;     // 信息级：钳位口径 / Info: clamped
    ELSE
        eErrCode := E_DL_TffErr.eOk;          // 正常 / Normal
    END_IF
END_IF

END_FUNCTION_BLOCK
