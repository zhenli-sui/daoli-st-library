(*
  ==================================================================
  组件名 Component  : FB_DL_DustCollectorPulse
  分类   Category   : DL_Device
  复杂度 Complexity  : 中
  版本   Version    : 1.0.0
  功能   Purpose    : 布袋除尘器脉冲反吹。压差分级触发（fDpStart 开 / 
                      fDpStop 关回差）；轮巡脉阀（tPulse 得电 → tInterval 间
                      隔 → 下一阀）；清灰无效劣化报警：整轮巡完且压差仍高于
                      fDpHigh 累轮 nRoundMax 轮 → 锁存 bDpHighAlm。LBP 三段
                      骨架（命令→监视→判定）。
  来源   Source     : T2-2-lbp（LBP 三段骨架）
  溯源   Origin     : IEC 61131-3 标准语义的道莅防御性实现；压差回差与脉阀
                      轮巡为行业公知工程语义，clean-room 自研实现，未复制
                      LBP 或任何厂商私有库源码。
  平台   Platform   : 纯 IEC 61131-3（Standard.library: TON / R_TRIG，无私有库）
  分工声明 Split     : 与 FB_DL_SprayNozzleBank 分工——后者做喷嘴组搭接排
                      布，本件做除尘压差触发脉阀轮巡。
  作者   Author     : 道莅代码库 · PLC 编程专家（R59）
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 安全语义：报警 / 非有限压差 / 停止时全阀输出统一出
                         口强制 FALSE（安全侧单点映射，R191）；
                      二 组态域闸：nValves ∈ [1..8]，越域锁存 bError（解除
                         = bReset 沿，R188）；
                      三 阀脉冲窗 / 间隔窗到期即迁（窗口末退出迁移，纪律④）；
                      四 非有限压差置 bBad（纪律②）挂起触发与判定不误报；
                      五 报警锁存解除路径 = bReset 沿（唯一路径，R188 声明）；
                      六 定时器与沿检测全部段 0 无条件周期刷新（R7）；
                      七 无全局变量、无外部变量声明、无物理地址寻址。
  修订记录 Revision  :
    2026-11-21  v1.0.0  R59 首版（批 3 · 序号 14）
  ==================================================================
*)

FUNCTION_BLOCK FB_DL_DustCollectorPulse
VAR_INPUT
    fDpKpa    : LREAL := 0.0;   // 除尘器压差反馈 [千帕] / the dust collector differential pressure [kilopascal]
    fDpStart  : LREAL := 1.2;   // 反吹启动压差阈值 [千帕] / the cleaning start threshold [kilopascal]
    fDpStop   : LREAL := 0.9;   // 反吹停止压差阈值（回差下限）[千帕] / the cleaning stop threshold [kilopascal]
    fDpHigh   : LREAL := 2.0;   // 清灰无效判定压差 [千帕] / the ineffective cleaning verdict pressure [kilopascal]
    nValves   : INT := 8;       // 脉阀数 [只]，域 1..8 / the valve count, one through eight
    tPulse    : TIME := T#150MS; // 脉阀得电时长 [毫秒] / the valve pulse duration [millisecond]
    tInterval : TIME := T#5S;   // 阀间间隔时长 [毫秒] / the valve interval [millisecond]
    nRoundMax : UDINT := 3;     // 无效判定累轮限 [轮] / the ineffective round bound
    bStop     : BOOL := FALSE;  // 停止指令，电平生效 [-] / the stop command, level effective
    bReset    : BOOL := FALSE;  // 报警与组态复位，上升沿生效 [-] / the alarm and config reset, rising edge
END_VAR
VAR_OUTPUT
    aValve     : ARRAY[0..7] OF BOOL; // 脉阀输出组 [-] / the valve outlets
    nValveIdx  : INT  := -1;  // 当前脉阀索引，-1 = 无 [只] / the current valve index, minus one when none
    bValveOn   : BOOL := FALSE; // 当前阀得电进行中 [-] / the current valve energized
    bCleaning  : BOOL := FALSE; // 反吹轮巡进行指示 [-] / the cleaning round robin indicator
    bDpHighAlm : BOOL := FALSE; // 清灰无效劣化报警锁存（解除 = bReset 沿）[-] / the ineffective cleaning alarm latch
    nRoundCnt  : UDINT := 0;  // 无效累轮计数 [轮] / the ineffective round count
    bBad       : BOOL := FALSE; // 非有限压差实时标志 [-] / the non finite pressure flag
    bError     : BOOL := FALSE; // 组态域闸故障锁存 [-] / the config gate fault latch
END_VAR
VAR CONSTANT
    DL_DCP_VMAX   : INT  := 8;           // 阀容量上界 [只] / the valve capacity bound
    DL_DCP_CNTMAX : UDINT := 4294967294; // 计数防回绕上界 [轮] / the counter anti wrap clamp bound
END_VAR
VAR
    _bRun    : BOOL := FALSE; // 轮巡运行锁存（压差回差驱动）/ the round robin run latch, driven by the hysteresis
    _nValve  : INT := 0;   // 轮巡阀寄存 [只] / the round robin valve register
    _bOn     : BOOL := FALSE; // 阀得电相位寄存 / the valve on phase register
    _bWrap   : BOOL := FALSE; // 整轮回绕捕获寄存 / the full round wrap capture register
    _bInit   : BOOL := FALSE; // 首拍初始化标志（R310，真实使用：首拍清阀输出）/ the first scan flag, real use
    _nI      : DINT;       // 阀遍历索引 / the valve loop index
    _bFinDp  : BOOL;       // 压差有限工作量 [-] / the pressure finiteness work flag
    rtReset  : R_TRIG;     // 复位沿，段 0 无条件刷新 / the reset edge
    tonPulse : TON;        // 阀脉冲窗，段 0 无条件刷新 / the valve pulse window
    tonGap   : TON;        // 阀间间隔窗，段 0 无条件刷新 / the valve interval window
END_VAR

// 段 0｜定时器与沿检测无条件周期刷新（禁入分支，R7）/ segment 0, the unconditional refresh
rtReset(CLK := bReset); // 复位沿 / the reset edge
tonPulse(IN := _bOn, PT := tPulse); // 阀脉冲窗 / the valve pulse window
tonGap(IN := _bRun AND (NOT _bOn) AND (NOT tonGap.Q), PT := tInterval); // 间隔窗（自复位单发，R188）/ the interval self reset window

// 段 1｜首拍初始化（R310 真实使用路径）：阀输出显式清零 / segment 1, the first scan init
IF NOT _bInit THEN // 首拍一拍 / the first scan
    _bInit := TRUE; // 置首拍标志 / raise the flag
    FOR _nI := 0 TO DL_DCP_VMAX - 1 DO // 全阀清零 / clear all the valves
        aValve[_nI] := FALSE; // 阀输出清零 / clear the valve outlet
    END_FOR
END_IF

// 段 2｜组态域闸与复位（边界二五，解除路径 = bReset 沿，R188）/ segment 2, the config gate and the reset
IF (nValves < 1) OR (nValves > DL_DCP_VMAX) THEN // 阀数越域 / the valve count out of domain
    bError := TRUE; // 置域闸锁存 / raise the config latch
END_IF
IF rtReset.Q THEN // 复位沿 / the reset edge
    bError := FALSE; // 清域闸锁存 / clear the config latch
    bDpHighAlm := FALSE; // 清劣化报警（唯一解除路径）/ clear the alarm
    nRoundCnt := 0; // 清累轮计数 / clear the round count
END_IF

// 段 3｜压差有限性与回差触发（边界四）/ segment 3, the pressure finiteness and the hysteresis
_bFinDp := (fDpKpa = fDpKpa) AND ((fDpKpa - fDpKpa) = (fDpKpa - fDpKpa)); // 压差有限双判据（R79）/ the finiteness dual verdicts
bBad := NOT _bFinDp; // 拒收实时标志（R191 名实双出口）/ the rejection flag
IF _bFinDp AND (NOT bError) THEN // 有效压差才参与触发 / only the valid pressure drives the trigger
    IF (NOT _bRun) AND (fDpKpa > fDpStart) THEN // 超启动阈值开轮巡 / beyond the start threshold, run
        _bRun := TRUE; // 开轮巡 / start the round robin
    ELSIF _bRun AND (fDpKpa < fDpStop) THEN // 低于回差下限停轮巡 / below the stop threshold, halt
        _bRun := FALSE; // 停轮巡 / halt
        _bOn := FALSE; // 阀断电 / drop the valve
        _nValve := 0; // 阀寄存归零 / reset the valve register
    END_IF
END_IF

// 段 4｜轮巡相位消化（阀脉冲窗与间隔窗窗口末退出迁移，边界三）/ segment 4, the round robin consume
IF _bOn THEN // 阀得电相位 / the valve on phase
    IF tonPulse.Q THEN // 脉冲窗到期（窗口末退出迁移）/ the pulse expired
        _bOn := FALSE; // 阀断电进间隔 / drop the valve into the interval
    END_IF
ELSIF _bRun AND (NOT bError) AND (NOT bDpHighAlm) AND (NOT bStop) AND _bFinDp THEN // 间隔相位（有效运行窗）/ the interval phase in the valid window
    IF tonGap.Q THEN // 间隔窗到期（自复位单发，窗口末退出迁移）/ the interval expired, self reset one shot
        _nValve := _nValve + 1; // 阀推进 / advance the valve
        IF _nValve >= nValves THEN // 整轮回绕 / the full round wrap
            _nValve := 0; // 回首阀 / back to the first valve
            _bWrap := TRUE; // 捕获整轮 / capture the full round
        END_IF
        _bOn := TRUE; // 下一阀得电 / energize the next valve
    END_IF
END_IF

// 段 5｜清灰无效劣化判定（整轮巡完且压差仍高，累轮达限锁存，边界五）/ segment 5, the ineffective cleaning verdict
IF _bWrap THEN // 整轮捕获沿 / the full round captured
    _bWrap := FALSE; // 捕获消化 / absorb the capture
    IF _bFinDp AND (fDpKpa > fDpHigh) THEN // 轮末压差仍高于判定限 / the pressure still high at the round end
        IF nRoundCnt < DL_DCP_CNTMAX THEN // 计数防回绕 / the wrap guard
            nRoundCnt := nRoundCnt + 1; // 累轮推进 / advance the round count
        END_IF
        IF nRoundCnt >= nRoundMax THEN // 达累轮限 / at the round bound
            bDpHighAlm := TRUE; // 置劣化报警锁存（成因独立，R190）/ raise the alarm latch
            _bRun := FALSE; // 停轮巡（报警安全侧）/ halt the round robin
            _bOn := FALSE; // 阀断电 / drop the valve
        END_IF
    END_IF
END_IF

// 段 6｜统一出口：阀输出单点安全映射（边界一）/ segment 6, the unified outlet
FOR _nI := 0 TO DL_DCP_VMAX - 1 DO // 全阀重映射 / remap all the valves
    aValve[_nI] := FALSE; // 先全断（安全侧基线）/ all off first, the safe baseline
END_FOR
IF _bOn AND (NOT bError) AND (NOT bDpHighAlm) AND (NOT bStop) AND _bFinDp THEN // 阀得电有效窗 / the valid energize window
    IF (_nValve >= 0) AND (_nValve < nValves) THEN // 阀界闸（防越界写）/ the valve bound gate
        aValve[_nValve] := TRUE; // 当前阀得电 / the current valve on
    END_IF
END_IF
nValveIdx := _nValve; // 阀索引出口 / the valve index outlet
bValveOn := _bOn; // 得电指示（R191 名实双出口）/ the energize indicator
bCleaning := _bRun; // 轮巡指示 / the round robin indicator
END_FUNCTION_BLOCK
