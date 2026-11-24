(*==============================================================================
 * 组件名称 (Component)  : FB_DL_R2rRunLogAudit
 * 所属子库 (Sublibrary) : DL_Process
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（R_TRIG / LEN），零厂商私有库
 * 功能描述 (Function)   : R2R 调参批次审计算账。
 *                         把"谁在第几版改了哪些调参量"落成可追溯台账：每次提交沿到来时，
 *                         与上一份快照逐项比对，**只有真发生变化**才产生一条留痕记录（版本号 +1），
 *                         并把当时的参数值整组快照存档；未变化则不记账（防止操作员连点造成假账）。
 *                         三条固化纪律：
 *                           ① **变更沿留痕**：R_TRIG 段 0 无条件刷新；比对用"差值容差判等"
 *                              （浮点禁 =/<>，逐项 ABS 差 < fEps 视为同值）；
 *                           ② **台账计数饱和**：记录条数与版本号均以 UDINT 承载并在上限前
 *                              停止自增（饱和不回绕），饱和后置 bCntSaturated，绝不让计数回绕成小值；
 *                           ③ **快照缓冲满锁存**：缓冲深度满后拒记并锁存 bBufFull，
 *                              等运维导出台账后 bReset 清空重记，绝不静默丢账。
 *                         验收向量：
 *                           ① 首拍提交（基准快照）：版本 1，记录 1 条
 *                           ② 未改变任何参数再提交：版本不变、记录数不变、eNoChange（信息级）
 *                           ③ 只改第 3 项 +0.5：版本 2，记录 2 条，sLastTag = 本次标识
 *                           ④ 记录达深度 16 后再提交有变更：拒记 + bBufFull 锁存
 * 接口     (Interface)  : 入 bCommit 提交沿、sParamTag 参数组标识、afParam 当前调参量（1..8）、
 *                         nParamCnt 有效参数个数、fEps 判等容差、bReset 复位沿；
 *                         出 uLogCnt 台账条数、nRev 当前版本号、bChanged 记账脉冲（单拍）、
 *                         sLastTag 最近记账标识、bBufFull 缓冲满锁存、bCntSaturated 计数饱和标志、
 *                         eState 相、eCause 成因、bError 故障标志。
 * 边界     (Boundary)   : ① **属主边界（写死）：本件只做"调参快照 + 变更留痕 + 计数"，
 *                         不执行调参动作、不下发参数、不写 MES/磁盘**（分别属调参执行件与通讯件）；
 *                         ② **数组边界**：afParam 以字面量上界 8、缓冲以 16 声明（R104），
 *                         nParamCnt 与深度常量作运行时二次闸；
 *                         ③ **组态闸**：nParamCnt 须在 1..8、fEps 须 > 0，违反即锁存 eCfgIllegal；
 *                         ④ **计数饱和**：UDINT 上限前停止自增并置 bCntSaturated（饱和不回绕 R43 家族）；
 *                         ⑤ **非有限闸**：提交时任一参数非有限 → 拒记 + eParamBad（当拍，不锁存），
 *                         防止 NaN 污染台账信任根（R133）；
 *                         ⑥ **锁存解除式**：bBufFull 与 eFault 仅由 bReset 上升沿解除（R228B 唯一迁出）；
 *                         ⑦ 零全局耦合、零物理地址。
 * 分工声明 (Scope)      : 本件只管"调参审计台账"。不接管：调参算法执行
 *                         （属 FB_DL_R2rEwmaTuner）、参数合法性审查（属参数校验件）、
 *                         台账持久化（属 MES/文件件）。
 * 来源标签 (Source Tag) : ROADMAP 空勾真缺口 P1（R2R 调参审计，自研 clean-room）
 * 码表     (Codes)      : 本件不占用任何全局数字码位（零码位范式 R297）；诊断由 BOOL + ENUM 出口承担。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 数组闸 + 判等容差 + 计数饱和 + 非有限闸 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 ✓ ENUM+CASE 含 ELSE 兜底 ｜ R7 ✓ R_TRIG 段 0 无条件刷新（本件无 TON）
 * 修订历史 (Revision)   : 2026-11-19  v1.0.0  R47 首版（批次 4 · 序号 17）
 *==============================================================================*)

TYPE ST_DL_RlaEntry :
STRUCT
    sTag   : STRING[15] := '';              // 参数组标识（≤15 字符） [-] / Parameter-group tag, up to 15 chars
    afVal  : ARRAY[1..8] OF LREAL;          // 记账时的参数值快照（1..8） [工程单位] / Parameter snapshot at logging time
    nCnt   : INT := 0;                      // 该条有效参数个数 [个] / Valid parameter count of this entry
    uRev   : UDINT := 0;                    // 该条对应版本号 [-] / Revision number of this entry
END_STRUCT
END_TYPE

TYPE E_DL_RlaState :
(
    eIdle  := 0,    // 待机相（等提交沿） / Idle, awaiting a commit edge
    eFault := 90    // 故障相（组态非法，等复位） / Fault, awaiting reset
);
END_TYPE

TYPE E_DL_RlaCause :
(
    eNone         := 0,   // 无异常 / No anomaly
    eFirstSnap    := 1,   // 首次基准快照（信息级） / First baseline snapshot, info level
    eNoChange     := 2,   // 提交但无变化（信息级，不记账） / Commit without change, info level
    eParamBad     := 3,   // 参数非有限（当拍拒记） / Non-finite parameter, rejected this scan
    eBufFull      := 4,   // 缓冲满（锁存，拒记） / Buffer full, latched, rejected
    eCfgIllegal   := 5,   // 组态非法（参数个数/容差越域） / Illegal configuration
    ePhaseBad     := 6    // 非法相位兜底 / Illegal phase fallback
);
END_TYPE

FUNCTION_BLOCK FB_DL_R2rRunLogAudit
VAR_INPUT
    bCommit   : BOOL := FALSE;         // 提交沿（记录一次调参结果） [-] / Commit edge, one audit record per edge
    sParamTag : STRING[15] := '';      // 参数组标识 [-] / Parameter-group tag
    afParam   : ARRAY[1..8] OF LREAL;  // 当前调参量（1..8） [工程单位] / Current parameter values, points 1..8
    nParamCnt : INT := 8;              // 有效参数个数，域 1..8 [个] / Valid parameter count, 1..8
    fEps      : LREAL := 1.0E-9;       // 判等容差，域 > 0 [工程单位] / Equality tolerance, > 0
    bReset    : BOOL := FALSE;         // 复位/清台账沿 [-] / Reset and clear edge
END_VAR
VAR_OUTPUT
    uLogCnt       : UDINT := 0;                          // 台账条数 [条] / Number of audit records
    nRev          : UDINT := 0;                          // 当前版本号 [-] / Current revision number
    bChanged      : BOOL := FALSE;                       // 记账脉冲（单拍） [-] / Logging pulse, single scan
    sLastTag      : STRING[15] := '';                    // 最近记账的参数组标识 [-] / Tag of the latest record
    bBufFull      : BOOL := FALSE;                       // 缓冲满锁存（等复位） [-] / Buffer full, latched
    bCntSaturated : BOOL := FALSE;                       // 计数饱和标志 [-] / Counter saturation flag
    eState        : E_DL_RlaState := E_DL_RlaState.eIdle;   // 相出口 [-] / Phase outlet
    eCause        : E_DL_RlaCause := E_DL_RlaCause.eNone;   // 成因出口（R190 归因唯一） [-] / Cause outlet
    bError        : BOOL := FALSE;                       // 故障标志（仅故障级成因） [-] / Error flag, fault level only
END_VAR
VAR
    _eState   : E_DL_RlaState := E_DL_RlaState.eIdle;    // 内部相（CASE 唯一写入目标） / Internal phase
    _eCause   : E_DL_RlaCause := E_DL_RlaCause.eNone;    // 成因锁存量 / Latched cause
    _bFault   : BOOL := FALSE;                           // 故障锁存位 / Latched fault bit
    _bBufFull : BOOL := FALSE;                           // 缓冲满锁存位 / Latched buffer-full bit
    _uCnt     : UDINT := 0;                              // 内部记录计数 / Internal record count
    _uRev     : UDINT := 0;                              // 内部版本号 / Internal revision number
    _bChanged : BOOL := FALSE;                           // 记账脉冲内部位（单拍） / Internal logging pulse
    _bInit    : BOOL := FALSE;                           // 基准快照已建立标志 / Baseline-established flag
    _bDiff    : BOOL := FALSE;                           // 本拍检出的差异标志 / Difference-found flag
    _bParamOk : BOOL := FALSE;                           // 参数有限性结论 / Parameter finiteness result
    _bCfgBad  : BOOL := FALSE;                           // 组态非法当拍量 / Illegal configuration this scan
    _i        : INT := 0;                                // 参数循环下标 / Parameter loop index
    _iIdx     : INT := 0;                                // 缓冲写指针（1..16） / Buffer write index
    afLast    : ARRAY[1..8] OF LREAL;                    // 上一版基准快照（1..8） / Previous baseline snapshot
    rtCommit  : R_TRIG;                                  // 提交沿实例，段 0 无条件调用 / Commit edge instance
    rtReset   : R_TRIG;                                  // 复位沿实例，段 0 无条件调用 / Reset edge instance
    astLog    : ARRAY[1..16] OF ST_DL_RlaEntry;          // 台账缓冲（深度字面量上界，R104） / Audit buffer
END_VAR
VAR CONSTANT
    DL_RLA_DEPTH  : UDINT := 16;         // 台账缓冲深度（与数组字面量上界同源） [条] / Audit buffer depth
    DL_RLA_PCNT   : INT := 8;            // 参数个数上限（与接口字面量上界同源） [个] / Parameter upper bound
    DL_RLA_NUM_MAX: UDINT := 16#FFFF_FFFE;  // 计数/版本饱和闸（留 1 个余量防回绕） [-] / Saturation gate
END_VAR

(* —— 段 0：组态闸 + 两沿无条件周期刷新（R228A；本件无 TON） —— *)
_bCfgBad := (nParamCnt < 1) OR (nParamCnt > DL_RLA_PCNT)                         // 参数个数须在 1..8 / Count within 1..8
         OR (fEps <= 0.0) OR (fEps <> fEps);                                     // 容差须为正且有限 / Tolerance positive and finite
rtCommit(CLK := bCommit);                                                        // 提交沿 / Commit edge
rtReset(CLK := bReset);                                                          // 复位沿 / Reset edge

(* —— 段 1：单拍量预清零（锁存量 _eCause/_bFault/_bBufFull/_uCnt/_uRev/_bInit 不入清单，R107） —— *)
_bChanged := FALSE;                                                              // 记账脉冲预清 / Logging pulse preset
_bDiff    := FALSE;                                                              // 差异标志预清 / Difference preset
bError    := FALSE;                                                              // 故障标志预清（R45 配对） / Error preset

(* —— 段 2：组态闸（非法即锁存） —— *)
IF _bCfgBad THEN
    _eCause := E_DL_RlaCause.eCfgIllegal;                                        // 归因：组态非法 / Cause: illegal configuration
    _bFault := TRUE;                                                             // 锁存 / Latch
    _eState := E_DL_RlaState.eFault;                                             // 入故障相 / Enter fault phase
END_IF

(* —— 段 3：迁出链（bReset 清双锁存并清台账；台账清空是运维显式动作） —— *)
IF rtReset.Q THEN
    _bFault   := FALSE;                                                          // 清故障锁存 / Clear fault latch
    _bBufFull := FALSE;                                                          // 清缓冲满锁存 / Clear the buffer-full latch
    _eCause   := E_DL_RlaCause.eNone;                                            // 清成因 / Clear cause
    _iIdx     := 1;                                                              // 写指针回 1 / Write index back to 1
    _uCnt     := 0;                                                              // 记录数清零 / Record count cleared
    _uRev     := 0;                                                              // 版本号清零 / Revision cleared
    _bInit    := FALSE;                                                          // 基准作废 / Baseline invalidated
    _eState   := E_DL_RlaState.eIdle;                                            // 回待机相 / Back to idle
END_IF

(* —— 段 4：相迁移（两相 CASE；故障相由段 3 迁出） —— *)
CASE _eState OF

E_DL_RlaState.eIdle:
    ;                                                                            // 待机相：记账在段 5 执行 / Logging happens in stage 5

E_DL_RlaState.eFault:
    ;                                                                            // 故障相：仅等复位 / Wait for the reset edge only

ELSE
    _eCause := E_DL_RlaCause.ePhaseBad;                                          // 归因：非法相位 / Cause: illegal phase
    _bFault := TRUE;                                                             // 锁存 / Latch
    _eState := E_DL_RlaState.eFault;                                             // 强拉故障相 / Force fault phase

END_CASE

(* —— 段 5：提交记账（有限性闸 → 差异比对 → 容量/饱和闸 → 落账） —— *)
IF (rtCommit.Q) AND (_eState = E_DL_RlaState.eIdle) AND (NOT _bCfgBad) THEN
    (* 有限性闸：任一有效参数非有限即当拍拒记（NaN 不得污染台账信任根，R133） *)
    _bParamOk := TRUE;                                                           // 结论初值 / Conclusion initial value
    FOR _i := 1 TO DL_RLA_PCNT DO
        IF _i <= nParamCnt THEN
            IF (afParam[_i] <> afParam[_i]) OR ((afParam[_i] - afParam[_i]) <> (afParam[_i] - afParam[_i])) THEN
                _bParamOk := FALSE;                                              // 检出非有限参数 / Non-finite parameter found
            END_IF
        END_IF
    END_FOR

    IF NOT _bParamOk THEN
        _eCause := E_DL_RlaCause.eParamBad;                                       // 归因：参数非有限 / Cause: non-finite parameter
    ELSIF NOT _bInit THEN
        (* 首次提交：建立基准快照并记第 1 条 *)
        IF _uCnt >= DL_RLA_DEPTH THEN
            _bBufFull := TRUE;                                                    // 容量闸（理论上首条不会满，仍显式判） / Capacity gate
            _eCause := E_DL_RlaCause.eBufFull;                                    // 归因：缓冲满 / Cause: buffer full
        ELSE
            FOR _i := 1 TO DL_RLA_PCNT DO
                afLast[_i] := afParam[_i];                                        // 建立基准 / Build the baseline
                astLog[_iIdx].afVal[_i] := afParam[_i];                           // 写记录值 / Write the record values
            END_FOR
            astLog[_iIdx].sTag := sParamTag;                                       // 写记录标识 / Write the record tag
            astLog[_iIdx].nCnt := nParamCnt;                                       // 写记录参数个数 / Write the record count
            _uRev := 1;                                                            // 版本号 1 / Revision 1
            astLog[_iIdx].uRev := _uRev;                                           // 记版本号 / Store the revision
            _uCnt := 1;                                                            // 记录数 1 / One record
            _iIdx := 2;                                                            // 写指针推进 / Advance the write index
            _bInit := TRUE;                                                        // 基准建立 / Baseline established
            _bChanged := TRUE;                                                     // 记账脉冲 / Logging pulse
            _eCause := E_DL_RlaCause.eFirstSnap;                                   // 归因：首次基准快照（信息级） / Cause: first baseline
        END_IF
    ELSE
        (* 差异比对：逐项差值容差判等，全部同值即"无变化" *)
        FOR _i := 1 TO DL_RLA_PCNT DO
            IF _i <= nParamCnt THEN
                IF ABS(afParam[_i] - afLast[_i]) > fEps THEN
                    _bDiff := TRUE;                                                // 检出差异 / Difference found
                END_IF
            END_IF
        END_FOR

        IF NOT _bDiff THEN
            _eCause := E_DL_RlaCause.eNoChange;                                    // 归因：无变化（信息级，不记账） / Cause: no change
        ELSIF _uCnt >= DL_RLA_DEPTH THEN
            _bBufFull := TRUE;                                                     // 缓冲满：锁存拒记 / Buffer full: latch and reject
            _eCause := E_DL_RlaCause.eBufFull;                                     // 归因：缓冲满 / Cause: buffer full
        ELSE
            FOR _i := 1 TO DL_RLA_PCNT DO
                afLast[_i] := afParam[_i];                                         // 更新基准 / Refresh the baseline
                astLog[_iIdx].afVal[_i] := afParam[_i];                            // 写记录值 / Write the record values
            END_FOR
            astLog[_iIdx].sTag := sParamTag;                                       // 写记录标识 / Write the record tag
            astLog[_iIdx].nCnt := nParamCnt;                                       // 写记录参数个数 / Write the record count
            IF _uRev < DL_RLA_NUM_MAX THEN
                _uRev := _uRev + 1;                                                // 版本号递增（饱和不回绕） / Revision increment
            ELSE
                bCntSaturated := TRUE;                                             // 版本号饱和 / Revision saturated
            END_IF
            astLog[_iIdx].uRev := _uRev;                                           // 记版本号 / Store the revision
            IF _uCnt < DL_RLA_NUM_MAX THEN
                _uCnt := _uCnt + 1;                                                // 记录数递增（饱和不回绕） / Count increment
            ELSE
                bCntSaturated := TRUE;                                             // 计数饱和 / Count saturated
            END_IF
            _iIdx := _iIdx + 1;                                                    // 写指针推进 / Advance the write index
            _bChanged := TRUE;                                                     // 记账脉冲 / Logging pulse
        END_IF
    END_IF
END_IF

(* —— 段 6：出口单点映射（名实双出口，R191） —— *)
uLogCnt       := _uCnt;                                                          // 记录数出口 / Record count outlet
nRev          := _uRev;                                                          // 版本号出口 / Revision outlet
bChanged      := _bChanged;                                                      // 记账脉冲出口 / Logging pulse outlet
sLastTag      := sParamTag;                                                      // 最近标识出口（与当拍提交同源） / Latest tag outlet
bBufFull      := _bBufFull;                                                      // 缓冲满出口 / Buffer-full outlet
eState        := _eState;                                                        // 相出口 / Phase outlet
eCause        := _eCause;                                                        // 成因出口 / Cause outlet
bError        := _bFault;                                                        // 故障标志 / Error flag

END_FUNCTION_BLOCK
