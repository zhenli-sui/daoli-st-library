(*==============================================================================
 * 组件名称 (Component)  : FB_DL_AxisScrewPitchComp
 * 所属子库 (Sublibrary) : DL_Motion
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（TRUNC / ABS），零厂商私有库
 * 功能描述 (Function)   : 丝杠螺距误差分段前馈补偿：误差表 aErrTable[0..nSegCnt]
 *                         给出均匀分段节点（段长 fSegLenMm，表长 = 段数 + 1，
 *                         一致性校验）处螺距误差（mm），段内线性插值：
 *                           idx  = TRUNC(fPosMm ÷ fSegLenMm)，钳位 [0, nSegCnt−1]
 *                           fFrac = fPosMm ÷ fSegLenMm − idx，钳位 [0,1]
 *                           fCompValMm = aErrTable[idx]
 *                                        + fFrac × (aErrTable[idx+1] − aErrTable[idx])
 *                         位置先钳入表覆盖域 [0, nSegCnt×fSegLenMm]（越域置
 *                         信息码 ePosClamped），段索引防越界钳位（规格指定）；
 *                         非有限位置输出 0 并置信息码 ePosNonFin（规格指定）。
 * 接口     (Interface)  : 输入 fPosMm 轴当前位置 [mm]、aErrTable 分段误差表
 *                         （定长 0..16，[mm]）、nSegCnt 有效段数（域 [1,16]）、
 *                         fSegLenMm 每段长度（域 > 0）、bReset 复位；
 *                         输出 fCompValMm 前馈补偿值（叠加到位置设定侧）
 *                         [mm]、eErrCode 错误码、bError 故障标志。
 * 边界     (Boundary)   : ① **属主边界（写死）：本件只算螺距误差补偿量，不写
 *                         位置指令、不接管反向间隙补偿**；间隙补偿归
 *                         `FB_DL_AxisBacklashComp`。
 *                         ② 表长一致性：nSegCnt 有效段数对应节点 0..nSegCnt
 *                         共 nSegCnt+1 个，超出定长 17（nSegCnt > 16）或
 *                         nSegCnt < 1 → 锁存故障（表长=段数+1 一致性校验，
 *                         规格指定），冻结输出 0。
 *                         ③ 位置域钳位：fPosMm < 0 钳 0、> nSegCnt×fSegLenMm
 *                         钳上界，置信息码 ePosClamped（量值方向可饱和）。
 *                         ④ 非有限判据（R79 双判）先行于一切换算：非有限时
 *                         输出 0、信息码 ePosNonFin，不污染插值。
 *                         ⑤ 组态闸：fSegLenMm <= 0 → 锁存故障（除数前置闸，
 *                         结构性无除零），冻结输出 0，解除沿 = bReset 上升沿。
 *                         ⑥ TRUNC 取整前位置已过非有限闸与域钳位（无溢出
 *                         取整路径）。
 *                         ⑦ 零全局耦合（无 GVL / VAR_EXTERNAL / 物理地址）。
 * 分工声明 (Scope)      : 与 `FB_DL_AxisBacklashComp` 分工：反向间隙（双区滞回）
 *                         归那件、螺距分段误差（单值表）归本件；与
 *                         `FB_DL_CamTableInterp` 分工：凸轮表插值归那件。
 * 来源标签 (Source Tag) : 自研线（分段线性插值为公开数值方法 clean-room）
 * 码表     (Codes)      : 本件不占用任何全局数字码位。出口为 LREAL 补偿值 +
 *                         ENUM 错误码；数字码位待主控收口阶段统一派号。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 索引钳位 + 表长一致性 + 除数前置闸 + 非有限先行
 *                         ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 N/A（无 ENUM 状态机） ｜ R7 ✓ 一 R_TRIG 段 0 无条件刷新
 * 修订历史 (Revision)   : 2026-11-20  v1.0.0  R50 首版（批次 2 · 序号 7）
 * 验收向量 (Acceptance) : ① fSegLenMm=10, nSegCnt=2, aErrTable=[0.0, 0.01, 0.03]
 *                         （mm）：fPosMm=5 → 段 0 半程 → 0.0 + 0.5×0.01 =
 *                         0.005 mm；fPosMm=15 → 段 1 半程 → 0.01 + 0.5×0.02
 *                         = 0.02 mm，均 eOk；② fPosMm=25 → 钳上界 20 → 段 1
 *                         终点 → 0.03 mm，ePosClamped；③ nSegCnt=0 → 锁存
 *                         eCfgBad，输出 0；④ fPosMm=NaN → 输出 0，
 *                         ePosNonFin。
 *==============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_SpcErr（错误码；信息级不置 bError，故障级恒伴 bError=TRUE）
 *----------------------------------------------------------------------------*)
TYPE E_DL_SpcErr :
(
    eOk         := 0,   // 正常 / Normal
    eCfgBad     := 1,   // 故障级：段数/段长组态非法（表长=段数+1 破坏） / Fault: segment config illegal
    ePosClamped := 2,   // 信息级：位置越表域已钳位 / Info: position clamped into table domain
    ePosNonFin  := 3    // 信息级：位置非有限，输出 0 / Info: position non-finite, output zero
);
END_TYPE

FUNCTION_BLOCK FB_DL_AxisScrewPitchComp
VAR_INPUT
    fPosMm    : LREAL := 0.0;                  // 轴当前位置 [mm] / Axis present position [mm]
    aErrTable : ARRAY[0..16] OF LREAL;         // 分段误差表（节点 0..nSegCnt） [mm] / Segmented error table [mm]
    nSegCnt   : UDINT := 8;                    // 有效段数（表长 = 段数+1），域 [1,16] [段] / Valid segment count
    fSegLenMm : LREAL := 10.0;                 // 每段长度，域 > 0 [mm] / Segment length [mm]
    bReset    : BOOL := FALSE;                 // 复位，上升沿清组态故障锁存 [-] / Reset, rising edge clears cfg latch
END_VAR
VAR_OUTPUT
    fCompValMm : LREAL;                        // 前馈补偿值（叠加位置设定侧） [mm] / Feedforward compensation [mm]
    eErrCode   : E_DL_SpcErr;                  // 错误码出口 / Error code outlet
    bError     : BOOL;                         // 故障标志（组态锁存） [-] / Error flag, latched
END_VAR
VAR
    _nIdx     : DINT;                          // 段索引（钳位后，域 [0, nSegCnt−1]） [-] / Clamped segment index
    _fScaled  : LREAL;                         // 位置按段长标度值（无量纲段数） [段] / Position scaled by segment length
    _fFrac    : LREAL;                         // 段内分数（钳位 [0,1]） [-] / In-segment fraction
    _fPosUse  : LREAL;                         // 钳入表域后的位置 [mm] / Position clamped into domain
    _fPosMax  : LREAL;                         // 表覆盖域上界 = nSegCnt×fSegLenMm [mm] / Table domain ceiling
    _bNonFin  : BOOL;                          // 位置非有限当拍量 [-] / Position non-finite this scan
    _bClamped : BOOL;                          // 本拍发生位置钳位 [-] / Position clamped this scan
    _bCfgBad  : BOOL;                          // 组态非法当拍量 [-] / Illegal configuration this scan
    _bErrLatch: BOOL;                          // 组态故障锁存位（解除沿 = bReset 上升沿） / Latched config fault
    rtReset   : R_TRIG;                        // 复位沿实例，段 0 无条件调用 / Reset edge instance
END_VAR
VAR CONSTANT
    DL_SPC_NMAX  : DINT := 16;                 // 段数上限（表定长 0..16 共 17 节点） [段] / Segment count ceiling
    DL_SPC_NMIN  : DINT := 1;                  // 段数下限 [段] / Segment count floor
    DL_SPC_ZERO  : LREAL := 0.0;               // 域下界与判零基准 [mm] / Domain floor and zero base
    DL_SPC_ONE   : LREAL := 1.0;               // 分数钳位上界 [-] / Fraction ceiling
END_VAR

(* —— 段 0：非有限判 + 组态闸 + 沿刷新 —— *)
_bNonFin := (fPosMm <> fPosMm) OR ((fPosMm - fPosMm) <> DL_SPC_ZERO);   // 位置非有限（R79 双判） / Position non-finite
_bCfgBad := (fSegLenMm <= DL_SPC_ZERO);        // 段长域闸（除数前置） / Segment length gate
IF (UDINT_TO_DINT(nSegCnt) < DL_SPC_NMIN) OR (UDINT_TO_DINT(nSegCnt) > DL_SPC_NMAX) THEN
    _bCfgBad := TRUE;                          // 表长=段数+1 一致性破坏（规格②） / Table length consistency violated
END_IF
rtReset(CLK := bReset);                        // 复位沿，每拍必调 / Reset edge, every scan

(* —— 段 1：复位沿与组态锁存 —— *)
IF rtReset.Q THEN
    _bErrLatch := FALSE;                       // 清组态锁存（R188 声明：解除沿 = bReset 上升沿） / Clear cfg latch
END_IF
IF _bCfgBad AND (NOT _bErrLatch) THEN
    _bErrLatch := TRUE;                        // 锁存 / Latch
END_IF

(* —— 段 2：位置域钳位（故障期跳过；非有限跳过） —— *)
_bClamped := FALSE;                            // 钳位量预清 / Clamp preset
_fPosUse := DL_SPC_ZERO;                       // 安全侧起步 0 / Safe-side start zero
_fPosMax := UDINT_TO_LREAL(nSegCnt) * fSegLenMm;   // 表域上界 [mm] / Domain ceiling
IF (NOT _bErrLatch) AND (NOT _bNonFin) THEN
    _fPosUse := fPosMm;                        // 位置工作副本 / Position working copy
    IF _fPosUse < DL_SPC_ZERO THEN
        _fPosUse := DL_SPC_ZERO;               // 下越域钳 0 / Clamp low to zero
        _bClamped := TRUE;                     // 记钳位 / Mark clamp
    ELSIF _fPosUse > _fPosMax THEN
        _fPosUse := _fPosMax;                  // 上越域钳上界 / Clamp high to ceiling
        _bClamped := TRUE;                     // 记钳位 / Mark clamp
    END_IF
END_IF

(* —— 段 3：分段线性插值（索引与分数双重钳位，防越界） —— *)
IF (NOT _bErrLatch) AND (NOT _bNonFin) THEN
    _fScaled := _fPosUse / fSegLenMm;          // 标度值（除数已过闸，结构性无除零） / Scaled value
    _nIdx := LREAL_TO_DINT(TRUNC(_fScaled));   // 段索引取整（域已钳，无溢出） / Segment index by TRUNC
    IF _nIdx > (UDINT_TO_DINT(nSegCnt) - 1) THEN
        _nIdx := UDINT_TO_DINT(nSegCnt) - 1;   // 索引上钳（规格：防越界钳位） / Clamp index high
    END_IF
    IF _nIdx < 0 THEN
        _nIdx := 0;                            // 索引下钳 / Clamp index low
    END_IF
    _fFrac := _fScaled - DINT_TO_LREAL(_nIdx);   // 段内分数（索引升位实数化） / In-segment fraction
    IF _fFrac < DL_SPC_ZERO THEN
        _fFrac := DL_SPC_ZERO;                 // 分数下钳 / Clamp fraction low
    END_IF
    IF _fFrac > DL_SPC_ONE THEN
        _fFrac := DL_SPC_ONE;                  // 分数上钳 / Clamp fraction high
    END_IF
    fCompValMm := aErrTable[_nIdx] + _fFrac * (aErrTable[_nIdx + 1] - aErrTable[_nIdx]);   // 段内线性插值（_nIdx+1 <= nSegCnt 表内） / Linear interpolation
ELSE
    fCompValMm := DL_SPC_ZERO;                 // 故障/非有限安全侧输出 0（规格④） / Safe-side zero output
END_IF

(* —— 段 4：出口单点映射（错误码归约，R191） —— *)
IF _bErrLatch THEN
    bError := TRUE;                            // 故障标志（R45 配对） / Error flag
    eErrCode := E_DL_SpcErr.eCfgBad;           // 故障级码 / Fault code
ELSE
    bError := FALSE;                           // 无故障级条件 / No fault
    IF _bNonFin THEN
        eErrCode := E_DL_SpcErr.ePosNonFin;    // 信息级：非有限口径 / Info: non-finite
    ELSIF _bClamped THEN
        eErrCode := E_DL_SpcErr.ePosClamped;   // 信息级：越域钳位口径 / Info: clamped
    ELSE
        eErrCode := E_DL_SpcErr.eOk;           // 正常 / Normal
    END_IF
END_IF

END_FUNCTION_BLOCK
