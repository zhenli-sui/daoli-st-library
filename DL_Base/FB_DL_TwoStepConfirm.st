(*
  ==================================================================
  组件名 Component  : FB_DL_TwoStepConfirm
  分类   Category   : DL_Base
  复杂度 Complexity  : 中
  版本   Version    : 1.0.2
  功能   Purpose    : 两步确认防误触发。首按（上升沿）进入预备态 bArmed，
                      限窗 tArmWindow 内二按（再次上升沿）才输出确认单脉冲
                      bConfirmed；预备窗超时自动复位并输出超时单脉冲
                      bTimeout。IEC 60204 人机交互公开语义（双手/两步确认
                      防误触发思想），与 FB_DL_HoldRepeatButton 按住重复分工。
  来源   Source     : self-std（IEC 60204 公开人机交互语义）
  溯源   Origin     : IEC 60204-1 两步控制公开条款语义，clean-room 自研实现，
                      未复制任何厂商私有库源码。
  平台   Platform   : 纯 IEC 61131-3（Standard.library: TON / R_TRIG，无私有库）
  分工声明 Split     : 与 FB_DL_HoldRepeatButton 分工——后者做按住重复触发，
                      本件做两步防误确认。
  作者   Author     : 道莅代码库 · PLC 编程专家（R59）
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 确认/超时均为单拍脉冲输出，每拍先统一预清零再置位
                         （本库纪律③，防粘滞）；
                      二 预备窗 tArmWindow 超时自动复位预备态（窗口末退出迁
                         移，本库纪律④）；
                      三 busy 态（已预备）期间忽略一切新输入语义，只接受二
                         按 / 超时两条出口；
                      四 定时器与沿检测全部段 0 无条件周期刷新（R7）；
                      五 段序铁律：段 3 先消化本拍输入沿、段 4 才做超时迁移，
                         窗口到期拍与二按沿同拍时二按优先，bTimeout 不在该拍
                         发码（R275 同拍竞态口径）；
                      六 无全局变量、无外部变量声明、无物理地址寻址。
  修订记录 Revision  :
    2026-11-21  v1.0.0  R59 首版（批 1 · 序号 2）
    2026-11-21  v1.0.1  修 R275 同拍竞态：超时迁移前预消化本拍二按沿
                        （原 v1.0.0 段 3 超时先清 _bArmed，段 4 读假预备态把
                         二按当首按重新武装，二按被吞需按第三次；本次仅调整
                         段序与事件优先判据，对外引脚与语义一字不动）
    2026-11-21  v1.0.2  R61 轻项：段 4 超时判据补 AND _bArmed 双保险（R60
                        复核残留项；语义不变，仅防御性收紧）
  ==================================================================
*)

FUNCTION_BLOCK FB_DL_TwoStepConfirm
VAR_INPUT
    bBtn       : BOOL := FALSE;  // 确认按钮输入，上升沿语义 [-] / the confirm button input, rising edge semantics
    tArmWindow : TIME := T#3S;   // 二按限窗时长 [毫秒] / the second press window [millisecond]
END_VAR
VAR_OUTPUT
    bArmed     : BOOL := FALSE;  // 预备态指示（首按已受理等二按）[-] / the armed indicator, first press accepted
    bConfirmed : BOOL := FALSE;  // 两步确认成立单脉冲（单拍）[-] / the confirmed one shot pulse, single scan
    bTimeout   : BOOL := FALSE;  // 预备窗超时单脉冲（单拍）[-] / the window timeout one shot pulse, single scan
    bError     : BOOL := FALSE;  // 预留故障位（本件无浮点运算，恒常假）[-] / the reserved fault bit, constant false
END_VAR
VAR
    _bInit     : BOOL := FALSE; // 首拍初始化标志（R310，真实使用：首拍清预备态）/ the first scan flag, real use
    _bArmed    : BOOL := FALSE; // 预备态锁存位（区分于实时镜像 bArmed）/ the armed latch bit
    _bEvtTaken : BOOL := FALSE; // 同拍事件已消化标志（单拍，段 2 预清，R275）/ the same scan event consumed flag, single scan preset in segment two
    rtBtn      : R_TRIG;        // 按钮沿检测，段 0 无条件刷新 / the button edge, refreshed unconditionally
    tonArm     : TON;           // 二按限窗定时器，段 0 无条件刷新 / the arm window timer, refreshed unconditionally
END_VAR

// 段 0｜定时器与沿检测无条件周期刷新（禁入分支，R7）/ segment 0, the unconditional refresh
rtBtn(CLK := bBtn); // 按钮沿 / the button edge
tonArm(IN := _bArmed, PT := tArmWindow); // 限窗计时，预备态驱动 / the window timing, driven by the armed latch

// 段 1｜首拍初始化（R310 真实使用路径）：预备态显式清零 / segment 1, the first scan init
IF NOT _bInit THEN // 首拍一拍 / the first scan
    _bInit := TRUE; // 置首拍标志 / raise the first scan flag
    _bArmed := FALSE; // 预备态显式清零（编译缺省之上的显式安全预置）/ clear the armed latch explicitly
END_IF

// 段 2｜单拍脉冲与单拍标志每拍前置清零（本库纪律③防粘滞；仅单拍标志入此清单，R32 FB32-1）/ segment 2, the per scan preset of the one shot pulses and flags
bConfirmed := FALSE; // 确认脉冲预清零 / preset the confirmed pulse false
bTimeout := FALSE; // 超时脉冲预清零 / preset the timeout pulse false
_bEvtTaken := FALSE; // 同拍事件消化标志预清零（先清后置，R53）/ preset the same scan consumed flag false, clear before set

// 段 3｜本拍输入沿预消化（R275：合法事件先于超时迁移消化，段序在段 4 之前）/ segment 3, the same scan input edge pre-digest, the legal event ahead of the timeout migration
IF rtBtn.Q THEN // 按钮上升沿 / the button rising edge
    _bEvtTaken := TRUE; // 标记本拍已消化事件（段 4 据此不再发超时）/ mark the event consumed this scan, the segment four skips the timeout
    IF NOT _bArmed THEN // 首按：进入预备 / the first press, arm
        _bArmed := TRUE; // 置预备态（限窗同步启动）/ raise the armed latch
    ELSE // 二按：确认成立 / the second press, confirmed
        _bArmed := FALSE; // 退出预备态 / leave the armed state
        bConfirmed := TRUE; // 置确认单脉冲 / raise the confirmed pulse
    END_IF
END_IF

// 段 4｜预备窗超时迁移（窗口末退出，边界二；同拍已消化输入沿则不迁移，R275）/ segment 4, the window expiry migration, skipped when the same scan edge is already consumed
IF tonArm.Q AND (NOT _bEvtTaken) AND _bArmed THEN // 限窗到期且本拍无合法事件且仍在预备态（R61 轻项：_bArmed 双保险）/ the window expired with no legal event this scan and still armed, the double guard
    _bArmed := FALSE; // 自动退出预备态 / auto leave the armed state
    bTimeout := TRUE; // 置超时单脉冲 / raise the timeout pulse
END_IF

// 段 5｜统一出口（实时镜像与锁存位同源，R191 名实双出口）/ segment 5, the unified outlet
bArmed := _bArmed; // 预备态输出 / the armed outlet
END_FUNCTION_BLOCK
