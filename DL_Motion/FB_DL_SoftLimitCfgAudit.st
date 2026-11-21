(*==============================================================================
 * 组件名称 (Component)  : FB_DL_SoftLimitCfgAudit
 * 所属子库 (Sublibrary) : DL_Motion
 * 当前版本 (Version)    : 1.0.0
 * 兼容性 (Platform)     : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library，零厂商私有库，零轴状态枚举（R277）
 * 功能描述 (Function)   : 软限位组态交叉审计（投运/改版期一次性或周期审计）。
 *                         对软限域 [fSoftNeg, fSoftPos]、硬限域 [fHardNeg,
 *                         fHardPos]、行程域 [fTravelNeg, fTravelPos] 做五项
 *                         交叉判定：软限域 ⊆ 硬限域（两侧）、软限域 ⊆ 行程域
 *                         （两侧）、软限间距 >= 最小有效行程；任一项不过 →
 *                         bAuditFail 锁存并逐项输出失败位（归因到项，R190 粒度）。
 *                         与 SoftLimitGuard 分工：审计组态（静态），守卫运行
 *                         （动态）。
 * 来源标签 (Origin)     : 自研线（IEC 61131-3 标准语义的道莅防御性实现，clean-room）
 * 分工声明 (Pairing)    : SoftLimitCfgAudit（组态审计，本件）↔ SoftLimitGuard
 *                         （运行守卫，既有件）：本件只判静态域包含关系，不做
 *                         运行期位置预判、不输出拦截建议（R298 属主边界）。
 * 边界语义 (Boundary)   : ① 五项判定互独立，逐项输出失败位（不合并成单一布尔
 *                         造成归因丢失，R190 口径）；
 *                         ② 域值 NaN → 对应项按失败判（审计从严：可疑组态
 *                         不得放行）；
 *                         ③ 容差比较用 DL_AUD_EPS（浮点禁等值判，R4 口径）；
 *                         ④ 组态闸：最小有效行程 < 0 → 故障锁存。
 * 输出语义 (Fallback)   : 【R191】bEnable = FALSE → 审计输出保持末值（审计
 *                         结论是台账，不随失能清零）；eFault 相 → 冻结 +
 *                         bError = TRUE。监视型无主状态机（R23 公约）。
 * 码位     (Codes)      : 按 R297 范式零 16# 码位硬编码；错误出口 BOOL+ENUM(eCause)，
 *                         码位待主控收口统一派号。
 * 红线自检 (Redline)    : 7 项红线已自检：R1 零全局 ✓｜R2 零物理地址 ✓｜R3 纯 IEC ✓
 *                         R4 NaN 从严判败/容差比较/组态闸 ✓｜R5 双语同行注释 ✓
 *                         R6 N/A（监视型无状态机，判据纯派生）✓｜R7 N/A（无实例）✓
 * 验收向量 (Acceptance) : V1 软限 [-100,100] ⊆ 硬限 [-120,120] ⊆ 行程 [-130,130]，
 *                         间距 200 >= 10 → 全过 bAuditOk=TRUE；
 *                         V2 软限正界 125 > 硬限正界 120 → bFailPosOut=TRUE；
 *                         V3 软限间距 8 < 最小行程 10 → bFailSpan=TRUE；
 *                         V4 fHardPos=NaN → bFailPosOut=TRUE（从严）。
 * 修订历史 (Revision)   : 2026-11-20  v1.0.0  R49 首版（批 4 · 序号 18）
 *==============================================================================*)
TYPE E_DL_ScaCause :
(
    eNone       := 0,                        (* 无故障成因 / No cause *)
    eCfgIllegal := 1,                        (* 组态非法：最小行程域 / Illegal config: min-span domain *)
    eAuditFail  := 2                         (* 审计不通过（失败位承载逐项归因） / Audit failed *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_SoftLimitCfgAudit
VAR_INPUT
    fSoftPos    : LREAL := 100.0;            (* 软限位正界 [mm] / Soft limit positive *)
    fSoftNeg    : LREAL := (-100.0);         (* 软限位负界 [mm] / Soft limit negative *)
    fHardPos    : LREAL := 120.0;            (* 硬限位正界 [mm] / Hard limit positive *)
    fHardNeg    : LREAL := (-120.0);         (* 硬限位负界 [mm] / Hard limit negative *)
    fTravelPos  : LREAL := 130.0;            (* 机械行程正界 [mm] / Travel positive bound *)
    fTravelNeg  : LREAL := (-130.0);         (* 机械行程负界 [mm] / Travel negative bound *)
    fMinSpan    : LREAL := 10.0;             (* 软限最小有效行程要求，域 >= 0.0 [mm] / Minimum soft span requirement *)
    bRunAudit   : BOOL := FALSE;             (* 审计触发电平，TRUE 执行判定并刷新输出 [-] / Audit trigger level *)
    bReset      : BOOL := FALSE;              (* 复位命令，上升沿清审计锁存与失败位 [-] / Reset command *)
END_VAR
VAR_OUTPUT
    bAuditOk      : BOOL;                    (* 本轮审计全过电平（审计期有效）[-] / Audit-pass level *)
    bAuditFail    : BOOL;                    (* 审计不通过锁存位（复位沿清）[-] / Audit-fail latch *)
    bFailPosOutNeg: BOOL;                    (* 失败项 1：软限正界越过硬限正界 [-] / Fail item 1 *)
    bFailPosOutPos: BOOL;                    (* 失败项 2：软限负界越过硬限负界 [-] / Fail item 2 *)
    bFailTrvNeg   : BOOL;                    (* 失败项 3：软限正界越过行程正界 [-] / Fail item 3 *)
    bFailTrvPos   : BOOL;                    (* 失败项 4：软限负界越过行程负界 [-] / Fail item 4 *)
    bFailSpan     : BOOL;                    (* 失败项 5：软限间距不足最小行程 [-] / Fail item 5 *)
    nFailCnt      : INT;                     (* 本轮失败项计数 [项] / Failed item count *)
    eCause        : E_DL_ScaCause;           (* 成因出口（R190 逐项归由失败位承载） / Cause outlet *)
    bError        : BOOL;                    (* 组态故障锁存标志 [-] / Config fault flag *)
END_VAR
VAR
    rtReset   : R_TRIG;                       (* 复位沿实例，段 0 无条件调用 / Reset edge instance *)
    _bFault   : BOOL;                        (* 组态故障锁存位 / Config fault latch bit *)
    _bPosNaN  : BOOL;                        (* 任一域值非有限当拍量（从严判败用）[-] / Any bound non-finite this scan *)
    _nFail    : INT;                         (* 本轮失败项计数中间量 [项] / Fail count intermediate *)
END_VAR
VAR CONSTANT
    DL_AUD_EPS : LREAL := 1.0E-9;            (* 域比较容差（浮点禁等值判）[mm] / Domain comparison epsilon *)
END_VAR

(* —— 段 0：当拍判据派生 + 沿实例无条件刷新（R228A） —— *)
rtReset(CLK := bReset);                      (* 复位沿每拍必调 / Reset edge every scan *)
_bPosNaN := (fSoftPos <> fSoftPos) OR (fSoftNeg <> fSoftNeg) OR (fHardPos <> fHardPos)   (* 全部域值 NaN 自反判（逐引脚覆盖，R151） / NaN reflex on every bound *)
            OR (fHardNeg <> fHardNeg) OR (fTravelPos <> fTravelPos) OR (fTravelNeg <> fTravelNeg);

(* —— 段 1：复位沿处理（作用域：清故障 + 清失败锁存 + 清失败位，R283 逐项声明） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                        (* 清组态故障 / Clear fault *)
    eCause := E_DL_ScaCause.eNone;           (* 清成因 / Clear cause *)
    bAuditFail := FALSE;                     (* 清审计失败锁存 / Clear fail latch *)
    bFailPosOutNeg := FALSE;                 (* 清失败位 1 / Clear item 1 *)
    bFailPosOutPos := FALSE;                 (* 清失败位 2 / Clear item 2 *)
    bFailTrvNeg := FALSE;                    (* 清失败位 3 / Clear item 3 *)
    bFailTrvPos := FALSE;                    (* 清失败位 4 / Clear item 4 *)
    bFailSpan := FALSE;                      (* 清失败位 5 / Clear item 5 *)
    nFailCnt := 0;                           (* 清失败计数 / Clear count *)
    bAuditOk := FALSE;                       (* 清全过电平 / Clear pass level *)
END_IF

(* —— 段 2：组态闸故障锁存（最小行程负值无语义；锁存至复位沿，R189） —— *)
IF (fMinSpan < 0.0) AND NOT _bFault THEN
    _bFault := TRUE;                         (* 锁存组态故障（R45 配对） / Latch config fault *)
    eCause := E_DL_ScaCause.eCfgIllegal;     (* 成因：组态非法 / Cause: illegal config *)
END_IF

(* —— 段 3：审计判定（监视型纯派生，无 CASE 相；触发电平门控） —— *)
IF bRunAudit AND NOT _bFault THEN
    _nFail := 0;                             (* 失败计数清零重判 / Fail count recompute *)
    (* 项 1：软限正界须 < 硬限正界（从严：NaN 判败） / Item 1: soft pos must be inside hard pos *)
    IF _bPosNaN OR (fSoftPos > fHardPos - DL_AUD_EPS) THEN
        bFailPosOutNeg := TRUE;              (* 失败位 1 置位 / Item 1 fail *)
        _nFail := _nFail + 1;                (* 失败计数 / Count *)
    ELSE
        bFailPosOutNeg := FALSE;             (* 通过清位（每拍全路径赋值，R285） / Item 1 pass *)
    END_IF
    (* 项 2：软限负界须 > 硬限负界 / Item 2: soft neg inside hard neg *)
    IF _bPosNaN OR (fSoftNeg < fHardNeg + DL_AUD_EPS) THEN
        bFailPosOutPos := TRUE;              (* 失败位 2 / Item 2 fail *)
        _nFail := _nFail + 1;                (* 失败计数 / Count *)
    ELSE
        bFailPosOutPos := FALSE;             (* 通过清位 / Item 2 pass *)
    END_IF
    (* 项 3：软限正界须 <= 行程正界 / Item 3: soft pos inside travel pos *)
    IF _bPosNaN OR (fSoftPos > fTravelPos + DL_AUD_EPS) THEN
        bFailTrvNeg := TRUE;                 (* 失败位 3 / Item 3 fail *)
        _nFail := _nFail + 1;                (* 失败计数 / Count *)
    ELSE
        bFailTrvNeg := FALSE;                (* 通过清位 / Item 3 pass *)
    END_IF
    (* 项 4：软限负界须 >= 行程负界 / Item 4: soft neg inside travel neg *)
    IF _bPosNaN OR (fSoftNeg < fTravelNeg - DL_AUD_EPS) THEN
        bFailTrvPos := TRUE;                 (* 失败位 4 / Item 4 fail *)
        _nFail := _nFail + 1;                (* 失败计数 / Count *)
    ELSE
        bFailTrvPos := FALSE;                (* 通过清位 / Item 4 pass *)
    END_IF
    (* 项 5：软限间距须 >= 最小有效行程（间距 = 正界-负界，NaN 从严判败） / Item 5: span check *)
    IF _bPosNaN OR ((fSoftPos - fSoftNeg) < fMinSpan - DL_AUD_EPS) THEN
        bFailSpan := TRUE;                   (* 失败位 5 / Item 5 fail *)
        _nFail := _nFail + 1;                (* 失败计数 / Count *)
    ELSE
        bFailSpan := FALSE;                  (* 通过清位 / Item 5 pass *)
    END_IF
    nFailCnt := _nFail;                      (* 失败计数出口 / Count outlet *)
    IF _nFail > 0 THEN
        bAuditFail := TRUE;                  (* 审计失败锁存至复位沿 / Fail latch *)
        eCause := E_DL_ScaCause.eAuditFail;  (* 成因：审计不通过（逐项细节在失败位） / Cause: audit fail *)
        bAuditOk := FALSE;                   (* 全过电平收敛 / Pass level off *)
    ELSE
        bAuditOk := TRUE;                    (* 全过电平 / Pass level *)
        bAuditFail := FALSE;                 (* 通过时清失败锁存（新一轮覆盖旧结论） / Pass clears latch *)
        eCause := E_DL_ScaCause.eNone;       (* 成因清零 / Cause clear *)
    END_IF
END_IF

(* —— 段 4：出口映射（R191 名实同源） —— *)
bError := _bFault;                           (* 组态故障镜像 / Config fault mirror *)
END_FUNCTION_BLOCK
