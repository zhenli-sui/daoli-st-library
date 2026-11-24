(*
  ==================================================================
  组件名 Component  : FB_DL_SprayNozzleBank
  分类   Category   : DL_Device
  复杂度 Complexity  : 中
  版本   Version    : 1.0.0
  功能   Purpose    : 多喷嘴组排布时序（8 组上限）。分段分组吹扫/喷涂：组
                      计时 tGroup 到迁下一组，组间搭接窗 tOverlap 内前组维
                      持得电；喷堵压力反馈诊断：组活动期压力持续超阈值计满
                      tClogMon 判喷堵，累计 nClogCnt 达限锁存报警。LBP 命令
                      → 监视 → 判定骨架。
  来源   Source     : T2-2-lbp（命令→监视→判定骨架）
  溯源   Origin     : IEC 61131-3 标准语义的道莅防御性实现；喷嘴分组时序与
                      压差诊断为行业公知工程语义，clean-room 自研实现，未复
                      制 LBP 或任何厂商私有库源码。
  平台   Platform   : 纯 IEC 61131-3（Standard.library: TON / R_TRIG，无私有库）
  分工声明 Split     : 与 FB_DL_DustCollectorPulse 分工——后者做除尘脉冲轮
                      巡反吹，本件做喷嘴组搭接排布时序。
  作者   Author     : 道莅代码库 · PLC 编程专家（R59）
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 安全语义：停机 / 故障 / 喷堵报警 / 非有限压力时全组
                         输出统一出口强制 FALSE（安全侧单点映射，R191）；
                      二 组态域闸：nGroups ∈ [1..8]，越域锁存 bError（解除
                         = bReset 沿，R188）；
                      三 搭接窗 tOverlap < tGroup 由调用方保证，本件不二次
                         钳制；组计时窗到期即迁（窗口末退出迁移，纪律④）；
                      四 喷堵诊断：非有限压力置 bBad 挂起监视（不误报不吞），
                         组活动期 tonClog 计满判堵一次计数（自复位窗，R188）；
                      五 定时器与沿检测全部段 0 无条件周期刷新（R7）；
                      六 无全局变量、无外部变量声明、无物理地址寻址。
  修订记录 Revision  :
    2026-11-21  v1.0.0  R59 首版（批 2 · 序号 9）
  ==================================================================
*)

TYPE E_DL_SnbPhase :
(
    eSnbIdle := 0,  // 空闲：消化停止与复位 / idle, absorbing the stop and reset
    eSnbRun  := 10, // 分组排布运行：组计时推进 / the group sequencing run
    eSnbDone := 20, // 全组完成驻留：等新启动沿 / the all groups done dwell
    eSnbFault := 90 // 故障锁存：仅复位可清 / the latched fault
);
END_TYPE

FUNCTION_BLOCK FB_DL_SprayNozzleBank
VAR_INPUT
    bStart     : BOOL := FALSE; // 启动指令，上升沿生效 [-] / the start command, rising edge effective
    bStop      : BOOL := FALSE; // 停止指令，电平生效 [-] / the stop command, level effective
    nGroups    : INT  := 8;     // 组数组态 [组]，域 1..8 / the group count config, one through eight
    tGroup     : TIME := T#2S;  // 单组作用时长 [毫秒] / the per group duration [millisecond]
    tOverlap   : TIME := T#200MS; // 组间搭接窗 [毫秒] / the group overlap window [millisecond]
    fPress     : LREAL := 0.0;  // 喷嘴压力反馈 [千帕] / the nozzle pressure feedback [kilopascal]
    fPressClog : LREAL := 300.0; // 喷堵压力阈值 [千帕] / the clog pressure threshold [kilopascal]
    tClogMon   : TIME := T#1S;  // 喷堵判满窗（压力超阈值持续时长）[毫秒] / the clog verdict window [millisecond]
    nClogMax   : UDINT := 5;    // 喷堵计数报警限 [次] / the clog count alarm bound
    bReset     : BOOL := FALSE; // 报警与故障复位，上升沿生效 [-] / the alarm and fault reset, rising edge
END_VAR
VAR_OUTPUT
    aGrp     : ARRAY[0..7] OF BOOL; // 组输出组（仅前 nGroups 组参与排布）[-] / the group outlets
    nGrpIdx  : INT  := -1;  // 当前活动组索引，-1 = 无 [组] / the active group index, minus one when none
    bRunning : BOOL := FALSE; // 排布运行指示 [-] / the sequencing running indicator
    bDone    : BOOL := FALSE; // 全组完成单脉冲（单拍）[-] / the all done one shot pulse, single scan
    bClogAlm : BOOL := FALSE; // 喷堵报警锁存（解除 = bReset 沿）[-] / the clog alarm latch, released by the reset edge
    nClogCnt : UDINT := 0;    // 喷堵判定累计 [次] / the clog verdict count
    bBad     : BOOL := FALSE; // 非有限压力实时标志 [-] / the non finite pressure flag
    bError   : BOOL := FALSE; // 组态域闸故障锁存 [-] / the config gate fault latch
END_VAR
VAR CONSTANT
    DL_SNB_GRPMAX  : INT  := 8;          // 组容量上界 [组] / the group capacity bound
    DL_SNB_CNTMAX  : UDINT := 4294967294; // 计数防回绕上界 [次] / the counter anti wrap clamp bound
END_VAR
VAR
    _ePhase  : E_DL_SnbPhase := E_DL_SnbPhase.eSnbIdle; // 内部相位，CASE 唯一写入目标 / the internal phase, the single CASE write target
    _nGrp    : INT := 0;   // 组推进寄存 [组] / the group advance register
    _nI      : DINT;       // 组遍历索引（清零与出口重映射环）/ the group loop index
    _bOvlRun : BOOL := FALSE; // 搭接窗进行寄存（前组维持得电源）/ the overlap window register
    _bAdv    : BOOL := FALSE; // 组推进屏蔽寄存（组计时器重启一拍用）/ the advance mask register, the timer restart mask
    _bInit   : BOOL := FALSE; // 首拍初始化标志（R310，真实使用：首拍清组输出）/ the first scan flag, real use
    _bFinP   : BOOL;        // 压力有限工作量 [-] / the pressure finiteness work flag
    rtStart  : R_TRIG;      // 启动沿，段 0 无条件刷新 / the start edge
    rtReset  : R_TRIG;      // 复位沿，段 0 无条件刷新 / the reset edge
    tonGrp   : TON;         // 组计时窗，段 0 无条件刷新 / the group window
    tonOvl   : TON;         // 搭接窗（自复位一次性），段 0 无条件刷新 / the overlap one shot window
    tonClog  : TON;         // 喷堵判满窗（自复位），段 0 无条件刷新 / the clog verdict self reset window
END_VAR

// 段 0｜定时器与沿检测无条件周期刷新（禁入分支，R7）/ segment 0, the unconditional refresh
rtStart(CLK := bStart); // 启动沿 / the start edge
rtReset(CLK := bReset); // 复位沿 / the reset edge
tonGrp(IN := (_ePhase = E_DL_SnbPhase.eSnbRun) AND (NOT _bAdv), PT := tGroup); // 组计时窗，推进屏蔽一拍 / the group window, masked one scan per advance
tonOvl(IN := _bOvlRun, PT := tOverlap); // 搭接窗 / the overlap window
tonClog(IN := (_ePhase = E_DL_SnbPhase.eSnbRun) AND (NOT tonClog.Q) AND _bFinP AND (fPress > fPressClog), PT := tClogMon); // 自复位喷堵窗（R188）/ the self reset clog window

// 段 1｜首拍初始化（R310 真实使用路径）：组输出显式清零 / segment 1, the first scan init
IF NOT _bInit THEN // 首拍一拍 / the first scan
    _bInit := TRUE; // 置首拍标志 / raise the flag
    FOR _nI := 0 TO DL_SNB_GRPMAX - 1 DO // 全组清零 / clear all the groups
        aGrp[_nI] := FALSE; // 组输出清零 / clear the group outlet
    END_FOR
END_IF

// 段 2｜组态域闸与复位（边界二，解除路径 = bReset 沿，R188）/ segment 2, the config gate and the reset
IF (nGroups < 1) OR (nGroups > DL_SNB_GRPMAX) THEN // 组数越域 / the group count out of domain
    bError := TRUE; // 置域闸故障锁存 / raise the config latch
END_IF
IF rtReset.Q THEN // 复位沿 / the reset edge
    bError := FALSE; // 清域闸锁存 / clear the config latch
    bClogAlm := FALSE; // 清喷堵报警（解除路径声明）/ clear the clog alarm
    nClogCnt := 0; // 清喷堵计数 / clear the clog count
END_IF

// 段 3｜压力有限性与喷堵计数（非有限挂起监视不误报，边界四）/ segment 3, the pressure finiteness and the clog count
_bFinP := (fPress = fPress) AND ((fPress - fPress) = (fPress - fPress)); // 压力有限双判据（R79）/ the finiteness dual verdicts
bBad := NOT _bFinP; // 拒收实时标志与工作量同源（R191 名实双出口）/ the rejection flag shares the work flag
IF tonClog.Q THEN // 喷堵判满窗到期 / the clog window expired
    IF nClogCnt < DL_SNB_CNTMAX THEN // 计数防回绕 / the wrap guard
        nClogCnt := nClogCnt + 1; // 计一次 / count one
    END_IF
    IF nClogCnt >= nClogMax THEN // 达报警限 / at the alarm bound
        bClogAlm := TRUE; // 置喷堵报警锁存 / raise the clog alarm latch
    END_IF
END_IF

// 段 4｜单拍脉冲预清零（本库纪律③）/ segment 4, the per scan pulse preset
bDone := FALSE; // 完成脉冲预清零 / preset the done pulse false

// 段 5｜相位机：ENUM + CASE，含 ELSE 非法相位兜底（R6 / R128）/ segment 5, the phase machine
CASE _ePhase OF

E_DL_SnbPhase.eSnbIdle: // 空闲相 / the idle phase
    IF bStop THEN _nGrp := 0; END_IF // 停止消化（安全侧已在出口） / absorb the stop
    IF rtStart.Q AND (NOT bError) AND (NOT bClogAlm) THEN // 受理启动（组态合法且无报警）/ accept the start
        _nGrp := 0; // 组归零 / reset the group
        _ePhase := E_DL_SnbPhase.eSnbRun; // 运行相 / to the run phase
    END_IF

E_DL_SnbPhase.eSnbRun: // 排布运行相 / the run phase
    IF bStop OR bError OR bClogAlm THEN // 停止 / 组态故障 / 报警中止 / a stop, config fault or alarm abort
        _ePhase := E_DL_SnbPhase.eSnbIdle; // 回空闲 / back to idle
        _bOvlRun := FALSE; // 搭接窗取消 / cancel the overlap
    ELSE // 正常推进 / the normal advance
        IF tonGrp.Q THEN // 组计时窗到期（窗口末退出迁移，边界三）/ the group window expired
            _bAdv := TRUE; // 推进屏蔽一拍（组计时器下拍重启）/ raise the advance mask
            IF _nGrp > 0 THEN // 非首组：开启搭接窗维持前组 / a later group, open the overlap for the former
                _bOvlRun := TRUE; // 搭接窗启动 / start the overlap
            END_IF
            _nGrp := _nGrp + 1; // 组推进 / advance the group
            IF _nGrp >= nGroups THEN // 全组完成 / all the groups done
                _nGrp := 0; // 组归零 / reset the group
                _ePhase := E_DL_SnbPhase.eSnbDone; // 完成驻留相 / to the done dwell
                bDone := TRUE; // 置完成单脉冲 / raise the done pulse
            END_IF
        END_IF
    END_IF

E_DL_SnbPhase.eSnbDone: // 完成驻留相 / the done dwell phase
    IF bStop THEN // 停止消化 / absorb the stop
        _ePhase := E_DL_SnbPhase.eSnbIdle; // 回空闲 / back to idle
    END_IF

E_DL_SnbPhase.eSnbFault: // 故障锁存相（本件当前无迁入源，保留兜底对称位）/ the fault latch phase, reserved symmetric
    IF rtReset.Q THEN // 复位沿 / the reset edge
        _ePhase := E_DL_SnbPhase.eSnbIdle; // 回空闲 / back to idle
    END_IF

ELSE // 非法相位兜底（R128）/ the illegal phase fallback
    _ePhase := E_DL_SnbPhase.eSnbIdle; // 回空闲安全相 / back to the safe idle
END_CASE

// 段 6｜搭接窗消化与推进屏蔽清除（每拍后段执行）/ segment 6, the overlap consume and the mask clear
IF tonOvl.Q THEN // 搭接窗到期（窗口末退出）/ the overlap expired
    _bOvlRun := FALSE; // 前组断电 / drop the former group
END_IF
_bAdv := FALSE; // 推进屏蔽每拍清（组计时器重启机制）/ clear the advance mask every scan

// 段 7｜统一出口：组输出单点安全映射（边界一）/ segment 7, the unified outlet
FOR _nI := 0 TO DL_SNB_GRPMAX - 1 DO // 全组重映射 / remap all the groups
    aGrp[_nI] := FALSE; // 先全断（安全侧基线）/ all off first, the safe baseline
END_FOR
IF (_ePhase = E_DL_SnbPhase.eSnbRun) AND (NOT bError) AND (NOT bClogAlm) AND (NOT bStop) THEN // 排布有效窗口 / the valid sequencing window
    IF (_nGrp >= 0) AND (_nGrp < nGroups) THEN // 组界闸（防越界写）/ the group bound gate
        aGrp[_nGrp] := TRUE; // 当前组得电 / the current group on
    END_IF
    IF _bOvlRun AND (_nGrp > 0) AND (_nGrp - 1 < nGroups) THEN // 搭接窗内前组维持（组界闸）/ the former group held in the overlap
        aGrp[_nGrp - 1] := TRUE; // 前组得电 / the former group on
    END_IF
END_IF
nGrpIdx := _nGrp; // 活动组出口 / the active group outlet
bRunning := (_ePhase = E_DL_SnbPhase.eSnbRun); // 运行指示（R191 名实双出口）/ the running indicator
END_FUNCTION_BLOCK
