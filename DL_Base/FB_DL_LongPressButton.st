(*
  ==================================================================
  组件名 Component  : FB_DL_LongPressButton
  分类   Category   : DL_Base
  前缀   Naming     : FB_DL_ ｜ b/n/u/f/t/e/st 类型前缀制（R265）
  复杂度 Complexity  : 中
  版本   Version    : 1.0.0
  功能   Purpose    : 单按钮短按/长按/超长按三档时序分档（三窗 TON 阈值单拍分档）。
  来源   Source     : self-std（IEC 人机交互时序语义自研）
  平台   Platform   : 纯 IEC 61131-3（Standard.library: TON / R_TRIG / F_TRIG），无私有库
  分工声明 Split     : 与 FB_DL_ToggleButtonBank（模式解算属主）分工——后者做
                      按压次数模式解算；本件做单按钮按持续时长的三档分档
                      （R216 双向互引）。
  作者   Author     : 道莅代码库 · PLC 编程专家（R61）
  归属 Ownership     : 本件无 TYPE 声明；引用件类型全部 IEC 标准原生。
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 三档窗组态闸（R239）：tShort < tLong < tXLong 且三者 > 0，
                         违反判组态非法故障码并冻结分档输出（锁存至复位沿）；
                      二 三窗职责与配比约束（R100）：tonShort < tonLong < tonXLong
                         由组态闸结构性保证；长按/超长按在按压持续中经阈值沿
                         单拍分档，短按在释放沿回判；
                      三 TON / R_TRIG / F_TRIG 全部段 0 无条件周期刷新（禁入分支）；
                      四 三档脉冲为单拍输出，段 1 统一预置 FALSE、分支只写 TRUE
                         （R256），内部 _b* 两段式映射（R187）；
                      五 故障态语义为「冻结保持全假输出」（R191 声明行）；
                      六 故障解除路径：复位沿清锁存（bReset 恒可达，R152 自证）；
                      七 无全局、无外部变量、无物理地址。
  错误码   Codes    :
    16#0001_0640【故障级】三档窗组态非法（tShort < tLong < tXLong 违反或 ≤0），锁存至复位沿
  验收   Acceptance :
    算法已证（脚本）：未跑 ｜ 编译器已证（三平台）：未跑
    V1 按下 200ms 释放（tShort=100/tLong=800/tXLong=2000）→ bShortPress 单拍
    V2 按住 1s → 长按阈值拍 bLongPress 单拍；V3 按住 2.5s → bXLongPress 单拍
    V4 tShort = tLong → 码 0640、三脉冲恒假、锁存待复位
  修订记录 Revision  :
    2026-11-21  v1.0.0  R61 首版（批 2 · 序号 8）
  ==================================================================
*)
FUNCTION_BLOCK FB_DL_LongPressButton
VAR_INPUT
    bBtn   : BOOL := FALSE; // 按钮输入电平 [-] / the button input level
    bReset : BOOL := FALSE; // 故障复位电平，上升沿清锁存 [-] / the fault reset level
    tShort : TIME := T#100MS; // 短按下限阈值 [毫秒]，须 < tLong / the short press lower threshold
    tLong  : TIME := T#800MS; // 长按阈值 [毫秒]，须 < tXLong / the long press threshold
    tXLong : TIME := T#2S;    // 超长按阈值 [毫秒] / the extra long press threshold
END_VAR
VAR_OUTPUT
    bShortPress : BOOL := FALSE; // 短按单拍脉冲（释放沿回判）[-] / the short press one shot
    bLongPress  : BOOL := FALSE; // 长按单拍脉冲（tLong 阈值沿）[-] / the long press one shot
    bXLongPress : BOOL := FALSE; // 超长按单拍脉冲（tXLong 阈值沿）[-] / the extra long press one shot
    bFaulted    : BOOL := FALSE; // 组态故障锁存指示 [-] / the latched configuration fault indicator
    eErr        : UDINT := 16#0000_0000; // 错误码，0 = 正常 / the error code, zero is ok
    bError      : BOOL := FALSE; // 故障锁存位（与锁存同源，R191）/ the fault bit from the same latch
END_VAR
VAR
    _bInit      : BOOL := FALSE; // 首拍初始化标志（R310）/ the first scan flag
    _bFault     : BOOL := FALSE; // 组态故障锁存副本（仅复位沿清除）/ the fault latch copy
    _bShort     : BOOL := FALSE; // 短拍内部位，段 1 预清段 5 映射 / the internal short bit
    _bLong      : BOOL := FALSE; // 长拍内部位 / the internal long bit
    _bXLong     : BOOL := FALSE; // 超长拍内部位 / the internal extra long bit
    _bLongFired : BOOL := FALSE; // 长按已发标记（释放沿判短按排除用，按压期间保持）/ the long fired flag held during the press
    _bXFired    : BOOL := FALSE; // 超长按已发标记 / the extra long fired flag
    _bCfgBad    : BOOL := FALSE; // 组态非法标记（逐拍重算）/ the configuration fault flag recomputed
    rtBtn       : R_TRIG;  // 按钮按下沿实例，段 0 无条件刷新 / the press edge instance
    ftBtn       : F_TRIG;  // 按钮释放沿实例，段 0 无条件刷新 / the release edge instance
    rtReset     : R_TRIG;  // 复位沿实例，段 0 无条件刷新 / the reset edge instance
    rtLongQ     : R_TRIG;  // 长窗到时沿实例，段 0 无条件刷新 / the long window expiry edge instance
    rtXLongQ    : R_TRIG;  // 超长窗到时沿实例，段 0 无条件刷新 / the extra long expiry edge instance
    tonShort    : TON;     // 短窗计时，段 0 无条件刷新 / the short window timer
    tonLong     : TON;     // 长窗计时 / the long window timer
    tonXLong    : TON;     // 超长窗计时 / the extra long window timer
END_VAR

// 段 0｜定时器与沿检测无条件周期刷新（禁入分支，R7）/ segment 0, the unconditional refresh
rtBtn(CLK := bBtn); // 按下沿 / the press edge
ftBtn(CLK := bBtn); // 释放沿 / the release edge
rtReset(CLK := bReset); // 复位沿 / the reset edge
tonShort(IN := bBtn, PT := tShort); // 短窗计时（按压电平驱动）/ the short window timing
tonLong(IN := bBtn, PT := tLong); // 长窗计时 / the long window timing
tonXLong(IN := bBtn, PT := tXLong); // 超长窗计时 / the extra long window timing
rtLongQ(CLK := tonLong.Q); // 长窗到时沿 / the long expiry edge
rtXLongQ(CLK := tonXLong.Q); // 超长窗到时沿 / the extra long expiry edge

// 段 1｜首拍初始化与单拍标志预清（仅单拍标志入清单，FB32-1；R256）/ segment 1, the first scan init and the one shot preset
IF NOT _bInit THEN // 首拍一拍 / the first scan
    _bInit := TRUE; // 置首拍标志 / raise the first scan flag
    _bFault := FALSE; // 故障锁存显式清零 / clear the fault latch explicitly
    _bLongFired := FALSE; // 长发标记显式清零 / clear the long fired flag explicitly
    _bXFired := FALSE; // 超长发标记显式清零 / clear the extra long fired flag explicitly
END_IF
IF rtReset.Q THEN // 复位沿：清故障锁存（解除路径：复位沿恒可达，R152 自证）/ the reset edge clears the latch
    _bFault := FALSE; // 清锁存 / clear the latch
END_IF
_bShort := FALSE; // 短拍预清零 / preset the short bit false
_bLong := FALSE; // 长拍预清零 / preset the long bit false
_bXLong := FALSE; // 超长拍预清零 / preset the extra long bit false
_bCfgBad := FALSE; // 组态标记预清零 / preset the configuration flag false

// 段 2｜组态域闸（三窗严格递增 + 正值，R239，边界一）/ segment 2, the configuration gate
IF (tShort <= T#0S) OR (tLong <= tShort) OR (tXLong <= tLong) THEN // 递增配比违反或非正 / the monotone ratio violated
    _bCfgBad := TRUE; // 置组态非法标记 / raise the configuration flag
    _bFault := TRUE; // 锁存故障（段 5 出口回放）/ latch the fault
END_IF

// 段 3｜按压中阈值沿分档（故障冻结，边界五；沿只在合法态消费）/ segment 3, the threshold edges during the press
IF (NOT _bFault) AND bBtn THEN // 合法态且按压中 / legal and pressed
    IF rtLongQ.Q AND (NOT _bLongFired) AND (NOT _bXFired) THEN // 长窗到时沿首现 / the long expiry edge first seen
        _bLong := TRUE; // 置长拍 / raise the long bit
        _bLongFired := TRUE; // 锁长发标记（释放沿判短按排除）/ latch the long fired flag
    END_IF
    IF rtXLongQ.Q AND (NOT _bXFired) THEN // 超长窗到时沿首现 / the extra long expiry edge first seen
        _bXLong := TRUE; // 置超长拍 / raise the extra long bit
        _bXFired := TRUE; // 锁超长发标记 / latch the extra long fired flag
    END_IF
END_IF

// 段 4｜释放沿回判短按（短按 = 释放时短窗已到而长按未发，边界二）/ segment 4, the release edge judges the short press
IF ftBtn.Q AND (NOT _bFault) THEN // 合法态释放沿 / a legal release edge
    IF tonShort.Q AND (NOT _bLongFired) AND (NOT _bXFired) THEN // 短窗已到且未触发高档 / the short window met with no higher grade fired
        _bShort := TRUE; // 置短拍 / raise the short bit
    END_IF
    _bLongFired := FALSE; // 释放清长发标记（下一按压新起点）/ clear the long fired flag at the release
    _bXFired := FALSE; // 释放清超长发标记 / clear the extra long fired flag
END_IF

// 段 5｜统一出口（内部副本单点映射；故障冻结全假，R191）/ segment 5, the unified outlet with the frozen fault
bShortPress := _bShort AND (NOT _bFault); // 短拍出口 / the short outlet
bLongPress := _bLong AND (NOT _bFault); // 长拍出口 / the long outlet
bXLongPress := _bXLong AND (NOT _bFault); // 超长拍出口 / the extra long outlet
bFaulted := _bFault; // 故障指示出口 / the fault indicator outlet
bError := _bFault; // 故障位出口（与锁存同源，R191）/ the fault bit outlet
IF _bFault THEN // 故障锁存回放（R187）/ the latched fault replays
    eErr := 16#0001_0640; // 故障级：三档窗组态非法 / fault grade, the illegal window configuration
ELSE // 无故障 / no fault
    eErr := 16#0000_0000; // 正常 / ok
END_IF
END_FUNCTION_BLOCK
