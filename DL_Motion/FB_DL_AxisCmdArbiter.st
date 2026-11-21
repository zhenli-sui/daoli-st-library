(*
  ==================================================================
  组件名 Component  : FB_DL_AxisCmdArbiter
  分类   Category   : DL_Motion
  复杂度 Complexity  : 中
  版本   Version    : 1.0.1
  功能   Purpose    : 轴驱动命令源优先级仲裁。四级命令源 安全 > 手动 > 自动 > 上位，
                      每拍全量重判，输出胜出源标签与整份命令字（携带源身份，
                      防「赢了仲裁丢了身份」），源切换出单拍脉冲。
  来源   Source     : t1-6-plcopen（PLCopen 运动接口命令源语义）
  溯源   Origin     : 命令源优先级仲裁属公开运动控制语义，clean-room 自研实现，
                      未复制 PLCopen 官方库或任何厂商源码。
  平台   Platform   : 纯 IEC 61131-3（IF / ELSIF / CASE / 标准转换函数），三平台通用
  分工声明 Split     : 与 FB_DL_ModeArbiter（单元模式级属主）分工——后者仲裁整机/
                      单元运行模式；本件只仲裁单轴驱动命令源，不发运动指令、
                      不判轴状态、不自造轴状态枚举（PLCopen 纪律，R277）。
  作者   Author     : 道莅代码库 · PLC 编程专家（R60）
  ------------------------------------------------------------------
  归属 Ownership     : E_DL_AxisCmdSrc 与 ST_DL_AxisCmd 的属主为本文件（全库唯一
                      定义，R264）；引用件只引用不重声明。
  边界 Boundary     :
                      一 纯组合件，每拍全量重判，无相位机（R227 显式声明）：不存在
                         等待相、不存在陈旧保持，胜出结果即本拍输入的函数；
                      二 优先级写死 安全(10) > 手动(20) > 自动(30) > 上位(40)，
                         枚举数值小者优先；源标签不符（如 stSafe 携带 eAuto）
                         视为该源未请求，不参与仲裁；
                      三 输出命令字整体取自胜出源结构体并回写胜出源标签，调用方
                         据 eWinner 与 stWinnerCmd.eSrc 双重可判来源；
                      四 源切换单拍脉冲 bSwitched 统一出口段每拍先预置 FALSE、
                         分支只写 TRUE（R256）；
                      五 无请求源时输出 eNone 与安全侧零命令（bAnyActive = FALSE）；
                      六 使能 bEnable = FALSE 时语义为「降级为零命令 + 置标志」
                         （eWinner = eNone），不保持上拍命令（R191 声明行）；
                      七 有界豁免登记（R272，D11 返修）：非有限闸只判胜出源 _stWin
                         的两个浮点字段——非胜出源命令字不入出口、不参与判据
                         换算，属有界豁免（机检口径 2/8 显式声明，非漏闸）。
  错误码   Codes    :
    16#0004_0620【信息级】本拍无任何命令源请求（胜出 eNone）
    16#0004_0621【信息级】发生源切换（bSwitched 同拍置位）
    16#0004_0622【故障级】胜出源命令字含非有限量，已降级为零命令
  验收   Acceptance :
    算法已证（脚本）：未跑 ｜ 编译器已证（三平台）：未跑
    V1 仅自动源请求 → eWinner = eAuto、命令字等于自动源
    V2 安全源与手动源同拍请求 → eWinner = eSafe（小者优先）
    V3 全部源 eNone → eWinner = eNone、命令零值、码 0620
  修订记录 Revision  :
    2026-11-21  v1.0.0  R60 首版（批 3 · 序号 11）
    2026-11-21  v1.0.1  R61 返修：D1 降级路径 _eWinner 同步落 eNone（双通道
                        一致）；D2 增 _bFault 锁存位 + bReset 复位引脚，bError
                        改为锁存回放口径（R187）；D11 边界段登记非胜出源豁免
  ==================================================================
*)

TYPE E_DL_AxisCmdSrc :
(
    eNone := 0,  // 无源：本拍无命令请求 / none, no command source requests this scan
    eSafe := 10, // 安全源：最高优先级 / the safety source with the top priority
    eJog  := 20, // 手动源：次高优先级 / the jog source
    eAuto := 30, // 自动源：第三优先级 / the automatic source
    eHost := 40  // 上位源：最低优先级 / the host source with the lowest priority
);
END_TYPE

TYPE ST_DL_AxisCmd :
STRUCT
    eSrc     : E_DL_AxisCmdSrc := E_DL_AxisCmdSrc.eNone; // 命令来源标签 [源] / the command source label
    fVelMmS  : LREAL := 0.0;                             // 速度指令 [毫米每秒] / the velocity command
    fPosMm   : LREAL := 0.0;                             // 位置指令 [毫米] / the position command
    uFlags   : UDINT := 16#0000_0000;                    // 命令标志位 [位图] / the command flag word
END_STRUCT
END_TYPE

FUNCTION_BLOCK FB_DL_AxisCmdArbiter
VAR_INPUT
    bEnable : BOOL := TRUE;              // 使能，FALSE 时降级为零命令（边界六）/ the enable, false degrades to the zero command
    bReset  : BOOL := FALSE;             // 故障复位电平，上升沿清非有限故障锁存（D2 返修新增）/ the fault reset level, the rising edge clears the non finite latch
    stSafe  : ST_DL_AxisCmd;             // 安全源命令字 [源结构] / the safety source command
    stJog   : ST_DL_AxisCmd;             // 手动源命令字 [源结构] / the jog source command
    stAuto  : ST_DL_AxisCmd;             // 自动源命令字 [源结构] / the automatic source command
    stHost  : ST_DL_AxisCmd;             // 上位源命令字 [源结构] / the host source command
END_VAR
VAR_OUTPUT
    eWinner     : E_DL_AxisCmdSrc := E_DL_AxisCmdSrc.eNone; // 胜出源 [源] / the winning source
    stWinnerCmd : ST_DL_AxisCmd;                            // 胜出命令字（携带源标签）[源结构] / the winning command carrying its label
    bAnyActive  : BOOL := FALSE;                            // 存在任一源请求 [-] / any source requests
    bSwitched   : BOOL := FALSE;                            // 源切换单拍脉冲 [-] / the source switch one shot pulse
    bError      : BOOL := FALSE;                            // 故障锁存位 [-] / the latched fault bit
    eErr        : UDINT := 16#0000_0000;                    // 错误码，0 = 正常 / the error code, zero is ok
END_VAR
VAR
    _bInit     : BOOL := FALSE;                                // 首拍初始化标志（R310）/ the first scan flag
    _eWinner   : E_DL_AxisCmdSrc := E_DL_AxisCmdSrc.eNone;     // 胜出源副本，段 6 单点映射 / the winning source copy
    _ePrev     : E_DL_AxisCmdSrc := E_DL_AxisCmdSrc.eNone;     // 上拍胜出源（切换沿判据，保持型不入预清，FB32-1）/ the previous winner, held across the scans
    _stWin     : ST_DL_AxisCmd;                                // 胜出命令字副本 / the winning command copy
    _bSwitched : BOOL := FALSE;                                // 切换单拍内部位，段 1 预清段 6 映射 / the internal switch bit, preset then mapped
    _bNoneReq  : BOOL := FALSE;                                // 本拍无源请求标记（逐拍重算）[-] / the no request flag, recomputed every scan
    _bNonFin   : BOOL := FALSE;                                // 胜出命令非有限标记（逐拍重算）[-] / the non finite winner flag, recomputed every scan
    _bFault    : BOOL := FALSE;                                // 故障锁存位（非有限降级置位，复位沿清除，D2 返修）/ the fault latch bit, set on the degrade and cleared by the reset edge
    rtReset    : R_TRIG;                                       // 复位沿实例，段 0 无条件刷新（D2 返修新增）/ the reset edge instance, refreshed unconditionally
END_VAR

// 段 0｜复位沿无条件周期刷新（禁入分支，R7；D2 返修新增）/ segment 0, the unconditional refresh of the reset edge
rtReset(CLK := bReset); // 故障复位沿 / the fault reset edge

// 段 1｜首拍初始化与单拍标志预清（仅单拍标志入清单，R32 FB32-1；R256）/ segment 1, the first scan init and the one shot preset
IF rtReset.Q THEN // 复位沿：清故障锁存（解除路径：复位沿恒可达，R152 自证）/ the reset edge clears the fault latch, the release path is reachable
    _bFault := FALSE; // 清故障锁存 / clear the fault latch
END_IF
IF NOT _bInit THEN // 首拍一拍 / the first scan
    _bInit := TRUE; // 置首拍标志 / raise the first scan flag
    _eWinner := E_DL_AxisCmdSrc.eNone; // 胜出源显式落无源 / place the winner to none explicitly
    _ePrev := E_DL_AxisCmdSrc.eNone; // 上拍源显式落无源 / place the previous winner to none explicitly
END_IF
_bSwitched := FALSE; // 切换脉冲预清零 / preset the switch pulse false
_bNoneReq := FALSE; // 无源标记预清零 / preset the no request flag false
_bNonFin := FALSE; // 非有限标记预清零 / preset the non finite flag false

// 段 2｜优先级仲裁（每拍全量重判，数值小者优先，边界二）/ segment 2, the priority arbitration recomputed every scan
_eWinner := E_DL_AxisCmdSrc.eNone; // 胜出源先置无源 / preset the winner to none
IF bEnable AND (stSafe.eSrc = E_DL_AxisCmdSrc.eSafe) THEN // 安全源请求且标签自洽 / the safety source requests with its own label
    _eWinner := E_DL_AxisCmdSrc.eSafe; // 安全源胜出（最高优先级）/ the safety source wins
ELSIF bEnable AND (stJog.eSrc = E_DL_AxisCmdSrc.eJog) THEN // 手动源请求 / the jog source requests
    _eWinner := E_DL_AxisCmdSrc.eJog; // 手动源胜出 / the jog source wins
ELSIF bEnable AND (stAuto.eSrc = E_DL_AxisCmdSrc.eAuto) THEN // 自动源请求 / the automatic source requests
    _eWinner := E_DL_AxisCmdSrc.eAuto; // 自动源胜出 / the automatic source wins
ELSIF bEnable AND (stHost.eSrc = E_DL_AxisCmdSrc.eHost) THEN // 上位源请求 / the host source requests
    _eWinner := E_DL_AxisCmdSrc.eHost; // 上位源胜出 / the host source wins
END_IF
IF _eWinner = E_DL_AxisCmdSrc.eNone THEN // 无源请求（含失能）/ no source requests or disabled
    _bNoneReq := TRUE; // 置无源标记 / raise the no request flag
END_IF

// 段 3｜胜出命令字整份搬运（携带源标签，边界三；CASE 逐源取，ELSE 兜零命令）/ segment 3, the winning command transfer with the source label
CASE _eWinner OF
    E_DL_AxisCmdSrc.eSafe: // 安全源 / the safety source
        _stWin := stSafe; // 整份搬运 / transfer the whole structure
        _stWin.eSrc := E_DL_AxisCmdSrc.eSafe; // 源标签归一（防调用方填错）/ normalise the label against a caller mistake
    E_DL_AxisCmdSrc.eJog: // 手动源 / the jog source
        _stWin := stJog; // 整份搬运 / transfer the whole structure
        _stWin.eSrc := E_DL_AxisCmdSrc.eJog; // 源标签归一 / normalise the label
    E_DL_AxisCmdSrc.eAuto: // 自动源 / the automatic source
        _stWin := stAuto; // 整份搬运 / transfer the whole structure
        _stWin.eSrc := E_DL_AxisCmdSrc.eAuto; // 源标签归一 / normalise the label
    E_DL_AxisCmdSrc.eHost: // 上位源 / the host source
        _stWin := stHost; // 整份搬运 / transfer the whole structure
        _stWin.eSrc := E_DL_AxisCmdSrc.eHost; // 源标签归一 / normalise the label
    ELSE // 无源或非法枚举值：零命令（安全侧，边界五）/ none or an illegal value, the zero command
        _stWin.eSrc := E_DL_AxisCmdSrc.eNone; // 标签无源 / the label none
        _stWin.fVelMmS := 0.0; // 速度零 / the zero velocity
        _stWin.fPosMm := 0.0; // 位置零 / the zero position
        _stWin.uFlags := 16#0000_0000; // 标志零 / the zero flags
END_CASE

// 段 4｜胜出命令非有限闸（安全侧零命令，不镜像可能被污染的量，R273）/ segment 4, the non finite gate on the winning command
IF (_stWin.fVelMmS <> _stWin.fVelMmS) OR ((_stWin.fVelMmS - _stWin.fVelMmS) <> (_stWin.fVelMmS - _stWin.fVelMmS)) THEN // 速度非有限 / the velocity is not finite
    _bNonFin := TRUE; // 置非有限标记 / raise the non finite flag
END_IF
IF (_stWin.fPosMm <> _stWin.fPosMm) OR ((_stWin.fPosMm - _stWin.fPosMm) <> (_stWin.fPosMm - _stWin.fPosMm)) THEN // 位置非有限 / the position is not finite
    _bNonFin := TRUE; // 置非有限标记 / raise the non finite flag
END_IF
IF _bNonFin THEN // 非有限：降级为零命令 / degrade to the zero command
    _bFault := TRUE; // 锁存故障（D2：故障级码锁存至复位沿，R187）/ latch the fault until the reset edge
    _eWinner := E_DL_AxisCmdSrc.eNone; // 胜出源同步落无源（D1：降级双通道一致，R283）/ sink the winner to none in step with the label
    _stWin.eSrc := E_DL_AxisCmdSrc.eNone; // 标签降级（不再宣称来源）/ degrade the label
    _stWin.fVelMmS := 0.0; // 速度零 / the zero velocity
    _stWin.fPosMm := 0.0; // 位置零 / the zero position
    _stWin.uFlags := 16#0000_0000; // 标志零 / the zero flags
END_IF

// 段 5｜源切换沿判据（保持型上拍源，边界四）/ segment 5, the source switch edge
IF _eWinner <> _ePrev THEN // 与上拍胜出源不同 / differs from the previous winner
    _bSwitched := TRUE; // 置切换单拍 / raise the switch pulse
END_IF
_ePrev := _eWinner; // 上拍源快照（主体末行赋值，跨拍保持）/ snapshot the winner at the body end

// 段 6｜统一出口（内部副本单点映射，R180；故障码回放，R187）/ segment 6, the unified outlet
eWinner := _eWinner; // 胜出源出口 / the winner outlet
stWinnerCmd := _stWin; // 胜出命令字出口 / the winning command outlet
bAnyActive := NOT _bNoneReq; // 有源请求出口 / the any request outlet
bSwitched := _bSwitched; // 切换单拍出口 / the switch pulse outlet
IF _bFault THEN // 故障锁存回放优先（D2：锁存至复位沿，R187）/ the latched fault replays first until the reset edge
    bError := TRUE; // 故障锁存位出口（与 _bFault 同源，R191）/ the fault outlet from the same latch
    eErr := 16#0004_0622; // 故障级：胜出命令含非有限量（锁存回放）/ fault grade, a non finite command quantity, replayed
ELSIF _bNoneReq THEN // 无源请求 / no request
    bError := FALSE; // 无故障 / no fault
    eErr := 16#0004_0620; // 信息级：无任何命令源请求 / informational, no source requests
ELSIF _bSwitched THEN // 源切换 / a source switch
    bError := FALSE; // 无故障 / no fault
    eErr := 16#0004_0621; // 信息级：发生源切换 / informational, a source switch happened
ELSE // 无事件 / no event
    bError := FALSE; // 无故障 / no fault
    eErr := 16#0000_0000; // 正常 / ok
END_IF
END_FUNCTION_BLOCK
