(*
  ==================================================================
  组件名 Component  : FB_DL_ImpulseRelay
  分类   Category   : DL_Base
  前缀   Naming     : FB_DL_ ｜ b/n/u/f/t/e 类型前缀制（R265）
  版本   Version    : 1.0.0
  功能   Purpose    : 沿触发定宽脉冲输出（按钮/点动 → 固定时长）：bTrig
                      上升沿置 bPulse，内部 tonPulse（PT = tPulseWidth）
                      定宽计时，计时到清 bPulse。重触发语义：脉宽运行中
                      再来沿，边沿拍强制 TON 计时基复位（IN 置 FALSE 一
                      拍，使 ET 归零重起）——重触发后的脉冲为完整新脉宽
                      （非残留余宽）。tPulseWidth ≤ T#0MS 配置非法电平
                      面码 01，故障拍不出脉冲。
  来源   Source     : t1-1-oscat-basic（定宽脉冲继电为 OSCAT 基础库公开
                      功能语义，clean-room 重写，零源码复制）
  互引   Cross-ref  : FB_DL_TpEx / FB_DL_PulseStretch（同族脉冲邻件：
                      TpEx 为脉宽可变触发延时变体，PulseStretch 为展宽
                      件，本件为固定脉宽沿触发口径属主）
  平台   Platform   : 纯 IEC 61131-3（R_TRIG/TON/TIME 比较）
  依赖   Depends    : 仅 Standard.library（R_TRIG/TON 属标准件）
  红线   Redline    : R1 零全局/VAR_EXTERNAL/R2 零 %I/%Q/R3 纯 IEC 标准
                      R4 配置闸显式 + TON/沿实例段 0 无条件刷新/R5 全变
                      量双语同行注释/R6 配置故障电平面无状态机（CASE 不
                      适用，头注说明）/R7 rtTrig/tonPulse 无条件周期调用
                      /R8 阈值常量化
  契约   Contract   : 码 01 配置非法为电平面（当拍复判）：故障拍 bPulse=
                      FALSE、bError=TRUE，恢复即恢复（恢复拍即触发沿则
                      照常出脉冲，同拍合法事件优先 R275）。bPulse 名实
                      双出口：bPulse=TRUE ⟺ tonPulse 计时窗内或边沿拍。
  错误码 Codes      : 01【故障级·电平面】tPulseWidth ≤ T#0MS 配置非法，
                      不出脉冲
  码位反证 Note     : 单码件（R90）：唯一失效面为脉宽配置面，无并置分立
                      依据；码 01 置 bError（故障级 3 行内配对，R45）。
  验收   Acceptance : V1 沿触发 → bPulse=TRUE 持续 tPulseWidth 后自落
                      ｜ V2 脉宽中途再沿 → 计时重起，总宽 ≈ 重触发时刻
                      + tPulseWidth ｜ V3 tPulseWidth=0 → 码 01（电平
                      面）｜ V4 连续 bTrig=TRUE → 仅首个沿出脉冲（沿触
                      发非电平触发）｜ V5 恢复合法脉宽 → 立即可触发
  变更   Revision   : 2026-11-22  v1.0.0  R67 首版（编码阶段批 3 序 4）
  ==================================================================
*)
FUNCTION_BLOCK FB_DL_ImpulseRelay
VAR_INPUT
    bTrig       : BOOL := FALSE;   // 触发输入（上升沿出脉冲）[-] / the trigger input, pulse on the rising edge
    tPulseWidth : TIME := T#1S;    // 脉宽 [ms]，须 > 0 / the pulse width, must be positive
END_VAR
VAR_OUTPUT
    bPulse   : BOOL := FALSE;       // 定宽脉冲输出 [-] / the fixed width pulse output
    bError   : BOOL := FALSE;       // 配置故障标志（电平面，恢复即清，R45 配对）/ the configuration fault flag
    uErrorId : UDINT := 16#0000_0000; // 错误码，0=正常，01 见头注 [码] / the error code [code]
END_VAR
VAR
    rtTrig   : R_TRIG;              // 触发沿实例，段 0 无条件刷新 / the trigger edge instance refreshed unconditionally
    tonPulse : TON;                 // 定宽计时实例，段 0 无条件刷新 / the width timer instance refreshed unconditionally
    _bCfgOk  : BOOL := FALSE;       // 本拍配置有效性 [-] / the per scan configuration validity
END_VAR
VAR CONSTANT
    IRL_ERR_NONE : UDINT := 16#0000_0000;  // 无错误 [码] / no error [code]
    IRL_ERR_CFG  : UDINT := 16#0000_0001;  // 码 01：脉宽配置非法 / code 01, illegal pulse width
END_VAR

(*------------------------------------------------------------------------------
 * 段 0｜沿检测与定时器无条件刷新区（红线 R7）：严禁移入 IF / CASE
 *      The edge and the timer refresh unconditionally, never inside a branch
 *-----------------------------------------------------------------------------*)
rtTrig(CLK := bTrig);                        // 触发沿 / the trigger edge
tonPulse(IN := bPulse AND NOT rtTrig.Q, PT := tPulseWidth);  // 定宽计时：边沿拍强制 IN=FALSE 使 ET 归零重起（重触发完整新脉宽，R188 自复位语义）/ the width timing, the edge scan resets the timing base

(*------------------------------------------------------------------------------
 * 段 1｜错误码本拍预置 + 配置闸（电平面，当拍复判，码 01）
 *      The error code preset and the configuration gate
 *-----------------------------------------------------------------------------*)
uErrorId := IRL_ERR_NONE;       // 预置无错误 / preset no error
_bCfgOk := (tPulseWidth > T#0MS);  // 配置闸（TIME 直接比较，三平台一致）/ the configuration gate
IF NOT _bCfgOk THEN
    bError := TRUE;             // 故障标志（R45 配对，故障级 3 行内置）/ the fault flag
    uErrorId := IRL_ERR_CFG;    // 码 01 / code 01
    bPulse := FALSE;            // 故障拍不出脉冲（安全缺省）/ no pulse on fault
    RETURN;                     // 结构早退（tonPulse 已刷，段 0 契约不破）/ structural early return
ELSE
    bError := FALSE;            // 配置恢复即清（电平面契约）/ cleared when the configuration recovers
END_IF

(*------------------------------------------------------------------------------
 * 段 2｜沿触发置位（同拍合法事件优先于计时窗判定，R275）
 *      The edge set, the legal event before the window verdict
 *-----------------------------------------------------------------------------*)
IF rtTrig.Q THEN
    bPulse := TRUE;             // 沿置脉冲 / set the pulse on the edge
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜计时窗到清位（段 0 已刷 tonPulse：边沿拍 Q=FALSE 不误清，下拍起算）
 *      The window expiry clears the pulse, the edge scan never clears
 *-----------------------------------------------------------------------------*)
IF tonPulse.Q THEN
    bPulse := FALSE;            // 脉宽到落脉冲 / drop the pulse on expiry
END_IF
END_FUNCTION_BLOCK
