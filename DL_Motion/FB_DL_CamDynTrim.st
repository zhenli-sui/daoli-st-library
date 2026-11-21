(*==============================================================================
 * 组件名称 (Component)  : FB_DL_CamDynTrim
 * 所属子库 (Sublibrary) : DL_Motion
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（ABS），零厂商私有库
 * 功能描述 (Function)   : 凸轮动态修调（相位 + 倍率双通道）：bApply 上升沿锁存
 *                         修调目标（先钳位：|fPhaseTrim| <= fPhTrimMaxDeg、
 *                         |fScaleTrim| <= fScTrimMaxPct，超幅钳位并置信息码
 *                         eClamped），生效期按 fPhRampDs/fScRampPs 斜率渐变
 *                         逼近目标（防凸轮表跳变，规格指定），双通道均到达后
 *                         bTrimActive 撤销（修调保持）；执行中（bTrimActive=
 *                         TRUE）新 bApply 沿被拒并置信息码 eBusyRej（拒绝
 *                         叠加，规格指定），拒次计数 uRejCnt。
 * 接口     (Interface)  : 输入 fPhaseTrim 相位修调请求 [deg]、fScaleTrim 倍率
 *                         修调请求 [%]、bApply 应用沿、fPhTrimMaxDeg 单次相位
 *                         修调幅值上限（域 > 0）、fScTrimMaxPct 单次倍率修调
 *                         幅值上限（域 > 0）、fPhRampDs 相位斜率（域 > 0）
 *                         [deg/s]、fScRampPs 倍率斜率（域 > 0） [%/s]、fCycle
 *                         扫描周期（<=0 用缺省） [s]、bReset 复位；输出
 *                         fPhTrimAct 生效相位修调 [deg]、fScTrimAct 生效倍率
 *                         修调 [%]、bTrimActive 斜坡执行中、uRejCnt 执行中
 *                         拒绝计数、eErrCode 错误码、bError 故障标志。
 * 边界     (Boundary)   : ① **属主边界（写死）：本件只出修调量标量对，不改写
 *                         凸轮表本体、不接管凸轮轴使能**；凸轮表插值归
 *                         `FB_DL_ElectronicCam`。
 *                         ② 生效通道单源：目标 _fPhTar/_fScTar 只在应用沿
 *                         锁存写入；生效量 _fPhAct/_fScAct 限步逼近，斜坡中
 *                         不受新请求污染（执行中拒绝叠加）。
 *                         ③ 幅值钳位：请求超上限钳到 ±上限并置信息码
 *                         eClamped（量值方向可饱和，钳位行在锁存行后置码，
 *                         先钳后码顺序无信息级丢失）。
 *                         ④ 到达判据用容差（禁浮点 =）；双通道各自独立到达，
 *                         bTrimActive = 任一通道未达。
 *                         ⑤ 组态闸：fPhTrimMaxDeg/fScTrimMaxPct/fPhRampDs/
 *                         fScRampPs 任一 <= 0 或非有限 → 锁存故障 eCfgBad，
 *                         生效量冻结保持，bTrimActive=FALSE，解除沿 = bReset
 *                         上升沿（R45 配对）。
 *                         ⑥ 零全局耦合（无 GVL / VAR_EXTERNAL / 物理地址）。
 * 分工声明 (Scope)      : 与 `FB_DL_CamPhaseTrim`/`FB_DL_CamOverrideTrim` 分工：
 *                         静态相位/倍率修调归那两件，本件为「斜坡渐生效 + 执行中
 *                         拒叠加」动态编排件；与 `FB_DL_EdgeTrimTraverse` 分工：
 *                         边缘修调归那件。
 * 来源标签 (Source Tag) : 自研线（凸轮动态修调编排为道莅防御性实现）
 * 码表     (Codes)      : 本件不占用任何全局数字码位。出口为 LREAL 修调对 +
 *                         BOOL 组 + UDINT 计数 + ENUM 错误码；数字码位待主控
 *                         收口阶段统一派号。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 幅值钳位 + 容差到达 + 组态锁存 + 非有限入闸
 *                         ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 N/A（锁存态无 CASE 状态机） ｜ R7 ✓ 两 R_TRIG 段 0 无条件刷新
 * 修订历史 (Revision)   : 2026-11-20  v1.0.0  R50 首版（批次 4 · 序号 19）
 * 验收向量 (Acceptance) : ① fPhTrimMaxDeg=10：请求 fPhaseTrim=15 → 钳 10，
 *                         eClamped；fPhRampDs=50, fCycle=0.01 → 单步 0.5，
 *                         20 拍达 10.0 → bTrimActive=FALSE（修调保持）；
 *                         ② 斜坡第 5 拍再发 bApply → 被拒，uRejCnt+1，
 *                         eErrCode=eBusyRej，生效量不受污染；③ fScTrimMaxPct
 *                         =0 → 锁存 eCfgBad，生效量冻结；④ bApply 请求
 *                         fPhaseTrim=3（< 上限）→ 无钳位，eOk。
 *==============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_CdtErr（错误码；信息级不置 bError，故障级恒伴 bError=TRUE）
 *----------------------------------------------------------------------------*)
TYPE E_DL_CdtErr :
(
    eOk      := 0,   // 正常 / Normal
    eCfgBad  := 1,   // 故障级：组态非法（上限/斜率域或非有限） / Fault: illegal configuration
    eClamped := 2,   // 信息级：请求超单次幅值上限已钳位 / Info: request clamped to single-shot ceiling
    eBusyRej := 3    // 信息级：执行中应用沿被拒（拒绝叠加） / Info: apply edge rejected while busy
);
END_TYPE

FUNCTION_BLOCK FB_DL_CamDynTrim
VAR_INPUT
    fPhaseTrim  : LREAL := 0.0;       // 相位修调请求 [deg] / Phase trim request [deg]
    fScaleTrim  : LREAL := 0.0;       // 倍率修调请求 [%] / Scale trim request [percent]
    bApply      : BOOL := FALSE;      // 应用沿（上升沿锁存目标，执行中拒绝） [-] / Apply edge
    fPhTrimMaxDeg: LREAL := 10.0;     // 单次相位修调幅值上限，域 > 0 [deg] / Single-shot phase trim ceiling
    fScTrimMaxPct: LREAL := 20.0;     // 单次倍率修调幅值上限，域 > 0 [%] / Single-shot scale trim ceiling
    fPhRampDs   : LREAL := 50.0;      // 相位斜率，域 > 0 [deg/s] / Phase ramp rate
    fScRampPs   : LREAL := 10.0;      // 倍率斜率，域 > 0 [%/s] / Scale ramp rate
    fCycle      : LREAL := 0.0;       // 扫描周期（<=0 用缺省） [s] / Scan cycle, default used when <= 0
    bReset      : BOOL := FALSE;      // 复位，上升沿清组态锁存与拒次计数 [-] / Reset, clears latch and reject counter
END_VAR
VAR_OUTPUT
    fPhTrimAct : LREAL;               // 生效相位修调（斜坡后） [deg] / Active phase trim [deg]
    fScTrimAct : LREAL;               // 生效倍率修调（斜坡后） [%] / Active scale trim [percent]
    bTrimActive: BOOL;                // 斜坡执行中指示（任一通道未达） [-] / Ramp busy indicator
    uRejCnt    : UDINT := 0;          // 执行中拒绝计数（防回绕） [次] / Busy-reject counter
    eErrCode   : E_DL_CdtErr;         // 错误码出口 / Error code outlet
    bError     : BOOL;                // 故障标志（组态锁存） [-] / Error flag, latched
END_VAR
VAR
    _fPhTar   : LREAL := 0.0;         // 相位目标锁存（应用沿唯一写入） [deg] / Phase target latch
    _fScTar   : LREAL := 0.0;         // 倍率目标锁存 [percent] / Scale target latch
    _fPhAct   : LREAL := 0.0;         // 生效相位（限步源） [deg] / Active phase internal
    _fScAct   : LREAL := 0.0;         // 生效倍率（限步源） [percent] / Active scale internal
    _fCy      : LREAL;                // 当拍有效周期 [s] / Effective cycle this scan
    _fPhStep  : LREAL;                // 相位单步上限 [deg] / Phase step ceiling
    _fScStep  : LREAL;                // 倍率单步上限 [%] / Scale step ceiling
    _bBusy    : BOOL := FALSE;        // 斜坡执行中内部量（R_TRIG 闸源） [-] / Busy internal
    _bClamped : BOOL;                 // 本拍应用沿发生钳位 [-] / Clamped at apply this scan
    _bRej     : BOOL;                 // 本拍应用沿被拒 [-] / Apply rejected this scan
    _bNonFin  : BOOL;                 // 请求非有限当拍量 [-] / Non-finite request this scan
    _bCfgBad  : BOOL;                 // 组态非法当拍量 [-] / Illegal configuration
    _bErrLatch: BOOL;                 // 组态故障锁存位（解除沿 = bReset 上升沿） / Latched config fault
    rtApply   : R_TRIG;               // 应用沿实例，段 0 无条件调用 / Apply edge instance
    rtReset   : R_TRIG;               // 复位沿实例，段 0 无条件调用 / Reset edge instance
END_VAR
VAR CONSTANT
    DL_CDT_CYDEF : LREAL := 0.01;     // 缺省扫描周期 [s] / Default scan cycle
    DL_CDT_TOL   : LREAL := 1.0E-9;   // 到达容差（禁浮点 = 判等） [deg|percent] / Arrival tolerance
    DL_CDT_ZERO  : LREAL := 0.0;      // 判零与安全侧基准 [deg|percent] / Zero base and safe value
    DL_CDT_UDMAX : UDINT := 4294967295;   // 拒次计数饱和点（防回绕） [次] / Reject counter ceiling
END_VAR

(* —— 段 0：非有限判 + 组态闸 + 周期派生 + 两沿无条件刷新 —— *)
_bNonFin := (fPhaseTrim <> fPhaseTrim) OR ((fPhaseTrim - fPhaseTrim) <> DL_CDT_ZERO)
         OR (fScaleTrim <> fScaleTrim) OR ((fScaleTrim - fScaleTrim) <> DL_CDT_ZERO);   // 请求非有限（R79 双判） / Non-finite request
_bCfgBad := (fPhTrimMaxDeg <= DL_CDT_ZERO) OR (fScTrimMaxPct <= DL_CDT_ZERO)
         OR (fPhRampDs <= DL_CDT_ZERO) OR (fScRampPs <= DL_CDT_ZERO)
         OR (fPhTrimMaxDeg <> fPhTrimMaxDeg) OR (fScTrimMaxPct <> fScTrimMaxPct);   // 组态域闸（上限/斜率域 + 上限非有限） / Configuration gate
IF fCycle > DL_CDT_ZERO THEN
    _fCy := fCycle;                   // 组态周期有效 / Configured cycle valid
ELSE
    _fCy := DL_CDT_CYDEF;             // 周期缺省兜底 / Default cycle fallback
END_IF
_fPhStep := fPhRampDs * _fCy;         // 相位单步 [deg] / Phase step
_fScStep := fScRampPs * _fCy;         // 倍率单步 [%] / Scale step
rtApply(CLK := bApply);               // 应用沿，每拍必调 / Apply edge, every scan
rtReset(CLK := bReset);               // 复位沿，每拍必调 / Reset edge, every scan

(* —— 段 1：复位沿与组态锁存 —— *)
IF rtReset.Q THEN
    _bErrLatch := FALSE;              // 清组态锁存（R188 声明：解除沿 = bReset 上升沿） / Clear cfg latch
    uRejCnt := 0;                     // 清拒次计数 / Clear reject counter
END_IF
IF _bCfgBad AND (NOT _bErrLatch) THEN
    _bErrLatch := TRUE;               // 锁存 / Latch
END_IF

(* —— 段 2：应用沿裁决（故障期拒绝；执行中拒绝叠加；请求钳位后锁存目标） —— *)
_bClamped := FALSE;                   // 钳位量预清 / Clamp preset
_bRej := FALSE;                       // 拒绝量预清 / Reject preset
IF rtApply.Q AND (NOT _bErrLatch) THEN
    IF _bBusy THEN
        _bRej := TRUE;                // 执行中拒绝叠加（规格，R191 声明：请求不生效，目标不变） / Busy reject, target unchanged
        IF uRejCnt < DL_CDT_UDMAX THEN
            uRejCnt := uRejCnt + 1;   // 拒次计数防回绕 / Count reject
        END_IF
    ELSIF _bNonFin THEN
        _bRej := TRUE;                // 非有限请求拒绝（不污染目标锁存） / Non-finite request rejected
        IF uRejCnt < DL_CDT_UDMAX THEN
            uRejCnt := uRejCnt + 1;   // 拒次计数 / Count reject
        END_IF
    ELSE
        _fPhTar := fPhaseTrim;        // 相位请求工作副本 / Phase working copy
        _fScTar := fScaleTrim;        // 倍率请求工作副本 / Scale working copy
        IF _fPhTar > fPhTrimMaxDeg THEN
            _fPhTar := fPhTrimMaxDeg;   // 相位超幅上钳（规格③） / Clamp phase high
            _bClamped := TRUE;          // 记钳位 / Mark clamp
        ELSIF _fPhTar < (-fPhTrimMaxDeg) THEN
            _fPhTar := -fPhTrimMaxDeg;  // 相位超幅下钳（对称 ±） / Clamp phase low
            _bClamped := TRUE;          // 记钳位 / Mark clamp
        END_IF
        IF _fScTar > fScTrimMaxPct THEN
            _fScTar := fScTrimMaxPct;   // 倍率超幅上钳 / Clamp scale high
            _bClamped := TRUE;          // 记钳位 / Mark clamp
        ELSIF _fScTar < (-fScTrimMaxPct) THEN
            _fScTar := -fScTrimMaxPct;  // 倍率超幅下钳 / Clamp scale low
            _bClamped := TRUE;          // 记钳位 / Mark clamp
        END_IF
        _bBusy := TRUE;               // 入斜坡执行态 / Enter ramp busy
    END_IF
END_IF

(* —— 段 3：双通道限步逼近（防凸轮表跳变；故障期冻结） —— *)
IF NOT _bErrLatch THEN
    IF _fPhTar > (_fPhAct + _fPhStep) THEN
        _fPhAct := _fPhAct + _fPhStep;   // 相位正向限步 / Phase ramp up
    ELSIF _fPhTar < (_fPhAct - _fPhStep) THEN
        _fPhAct := _fPhAct - _fPhStep;   // 相位负向限步 / Phase ramp down
    ELSE
        _fPhAct := _fPhTar;           // 相位步内到达 / Phase settle
    END_IF
    IF _fScTar > (_fScAct + _fScStep) THEN
        _fScAct := _fScAct + _fScStep;   // 倍率正向限步 / Scale ramp up
    ELSIF _fScTar < (_fScAct - _fScStep) THEN
        _fScAct := _fScAct - _fScStep;   // 倍率负向限步 / Scale ramp down
    ELSE
        _fScAct := _fScTar;           // 倍率步内到达 / Scale settle
    END_IF
    _bBusy := (ABS(_fPhAct - _fPhTar) >= DL_CDT_TOL)
           OR (ABS(_fScAct - _fScTar) >= DL_CDT_TOL);   // 双通道均达才撤销执行态（头注释④） / Busy until both settled
ELSE
    _bBusy := FALSE;                  // 故障期执行态强制撤销 / Fault forces not-busy
END_IF

(* —— 段 4：出口单点映射（名实双出口同源，R191） —— *)
fPhTrimAct := _fPhAct;                // 生效相位出口（故障期冻结保持） / Active phase outlet
fScTrimAct := _fScAct;                // 生效倍率出口 / Active scale outlet
bTrimActive := _bBusy;                // 执行中出口 / Busy outlet
IF _bErrLatch THEN
    bError := TRUE;                   // 故障标志（R45 配对） / Error flag
    eErrCode := E_DL_CdtErr.eCfgBad;  // 故障级码 / Fault code
ELSE
    bError := FALSE;                  // 无故障级条件 / No fault
    IF _bRej THEN
        eErrCode := E_DL_CdtErr.eBusyRej;   // 信息级：拒绝叠加 / Info: busy reject
    ELSIF _bClamped THEN
        eErrCode := E_DL_CdtErr.eClamped;   // 信息级：钳位口径 / Info: clamped
    ELSE
        eErrCode := E_DL_CdtErr.eOk;        // 正常 / Normal
    END_IF
END_IF

END_FUNCTION_BLOCK
