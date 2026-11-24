(*==============================================================================
 * 组件名称 (Component)  : FB_DL_OutputForcingBank
 * 所属子库 (Sublibrary) : DL_Base
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（R_TRIG），零厂商私有库
 * 功能描述 (Function)   : 16 路输出强制库（调试/维修用）：每拍组合式裁决
 *                         abOut[i] = bAutoMode ∧ abForceSel[i] ? abForceVal[i]
 *                         : abAutoVal[i]；任一通道强制激活 → uForcingMask 位图
 *                         对应位置 1；强制撤除（abForceSel 下降沿）当拍无扰
 *                         回自动（组合式单拍重算，无斜坡无残留）；bAutoMode=
 *                         FALSE 时强制请求被拒（输出仍走自动值），拒收当拍置
 *                         信息码 eForceRej 并计数 uRejCnt。
 * 接口     (Interface)  : 输入 abAutoVal 16 路自动值、abForceSel 16 路强制选择、
 *                         abForceVal 16 路强制值、bAutoMode 自动模式许可；
 *                         输出 abOut 16 路裁决输出、uForcingMask 强制激活
 *                         位图（bit i=通道 i）、uRejCnt 强制拒收计数、
 *                         eErrCode 信息码、bError 故障标志（本件无故障级
 *                         条件，恒 FALSE，契约位保留）。
 * 边界     (Boundary)   : ① **属主边界（写死）：本件只做输出裁决，不接管安全
 *                         回路、不做强制权限管理**；安全回路强制归硬件层，
 *                         本件不得用于旁路安全联锁（头注释声明）。
 *                         ② 无扰回自动：撤除拍输出 = 自动值（组合式当拍生效，
 *                         无历史残留路径，规格指定）。
 *                         ③ 拒收计数用 R_TRIG 捕「拒收状态进入沿」计数（状态
 *                         电平不重复计数）；拒收期 uForcingMask 对应位保持 0
 *                         （强制未生效）。
 *                         ④ 通道定长 16（常量），FOR 界宽常量，无越界路径。
 *                         ⑤ R_TRIG 实例段 0 无条件周期调用（R6/R7）。
 *                         ⑥ 零全局耦合（无 GVL / VAR_EXTERNAL / 物理地址）。
 * 分工声明 (Scope)      : 与 `FB_DL_OverrideSelector` 分工：模拟量超驰选择归
 *                         那件、数字量强制库归本件；与 `FB_DL_InterlockMatrix`
 *                         分工：联锁矩阵归那件（安全语义），本件为非安全
 *                         调试设施。
 * 来源标签 (Source Tag) : 自研线（输出强制裁决为道莅防御性实现）
 * 码表     (Codes)      : 本件不占用任何全局数字码位。出口为 BOOL 数组 +
 *                         WORD 位图 + UDINT 计数 + ENUM 信息码；数字码位待
 *                         主控收口阶段统一派号。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 拒收沿计数 + 无扰回自动 + 位图单源 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 N/A（无 ENUM 状态机） ｜ R7 ✓ 一 R_TRIG 段 0 无条件刷新
 * 修订历史 (Revision)   : 2026-11-20  v1.0.0  R50 首版（批次 3 · 序号 12）
 * 验收向量 (Acceptance) : ① bAutoMode=TRUE，abForceSel[3]=TRUE，abForceVal[3]=
 *                         TRUE，abAutoVal[3]=FALSE → abOut[3]=TRUE，
 *                         uForcingMask.bit3=1；② abForceSel[3] 撤除当拍：
 *                         abOut[3]=abAutoVal[3]=FALSE（无扰回自动），bit3=0；
 *                         ③ bAutoMode=FALSE 且 abForceSel[5] 置位 → abOut[5]
 *                         =abAutoVal[5]（强制被拒），uRejCnt+1，
 *                         eErrCode=eForceRej。
 *==============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_OfbErr（信息码；拒收走信息级，不置 bError）
 *----------------------------------------------------------------------------*)
TYPE E_DL_OfbErr :
(
    eOk       := 0,   // 无拒收 / No rejection
    eForceRej := 1    // 信息级：存在被拒强制通道（bAutoMode=FALSE，见 uRejCnt） / Info: forced channels rejected
);
END_TYPE

FUNCTION_BLOCK FB_DL_OutputForcingBank
VAR_INPUT
    abAutoVal  : ARRAY[0..15] OF BOOL;   // 16 路自动值（正常输出源） [-] / Sixteen auto values
    abForceSel : ARRAY[0..15] OF BOOL;   // 16 路强制选择 [-] / Sixteen force selects
    abForceVal : ARRAY[0..15] OF BOOL;   // 16 路强制值 [-] / Sixteen force values
    bAutoMode  : BOOL := TRUE;           // 自动模式许可（FALSE=强制被拒） [-] / Auto-mode permission
END_VAR
VAR_OUTPUT
    abOut        : ARRAY[0..15] OF BOOL; // 16 路裁决输出 [-] / Sixteen arbitrated outputs
    uForcingMask : WORD;                 // 强制激活位图（bit i=通道 i 强制生效） [-] / Forcing bitmap
    uRejCnt      : UDINT := 0;           // 强制拒收进入沿计数（防回绕） [次] / Rejection entry count
    eErrCode     : E_DL_OfbErr;          // 信息码出口 / Info code outlet
    bError       : BOOL;                 // 故障标志（本件恒 FALSE，契约位） [-] / Error flag, contract pin, always FALSE
END_VAR
VAR
    _uMask    : WORD;                    // 位图内部单源（与出口同源） / Bitmap internal source
    _bAnyRej  : BOOL;                    // 存在拒收通道当拍量 [-] / Any rejected channel
    i         : DINT;                    // 通道循环索引 / Channel loop index
    rtRej     : R_TRIG;                  // 拒收进入沿实例，段 0 无条件调用 / Rejection entry edge instance
END_VAR
VAR CONSTANT
    DL_OFB_NMAX : DINT := 16;            // 通道定长 [路] / Fixed channel count
    DL_OFB_BIT0 : WORD := 1;             // bit0 基准掩码 [-] / Bit zero base mask
    DL_OFB_UDMAX: UDINT := 4294967295;   // 拒收计数饱和点（防回绕） [次] / Rejection counter ceiling
END_VAR

(* —— 段 0：拒收沿实例无条件周期刷新（R6/R7） —— *)
rtRej(CLK := (NOT bAutoMode) AND (abForceSel[0] OR abForceSel[1] OR abForceSel[2]
       OR abForceSel[3] OR abForceSel[4] OR abForceSel[5] OR abForceSel[6]
       OR abForceSel[7] OR abForceSel[8] OR abForceSel[9] OR abForceSel[10]
       OR abForceSel[11] OR abForceSel[12] OR abForceSel[13] OR abForceSel[14]
       OR abForceSel[15]));              // 拒收进入沿（任一强制选择 ∧ 非自动模式），每拍必调 / Rejection entry edge, every scan

(* —— 段 1：拒收沿计数（防回绕） —— *)
IF rtRej.Q THEN
    IF uRejCnt < DL_OFB_UDMAX THEN
        uRejCnt := uRejCnt + 1;          // 拒收进入沿计数 / Count rejection entry
    END_IF
END_IF

(* —— 段 2：16 路组合式裁决（强制生效闸：bAutoMode ∧ abForceSel；撤除当拍无扰回自动） —— *)
_uMask := 0;                             // 位图当拍重建（单源） / Rebuild bitmap per scan
_bAnyRej := FALSE;                       // 拒收量预清 / Rejection preset
FOR i := 0 TO (DL_OFB_NMAX - 1) DO
    IF bAutoMode AND abForceSel[i] THEN
        abOut[i] := abForceVal[i];       // 强制生效：输出强制值 / Forced: force value
        _uMask := _uMask OR SHL(DL_OFB_BIT0, i);   // 记激活位（i∈[0,15] 位宽内） / Set forcing bit
    ELSE
        abOut[i] := abAutoVal[i];        // 自动值直通（含强制撤除当拍与拒收通道） / Auto pass-through
        IF abForceSel[i] THEN
            _bAnyRej := TRUE;            // 强制请求被拒（bAutoMode=FALSE） / Force rejected
        END_IF
    END_IF
END_FOR

(* —— 段 3：出口单点映射（名实双出口同源，R191） —— *)
uForcingMask := _uMask;                  // 位图出口 / Bitmap outlet
IF _bAnyRej THEN
    eErrCode := E_DL_OfbErr.eForceRej;   // 信息级（不置 bError） / Info code
ELSE
    eErrCode := E_DL_OfbErr.eOk;         // 正常 / Normal
END_IF
bError := FALSE;                         // 本件无故障级条件（头注释声明） / No fault-level condition

END_FUNCTION_BLOCK
