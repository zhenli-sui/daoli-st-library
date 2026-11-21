(*==============================================================================
 * 组件名称 (Component)  : FB_DL_DebounceBank
 * 所属子库 (Sublibrary) : DL_Base
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（TON），零厂商私有库
 * 功能描述 (Function)   : 16 路独立去抖库：每通道双阈值去抖（上升沿经 tRise
 *                         确认置 TRUE、下降沿经 tFall 确认回 FALSE，确认窗内
 *                         输出保持原态），每通道独立 TON 对（tonRise/tonFall），
 *                         全部实例主体无条件周期刷新（R6，禁止 IF 内调用）。
 *                         通道数 nChanCnt 钳位 1~16，越界钳位并置信息码
 *                         eCfgClamp；有效通道数之外的通道输出恒 FALSE。
 * 接口     (Interface)  : 输入 abRaw 16 路原始输入、aRise 16 路上升确认时间、
 *                         aFall 16 路下降确认时间、nChanCnt 有效通道数（钳位
 *                         1~16）；输出 abDeb 16 路去抖输出、bStable 全通道
 *                         稳定指示（全部通道当前不在确认窗内）、eErrCode
 *                         信息码、bError 故障标志（本件钳位走信息级，
 *                         bError 恒 FALSE，契约位保留）。
 * 边界     (Boundary)   : ① **属主边界（写死）：本件只做逐通道去抖，不判信号
 *                         语义、不做脉冲整形**；最小脉宽滤除归
 *                         `FB_DL_MinPulseWidthFilter`。
 *                         ② 32 个 TON 实例按 0..15 定长数组声明，FOR 循环
 *                         无条件调用（界宽常量，无死循环、无越界路径）。
 *                         ③ 双阈值语义：abDeb[i]=TRUE 当且仅当 tonRise[i].Q；
 *                          =FALSE 当 tonFall[i].Q（IN := NOT abRaw[i]）；两窗
 *                         均未到时输出保持上拍（互斥保持，无抖动带）。
 *                         ④ nChanCnt < 1 或 > 16：钳位到 [1,16] 并置信息码
 *                         eCfgClamp（规格指定钳位语义，不锁存故障）；有效域外
 *                         通道（i >= nChanCnt）输出强制 FALSE 且不参与 bStable。
 *                         ⑤ 时间引脚 <= T#0S 的通道按 0 处理（去抖直通：
 *                         输出跟随原始信号，TON PT=0 当拍到）。
 *                         ⑥ 零全局耦合（无 GVL / VAR_EXTERNAL / 物理地址）。
 * 分工声明 (Scope)      : 与 `FB_DL_SignalDebounce`（单路件）分工：单路去抖归
 *                         那件、16 路批量库归本件；与 `FB_DL_PulseWidthFilter`
 *                         分工：脉宽滤除 ≠ 电平去抖。
 * 来源标签 (Source Tag) : IEC 61131-3 标准语义的道莅防御性实现（TON 双阈值
 *                         去抖为标准定时器语义组合）
 * 码表     (Codes)      : 本件不占用任何全局数字码位。出口为 BOOL 数组 +
 *                         ENUM 信息码；数字码位待主控收口阶段统一派号。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 通道钳位 + 时间域兜底 + 有效域外恒 FALSE ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 N/A（无 ENUM 状态机） ｜ R7 ✓ 32 TON 段 0 定长循环无条件刷新
 * 修订历史 (Revision)   : 2026-11-20  v1.0.0  R50 首版（批次 1 · 序号 4）
 * 验收向量 (Acceptance) : ① 通道 0：tRise=T#50MS，tFall=T#50MS，原始信号跳变
 *                         TRUE 后 30ms 输出仍 FALSE（确认窗内保持），50ms 后
 *                         abDeb[0]=TRUE；② 原始信号 20ms 毛刺（< 50ms）：输出
 *                         不翻转（毛刺被去抖）；③ nChanCnt=20 → 钳位 16，
 *                         eErrCode=eCfgClamp；nChanCnt=0 → 钳位 1，
 *                         eErrCode=eCfgClamp，通道 1~15 恒 FALSE。
 *==============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_DbbErr（信息码；钳位走信息级，不置 bError）
 *----------------------------------------------------------------------------*)
TYPE E_DL_DbbErr :
(
    eOk       := 0,   // 通道数在合法域 / Channel count in domain
    eCfgClamp := 1    // 信息级：通道数越界已钳位 [1,16] / Info: channel count clamped to [1,16]
);
END_TYPE

FUNCTION_BLOCK FB_DL_DebounceBank
VAR_INPUT
    abRaw    : ARRAY[0..15] OF BOOL;   // 16 路原始输入信号 [-] / Sixteen raw input signals
    aRise    : ARRAY[0..15] OF TIME;   // 16 路上升确认时间（<=T#0S 直通） [ms] / Sixteen rise confirm times
    aFall    : ARRAY[0..15] OF TIME;   // 16 路下降确认时间（<=T#0S 直通） [ms] / Sixteen fall confirm times
    nChanCnt : UDINT := 16;            // 有效通道数，域 [1,16]（越界钳位） [路] / Active channel count
END_VAR
VAR_OUTPUT
    abDeb    : ARRAY[0..15] OF BOOL;   // 16 路去抖输出（有效域外恒 FALSE） [-] / Sixteen debounced outputs
    bStable  : BOOL;                   // 全有效通道稳定指示（无通道在确认窗内） [-] / All-active-channels stable indicator
    eErrCode : E_DL_DbbErr;            // 信息码出口 / Info code outlet
    bError   : BOOL;                   // 故障标志（本件恒 FALSE，契约位） [-] / Error flag, contract pin, always FALSE
END_VAR
VAR
    _nCount  : DINT;                   // 钳位后有效通道数 [路] / Clamped active channel count
    _bClamp  : BOOL;                   // 本拍发生钳位 [-] / Clamp occurred this scan
    _bAllStb : BOOL;                   // 稳定指示内部量 [-] / Stable indicator internal
    i        : DINT;                   // 通道循环索引 / Channel loop index
    aTonRise : ARRAY[0..15] OF TON;    // 16 路上升确认定时器（段 0 定长循环无条件调用） / Sixteen rise TON instances
    aTonFall : ARRAY[0..15] OF TON;    // 16 路下降确认定时器（段 0 定长循环无条件调用） / Sixteen fall TON instances
END_VAR
VAR CONSTANT
    DL_DBB_NMAX : DINT := 16;          // 通道定长上限 [路] / Fixed channel ceiling
    DL_DBB_NMIN : DINT := 1;           // 通道数下限 [路] / Active count floor
END_VAR

(* —— 段 0：通道数钳位 + 32 TON 定长循环无条件刷新（R6/R7） —— *)
_bClamp := FALSE;                                   // 钳位量预清 / Clamp preset
_nCount := UDINT_TO_DINT(nChanCnt);                 // 通道数转 DINT（越界由下步钳位） / Convert count
IF _nCount > DL_DBB_NMAX THEN
    _nCount := DL_DBB_NMAX;                         // 上越界钳 16 / Clamp high to 16
    _bClamp := TRUE;                                // 记钳位 / Mark clamp
END_IF
IF _nCount < DL_DBB_NMIN THEN
    _nCount := DL_DBB_NMIN;                         // 下越界钳 1 / Clamp low to 1
    _bClamp := TRUE;                                // 记钳位 / Mark clamp
END_IF
FOR i := 0 TO (DL_DBB_NMAX - 1) DO
    aTonRise[i](IN := abRaw[i],  PT := aRise[i]);   // 上升确认 TON 无条件调用 / Rise TON unconditional call
    aTonFall[i](IN := NOT abRaw[i], PT := aFall[i]);   // 下降确认 TON 无条件调用 / Fall TON unconditional call
END_FOR

(* —— 段 1：双阈值去抖输出（有效通道：Rise.Q 置 / Fall.Q 复 / 窗内保持；域外恒 FALSE） —— *)
_bAllStb := TRUE;                                   // 稳定指示起步为真，逐通道合取 / Stable preset true, AND-reduce
FOR i := 0 TO (DL_DBB_NMAX - 1) DO
    IF i >= _nCount THEN
        abDeb[i] := FALSE;                          // 有效域外通道恒 FALSE（规格④） / Out-of-domain channel constant FALSE
    ELSIF aTonRise[i].Q THEN
        abDeb[i] := TRUE;                           // 上升确认到：置 TRUE（已确认通道不降低稳定指示） / Rise confirmed: TRUE
    ELSIF aTonFall[i].Q THEN
        abDeb[i] := FALSE;                          // 下降确认到：回 FALSE / Fall confirmed: FALSE
    ELSE
        _bAllStb := FALSE;                          // 双窗均未到：输出保持上拍，本通道不稳定 / Both windows pending: hold, unstable
        (* abDeb[i] 不赋值 = 保持上拍（互斥保持语义，头注释③） *)
    END_IF
END_FOR

(* —— 段 2：出口单点映射（名实双出口同源，R191） —— *)
bStable := _bAllStb;                                // 稳定指示出口 / Stable indicator outlet
IF _bClamp THEN
    eErrCode := E_DL_DbbErr.eCfgClamp;              // 信息级：钳位口径 / Info: clamped
ELSE
    eErrCode := E_DL_DbbErr.eOk;                    // 正常 / Normal
END_IF
bError := FALSE;                                    // 本件无故障级条件（头注释声明） / No fault-level condition

END_FUNCTION_BLOCK
