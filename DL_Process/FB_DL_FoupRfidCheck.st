(*==============================================================================
 * 组件名称 (Component)  : FB_DL_FoupRfidCheck
 * 所属子库 (Sublibrary) : DL_Process
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG / LEN），零厂商私有库
 * 功能描述 (Function)   : FOUP 身份校验与配方放行。
 *                         装载口读 FOUP 身份码后，按**固定顺序的四段校验链**裁决是否放行加工：
 *                           ① 身份码非空（空码 = 没读到，不放行）；
 *                           ② 身份码长度在 [uIdMinLen, uIdMaxLen] 内（格式闸，防半截码/粘码）；
 *                           ③ 在机配方非空（无配方不许放行）；
 *                           ④ 在机配方 = 期望配方（配方一致性，逐字符比对）。
 *                         四段任一失败即锁存失败原因，**且首因不覆盖**：第一个失败段决定 eCause，
 *                         后续段不再改写（R190 归因唯一）；放行在四段全过时才给单拍脉冲。
 *                         验收向量：
 *                           ① FOUP='F0012'，配方 'RCP-A' = 期望 'RCP-A' → bPass 单拍
 *                           ② FOUP=''                              → eIdEmpty 锁存
 *                           ③ FOUP='F01'（长度 < 4）                → eIdFormat 锁存
 *                           ④ 配方 'RCP-B' ≠ 期望 'RCP-A'          → eRecipeMismatch 锁存
 *                           ⑤ 启动后 tReadTo 内无读码完成             → eReadTimeout 锁存
 * 接口     (Interface)  : 入 bStartCheck 校验启动沿、bReadDone 读码完成沿、sFoupId FOUP 身份码、
 *                         sRecipeId 在机配方号、sExpectedRecipe 期望配方号、uIdMinLen / uIdMaxLen
 *                         身份码长度域、tReadTo 读码超时、bReset 复位沿；
 *                         出 bPass 放行脉冲（单拍）、bCheckFailed 校验失败锁存、bWaiting 等读码中、
 *                         eState 相、eCause 成因、bError 故障标志。
 * 边界     (Boundary)   : ① **属主边界（写死）：本件只做"身份 + 配方"校验链与放行脉冲，
 *                         不驱动装载口门/夹紧、不切配方、不写 MES 账**（分别属门件、配方件、通讯件）；
 *                         ② **长度域闸**：uIdMinLen ≥ 1 且 uIdMaxLen ≥ uIdMinLen 且 uIdMaxLen ≤ 15，
 *                         违反即锁存 eCfgIllegal（长度域非法会让格式闸静默失效，R179）；
 *                         ③ **超时 TON 冻结**：tonRead 的 IN 串 (NOT _bFault)，故障期不累计，
 *                         复位同拍不会立即重锁（R252）；TON 段 0 无条件调用；
 *                         ④ **锁存解除式**：bCheckFailed 与 eFault 仅由 bReset 上升沿解除
 *                         （R228B 唯一迁出）；bReset 为外部引脚、恒可达；
 *                         ⑤ **等待相退出条件 ≥2**：读码完成沿 ∨ 超时（R98/R129），
 *                         并补一条"启动命令已撤销 → 回待机"（进相前置消失出口）；
 *                         ⑥ 零全局耦合、零物理地址。
 * 分工声明 (Scope)      : 本件只管"FOUP 身份与配方放行校验"。不接管：载具路径路由
 *                         （属 FB_DL_RfidTrayRoute）、配方参数下发与切换（属配方件）、
 *                         FOUP 内部晶圆计数校验（属片盒件）。
 * 来源标签 (Source Tag) : ROADMAP 空勾真缺口 P1（FOUP 配方放行，自研 clean-room）
 * 码表     (Codes)      : 本件不占用任何全局数字码位（零码位范式 R297）；诊断由 BOOL + ENUM 出口承担。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 长度域闸 + 空串闸 + 超时 + 等待相双出口 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 ✓ ENUM+CASE 含 ELSE 兜底 ｜ R7 ✓ TON/R_TRIG 段 0 无条件刷新
 * 修订历史 (Revision)   : 2026-11-19  v1.0.0  R47 首版（批次 3 · 序号 12）
 *==============================================================================*)

TYPE E_DL_FrcState :
(
    eIdle  := 0,    // 待机相（等校验启动） / Idle, awaiting a check request
    eWait  := 10,   // 等读码相（读码窗内） / Waiting for the tag read
    eFault := 90    // 故障相（等复位） / Fault, awaiting reset
);
END_TYPE

TYPE E_DL_FrcCause :
(
    eNone          := 0,   // 无异常 / No anomaly
    eIdEmpty       := 1,   // 身份码空（锁存） / Empty identity, latched
    eIdFormat      := 2,   // 身份码长度越域（锁存） / Identity length out of range, latched
    eRecipeEmpty   := 3,   // 在机配方空（锁存） / Empty on-machine recipe, latched
    eRecipeMismatch:= 4,   // 配方不一致（锁存） / Recipe mismatch, latched
    eReadTimeout   := 5,   // 读码超时（锁存） / Read timeout, latched
    eCfgIllegal    := 6,   // 组态非法（长度域/超时越域） / Illegal configuration
    ePhaseBad      := 7    // 非法相位兜底 / Illegal phase fallback
);
END_TYPE

FUNCTION_BLOCK FB_DL_FoupRfidCheck
VAR_INPUT
    bStartCheck    : BOOL := FALSE;      // 校验启动沿 [-] / Check-start edge
    bReadDone      : BOOL := FALSE;      // 读码完成沿 [-] / Tag-read edge
    sFoupId        : STRING[15] := '';   // FOUP 身份码（≤15 字符） [-] / FOUP identity, up to 15 chars
    sRecipeId      : STRING[15] := '';   // 在机配方号 [-] / On-machine recipe identifier
    sExpectedRecipe: STRING[15] := '';   // 期望配方号 [-] / Expected recipe identifier
    uIdMinLen      : UINT := 4;          // 身份码最小长度，域 1..15 [字符] / Minimum identity length
    uIdMaxLen      : UINT := 15;         // 身份码最大长度，域 ≥ 最小长度 [字符] / Maximum identity length
    tReadTo        : TIME := T#5S;       // 读码超时，域 > T#0S [ms] / Read timeout, > T#0S
    bReset         : BOOL := FALSE;      // 故障复位沿 [-] / Fault reset edge
END_VAR
VAR_OUTPUT
    bPass       : BOOL := FALSE;                         // 放行脉冲（单拍，四段全过） [-] / Pass pulse, single scan
    bCheckFailed: BOOL := FALSE;                         // 校验失败锁存（等复位） [-] / Check failure, latched
    bWaiting    : BOOL := FALSE;                         // 等读码中 [-] / Waiting for the tag read
    eState      : E_DL_FrcState := E_DL_FrcState.eIdle;  // 相出口 [-] / Phase outlet
    eCause      : E_DL_FrcCause := E_DL_FrcCause.eNone;  // 成因出口（R190 归因唯一） [-] / Cause outlet
    bError      : BOOL := FALSE;                         // 故障标志（仅故障级成因） [-] / Error flag, fault level only
END_VAR
VAR
    _eState   : E_DL_FrcState := E_DL_FrcState.eIdle;    // 内部相（CASE 唯一写入目标） / Internal phase
    _eCause   : E_DL_FrcCause := E_DL_FrcCause.eNone;    // 成因锁存量 / Latched cause
    _bFault   : BOOL := FALSE;                           // 故障锁存位 / Latched fault bit
    _bFail    : BOOL := FALSE;                           // 校验失败锁存位 / Latched check-failure bit
    _bPass    : BOOL := FALSE;                           // 放行脉冲内部位（单拍） / Internal pass pulse
    _bCfgBad  : BOOL := FALSE;                           // 组态非法当拍量 / Illegal configuration this scan
    _iLen     : INT := 0;                                // 身份码实际长度 [字符] / Actual identity length
    tonRead   : TON;                                     // 读码超时实例，段 0 无条件调用 / Read timeout instance
    rtStart   : R_TRIG;                                  // 启动沿实例，段 0 无条件调用 / Start edge instance
    rtRead    : R_TRIG;                                  // 读码沿实例，段 0 无条件调用 / Read edge instance
    rtReset   : R_TRIG;                                  // 复位沿实例，段 0 无条件调用 / Reset edge instance
END_VAR
VAR CONSTANT
    DL_FRC_LEN_MAX : UINT := 15;         // 身份码长度硬上限（与 STRING[15] 同源） [字符] / Hard length ceiling
END_VAR

(* —— 段 0：组态闸 + TON 与三沿无条件周期刷新（R228A；IN 串故障否决，R252） —— *)
_bCfgBad := (uIdMinLen < 1) OR (uIdMaxLen < uIdMinLen) OR (uIdMaxLen > DL_FRC_LEN_MAX)   // 长度域须满足 1 ≤ min ≤ max ≤ 15
         OR (tReadTo <= T#0S);                                                             // 超时须为正
rtStart(CLK := bStartCheck);                                                               // 启动沿 / Start edge
rtRead(CLK := bReadDone);                                                                  // 读码沿 / Read edge
rtReset(CLK := bReset);                                                                    // 复位沿 / Reset edge
tonRead(IN := (_eState = E_DL_FrcState.eWait) AND (NOT _bFault), PT := tReadTo);            // 读码超时（等读码相派生） / Read timeout

(* —— 段 1：单拍量预清零（锁存量 _eCause/_bFault/_bFail 不入清单，R107） —— *)
_bPass := FALSE;                                                                           // 放行脉冲预清 / Pass pulse preset
bError := FALSE;                                                                           // 故障标志预清（R45 配对） / Error preset
_iLen  := 0;                                                                               // 长度工作值预清 / Length working value preset

(* —— 段 2：组态闸（非法即锁存故障级） —— *)
IF _bCfgBad THEN
    _eCause := E_DL_FrcCause.eCfgIllegal;                                                  // 归因：组态非法 / Cause: illegal configuration
    _bFault := TRUE;                                                                       // 锁存 / Latch
    _eState := E_DL_FrcState.eFault;                                                       // 入故障相 / Enter fault phase
END_IF

(* —— 段 3：迁出链（bReset 上升沿：清双锁存，R228B） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                                                                      // 清故障锁存 / Clear fault latch
    _bFail  := FALSE;                                                                      // 清校验失败锁存 / Clear check-failure latch
    _eCause := E_DL_FrcCause.eNone;                                                        // 清成因 / Clear cause
    _eState := E_DL_FrcState.eIdle;                                                        // 回待机相 / Back to idle
END_IF

(* —— 段 4：相迁移（校验链；等待相三出口：读码沿 ∨ 超时 ∨ 启动撤销） —— *)
IF (NOT _bFault) AND (NOT _bCfgBad) THEN
    CASE _eState OF

    E_DL_FrcState.eIdle:
        IF rtStart.Q THEN
            _eState := E_DL_FrcState.eWait;                                                // 启动沿进等读码相 / Enter the wait phase
        END_IF

    E_DL_FrcState.eWait:
        IF rtRead.Q THEN
            (* —— 四段校验链（首因不覆盖：命中即锁存并停判） —— *)
            _iLen := LEN(sFoupId);                                                         // 取身份码长度 / Identity length
            IF _iLen = 0 THEN
                _bFail  := TRUE;                                                           // 失败锁存 / Latch the failure
                _eCause := E_DL_FrcCause.eIdEmpty;                                         // 首因：身份码空 / First cause: empty identity
            ELSIF (_iLen < UINT_TO_INT(uIdMinLen)) OR (_iLen > UINT_TO_INT(uIdMaxLen)) THEN
                _bFail  := TRUE;                                                           // 失败锁存 / Latch the failure
                _eCause := E_DL_FrcCause.eIdFormat;                                        // 首因：长度越域 / First cause: length out of range
            ELSIF LEN(sRecipeId) = 0 THEN
                _bFail  := TRUE;                                                           // 失败锁存 / Latch the failure
                _eCause := E_DL_FrcCause.eRecipeEmpty;                                     // 首因：在机配方空 / First cause: empty recipe
            ELSIF sRecipeId = sExpectedRecipe THEN
                _bPass  := TRUE;                                                           // 四段全过：放行脉冲（内部位） / All four checks passed
            ELSE
                _bFail  := TRUE;                                                           // 失败锁存 / Latch the failure
                _eCause := E_DL_FrcCause.eRecipeMismatch;                                  // 首因：配方不一致 / First cause: recipe mismatch
            END_IF

            IF _bFail THEN
                _bFault := TRUE;                                                           // 故障锁存 / Latch the fault
                _eState := E_DL_FrcState.eFault;                                           // 入故障相 / Enter fault phase
            ELSE
                _eState := E_DL_FrcState.eIdle;                                            // 放行后回待机相 / Back to idle after the pass
            END_IF
        ELSIF tonRead.Q THEN
            _bFail  := TRUE;                                                               // 读码超时：失败锁存 / Read timeout: latch the failure
            _eCause := E_DL_FrcCause.eReadTimeout;                                         // 首因：读码超时 / First cause: read timeout
            _bFault := TRUE;                                                               // 故障锁存 / Latch the fault
            _eState := E_DL_FrcState.eFault;                                               // 入故障相 / Enter fault phase
        ELSIF NOT bStartCheck THEN
            _eState := E_DL_FrcState.eIdle;                                                // 启动撤销：进相前置消失，回待机（出口 3，R129） / Start withdrawn, back to idle
        END_IF

    E_DL_FrcState.eFault:
        ;                                                                                  // 故障相：仅等复位沿 / Wait for the reset edge only

    ELSE
        _eCause := E_DL_FrcCause.ePhaseBad;                                                // 归因：非法相位 / Cause: illegal phase
        _bFault := TRUE;                                                                   // 锁存 / Latch
        _eState := E_DL_FrcState.eFault;                                                   // 强拉故障相 / Force fault phase

    END_CASE
END_IF

(* —— 段 5：出口单点映射（名实双出口，R191） —— *)
bPass        := _bPass;                                                                    // 放行脉冲出口 / Pass pulse outlet
bCheckFailed := _bFail;                                                                     // 校验失败出口 / Check-failure outlet
bWaiting     := (_eState = E_DL_FrcState.eWait);                                            // 等读码中出口 / Waiting outlet
eState       := _eState;                                                                    // 相出口 / Phase outlet
eCause       := _eCause;                                                                    // 成因出口 / Cause outlet
bError       := _bFault;                                                                    // 故障标志 / Error flag

END_FUNCTION_BLOCK
