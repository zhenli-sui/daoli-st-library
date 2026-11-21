(*==============================================================================
 * 组件名称 (Component)  : FB_DL_BatchDeviationTierAlarm
 * 所属子库 (Sublibrary) : DL_Process
 * 当前版本 (Version)    : 1.0.0
 * 命名说明 (Naming)     : 本库已存在 FB_DL_BatchDeviationAlarm（早期入库，引脚为
 *                         fBandWarn/fBandMinor/fBandMajor 三档区间口径，码位 0005_01FA/
 *                         01FB/033C~033E）。R28 计划书序 15 的引脚口径（TolL/TolH/TolLL/
 *                         TolHH 双侧四档 + 首出归因 + 升 P1）与之不兼容，且同名会与已注册
 *                         组件撞名，故按「双侧四档」语义另立本名，旧件保持不动待裁定。
 * 兼容性 (Platform)     : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop（纯标准元素，无方言）
 * 功能描述 (Function)   : 批次偏差四档分级报警与首出归因。实测值对目标的偏差按双侧带宽分
 *                         四档（L/LL 低侧、H/HH 高侧），越档即活跃；确认只清「已确认」不清
 *                         「活跃」，两者正交可同为 TRUE；回到 Ok 时两标志同拍清零（否则
 *                         HMI 留幽灵报警）；首出来源在越档沿锁存，便于多源汇总定位；超档
 *                         （LL/HH）升 P1。不做偏差计算之外的统计过程控制、不做批次切换。
 * 溯源 (Origin)         : 道莅 clean-room 防御性实现
 * 本文件内含 (Contains) : TYPE E_DL_DevLevel / FUNCTION_BLOCK FB_DL_BatchDeviationTierAlarm
 * 依赖 (Depends)        : 无（仅 Standard.library 的 ABS）
 * 红线自检 (Redline)    : 无外部全局变量、无硬件地址直引 ｜ 全变量中英双语同行注释
 *                         带宽反置先判组态错 ｜ 目标/实测非有限时保持上一拍活跃与档位 ｜ 非
 *                         有限用自反比较 ｜ 枚举显式赋值 ｜ CASE 含 ELSE 兜底 ｜ 本件无定时器，
 *                         沿实例无条件周期刷新
 * 错误码表 (Codes)      : 16#0005_043F 就绪（Ok 档）
 *                         16#0005_0440 故障级 实测值非有限（保持上一拍档位与活跃标志）
 *                         16#0005_0441 故障级 带宽序反置（LL ≤ L 或 HH ≤ H，反置使四档同档）
 *                         16#0005_0442 故障级 目标值非有限（eLevel=Ok 但 bActive 保持上一拍）
 *                         16#0005_0443 预留：本版不发码（下一轮区间起点，禁止回填）
 * 修订历史 (Revision)   : 2026-11-17  v1.0.0  首版入库 · R28 · 阶段三批 4（因撞名另立名）
 * 验收向量 (Acceptance) : 正向 目标 100、L/H=2、LL/HH=5、实测 106 → eLevel=HH 且
 *                         bEscalateP1；bAck 后 bAcked=TRUE 而 bActive 仍 TRUE；回 100 →
 *                         两标志同拍清零
 *                         反向 带宽反置（LL=1 < L=2）→ 16#0005_0441；目标给 NaN →
 *                         16#0005_0442 且 bActive 保持上一拍；实测 98 → eLevel=L
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_DevLevel（归属本功能块，同文件发布，全库唯一定义）
 *----------------------------------------------------------------------------*)
TYPE E_DL_DevLevel :
(
    eOk := 0,    // 合格：偏差在容忍带内 / Within the tolerance band
    eL  := 10,   // 低档：越过低侧带宽 / Low tier beyond the low band
    eLL := 20,   // 低低档：越过低低侧带宽，升 P1 / Low-low tier beyond the low-low band, escalated
    eH  := 30,   // 高档：越过高速侧带宽 / High tier beyond the high band
    eHH := 40    // 高高档：越过高高侧带宽，升 P1 / High-high tier beyond the high-high band, escalated
);
END_TYPE

FUNCTION_BLOCK FB_DL_BatchDeviationTierAlarm
VAR_INPUT
    bEnable    : BOOL := FALSE;           // 使能 / Enable
    fValue     : REAL := 0.0;             // 批内实测值（单位由调用方定义，头注释口径：与 fTarget 同单位） / Measured value in the same unit as the target
    fTarget    : REAL := 0.0;             // 批次目标 / Batch target value
    fTolL      : REAL := 2.0;             // 低侧容忍带宽 / Low tolerance band
    fTolH      : REAL := 2.0;             // 高侧容忍带宽 / High tolerance band
    fTolLL     : REAL := 5.0;             // 低低侧带宽，须 > fTolL / Low-low band, must exceed the low band
    fTolHH     : REAL := 5.0;             // 高高侧带宽，须 > fTolH / High-high band, must exceed the high band
    uSourceId  : UINT := 1;               // 来源编号（多源汇总首出定位） / Source identifier for first-out attribution
    bAck       : BOOL := FALSE;           // 确认（只清已确认，不清活跃） / Acknowledge, clears the acked flag only
END_VAR
VAR_OUTPUT
    eLevel     : E_DL_DevLevel;           // 偏差档位 / Deviation tier
    bActive    : BOOL;                    // 活跃（越档中） / Active while out of band
    bAcked     : BOOL;                    // 已确认（与活跃正交，可同为 TRUE） / Acknowledged, orthogonal to active
    uFirstSource : UINT;                  // 首出来源编号 / First-out source identifier
    bEscalateP1 : BOOL;                   // 超档升 P1（LL 或 HH） / Escalated to priority one on LL or HH
    uDevCount  : UDINT;                   // 累计越带次数 [次] / Accumulated excursion count
    eErr       : UDINT;                   // 错误码，段位 16#0005_xxxx / Error code in segment 16#0005_xxxx
END_VAR
VAR
    _bInit     : BOOL := FALSE;           // 首扫标志，取非判定 / First-scan flag, tested negated
    _bActive   : BOOL := FALSE;           // 活跃状态量（跨拍保持） / Active state quantity held across scans
    _bAcked    : BOOL := FALSE;           // 已确认状态量 / Acknowledged state quantity
    _bCfgOk    : BOOL;                    // 带宽序合法标志 / Band ordering valid flag
    _bValOk    : BOOL;                    // 实测值有限标志 / Measured value finite flag
    _bTgtOk    : BOOL;                    // 目标值有限标志 / Target value finite flag
    _eLevel    : E_DL_DevLevel := E_DL_DevLevel.eOk; // 档位内部副本 / Internal tier copy
    _fDev      : REAL;                    // 偏差（实测 − 目标） / Deviation, measured minus target
    _rtrigAck  : R_TRIG;                  // 确认上升沿 / Rising edge of the acknowledge input
END_VAR
VAR CONSTANT
    DL_BD_READY   : UDINT := 16#0005_043F;  // 就绪码 / Ready code
    DL_BD_VAL_BAD : UDINT := 16#0005_0440;  // 故障级实测非有限码 / Fault code for a non-finite measured value
    DL_BD_BAND_BAD : UDINT := 16#0005_0441; // 故障级带宽反置码 / Fault code for inverted bands
    DL_BD_TGT_BAD : UDINT := 16#0005_0442;  // 故障级目标非有限码 / Fault code for a non-finite target
END_VAR

// 段 1｜输出与单拍标志预置
bEscalateP1 := FALSE;                               // 升 P1 预清 / Escalation pre-cleared
eErr := 0;                                          // 错误码预清 / Error code pre-cleared

// 段 2｜确认沿无条件周期刷新
_rtrigAck(CLK := bAck);                             // 确认沿 / Acknowledge edge

// 段 3｜首扫初始化（判据取非，R19）
IF NOT _bInit THEN
    _eLevel := E_DL_DevLevel.eOk;                   // 档位起点 Ok / Tier starts at Ok
    _bActive := FALSE;                              // 活跃起点 FALSE / Active starts false
    _bAcked := FALSE;                               // 已确认起点 FALSE / Acknowledged starts false
    _bInit := TRUE;                                 // 首扫只做一次 / The first scan runs once
END_IF

// 段 4｜带宽序与数值可读闸
_bCfgOk := (fTolLL > fTolL) AND (fTolHH > fTolH) AND (fTolL > 0.0) AND (fTolH > 0.0);
_bValOk := NOT ((fValue <> fValue) OR ((fValue - fValue) <> (fValue - fValue)));
_bTgtOk := NOT ((fTarget <> fTarget) OR ((fTarget - fTarget) <> (fTarget - fTarget)));
IF NOT _bCfgOk THEN
    eErr := DL_BD_BAND_BAD;                         // 故障级：带宽序反置 / Fault, inverted bands
END_IF
IF NOT _bTgtOk THEN
    eErr := DL_BD_TGT_BAD;                          // 故障级：目标非有限（活跃与档位保持上一拍） / Fault, the target is not finite
END_IF
IF NOT _bValOk THEN
    eErr := DL_BD_VAL_BAD;                          // 故障级：实测非有限（档位保持上一拍） / Fault, the measured value is not finite
END_IF

// 段 5｜档位判定（数列在段 4 已证可读且带宽有序时才判）
IF _bCfgOk AND _bValOk AND _bTgtOk THEN
    _fDev := fValue - fTarget;                      // 偏差 / Deviation
    IF _fDev >= fTolHH THEN
        _eLevel := E_DL_DevLevel.eHH;               // 高高档 / High-high tier
    ELSIF _fDev >= fTolH THEN
        _eLevel := E_DL_DevLevel.eH;                // 高档 / High tier
    ELSIF _fDev <= (0.0 - fTolLL) THEN
        _eLevel := E_DL_DevLevel.eLL;               // 低低档 / Low-low tier
    ELSIF _fDev <= (0.0 - fTolL) THEN
        _eLevel := E_DL_DevLevel.eL;                // 低档 / Low tier
    ELSE
        _eLevel := E_DL_DevLevel.eOk;               // 合格 / Within band
    END_IF
END_IF

// 段 6｜活跃/确认状态推进（回 Ok 时两标志同拍清零）
IF _eLevel = E_DL_DevLevel.eOk THEN
    _bActive := FALSE;                              // 活跃清 / Active cleared
    _bAcked := FALSE;                               // 已确认同拍清（防 HMI 幽灵报警） / Acknowledged cleared in the same scan
    uFirstSource := 0;                              // 首出源清 / First-out source cleared
ELSE
    IF NOT _bActive THEN
        uDevCount := uDevCount + 1;                 // 新越带：累计 +1 [次] / New excursion, count incremented
        uFirstSource := uSourceId;                  // 首出来源锁存 / First-out source latched
    END_IF
    _bActive := TRUE;                               // 活跃置位 / Active set
    IF _rtrigAck.Q THEN
        _bAcked := TRUE;                            // 确认置位（不清活跃） / Acknowledge set, active is untouched
    END_IF
END_IF
bActive := _bActive;                                // 活跃出口 / Active output
bAcked := _bAcked;                                  // 已确认出口 / Acknowledged output

// 段 7｜档位映射与升 P1（ENUM + CASE + ELSE 兜底）
CASE _eLevel OF
    E_DL_DevLevel.eOk:
        eLevel := E_DL_DevLevel.eOk;                // 合格 / Within band
        IF eErr = 0 THEN
            eErr := DL_BD_READY;                    // 就绪码 / Ready code
        END_IF
    E_DL_DevLevel.eL:
        eLevel := E_DL_DevLevel.eL;                 // 低档 / Low tier
    E_DL_DevLevel.eLL:
        eLevel := E_DL_DevLevel.eLL;                // 低低档 / Low-low tier
        bEscalateP1 := TRUE;                        // 升 P1 / Escalated
    E_DL_DevLevel.eH:
        eLevel := E_DL_DevLevel.eH;                 // 高档 / High tier
    E_DL_DevLevel.eHH:
        eLevel := E_DL_DevLevel.eHH;                // 高高档 / High-high tier
        bEscalateP1 := TRUE;                        // 升 P1 / Escalated
    ELSE
        // 非法档位兜底：按高高档处理（安全侧）并报组态错
        _eLevel := E_DL_DevLevel.eHH;
        eLevel := E_DL_DevLevel.eHH;
        bEscalateP1 := TRUE;
        eErr := DL_BD_BAND_BAD;                     // 故障级：非法档位 / Fault, illegal tier
END_CASE
END_FUNCTION_BLOCK
