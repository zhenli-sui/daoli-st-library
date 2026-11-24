(*
  ==================================================================
  组件名 Component  : FB_DL_NightPurgeSeq
  分类   Category   : DL_Process
  复杂度 Complexity  : cx5
  版本   Version    : 1.0.1
  功能   Purpose    : 夜间免费制冷吹扫顺控。三重判据全满足才执行：夜间时段窗
                      （tNow 与窗起点终点比较；跨午夜用年内序数法判跨日，
                      全路径无 MOD）+ 室内外温差闸（带 0.5 K 回差）+ 开窗
                      许可。执行中许可失效即回驻留（不中断置故障）；最小
                      执行时长防反复启停。与防冻族分工为（利用冷量）。
  来源   Source     : t1-oscat-building（借鉴 OSCAT Building ROOM_CONTROL 夜间
                      通风待挖子项的域语义，clean-room 自研实现，未复制
                      OSCAT 任何源码行）
  溯源   Origin     : IEC 61131-3 标准语义的道莅防御性实现；夜间免费制冷为
                      公开暖通空调节能语义。
  平台   Platform   : 纯 IEC 61131-3（Standard.library: TON / R_TRIG，无私有库）
  分工声明 Split     : 与 DL_Process 存量防冻族（FrostProtectFreeze 等）分工
                      ——防冻件防低温损害，本件利用夜间冷量节能预冷，方向相反；
                      时段窗时刻由调用方（PRG 层时钟同步）经 tNow 引脚传入，
                      本件不读系统时钟。
  作者   Author     : 道莅代码库 · PLC 编程专家（R57）
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 温差闸回差 0.5 K 常量：进入用全阈值，退出减回差；
                      二 开窗许可失效：执行中即回驻留相（R191 显式声明，
                         不中断置故障），窗口命令安全侧关闭；
                      三 跨午夜时段窗用年内序数法（起点日与次日 +1 判跨日），
                         全路径无 MOD；
                      四 最小执行时长 tMinRun 防反复启停（执行相退出门控）；
                      五 夜窗结束（_bNight 变假）执行相立即退出，不受 tMinRun
                         门控（v1.0.1 偏离段声明：外因一次性事件不会抖振，
                         防止温差持续满足时把热空气灌进建筑）；
                      六 锁存解除路径 = bReset 上升沿（唯一路径，R188）；
                      七 无全局变量、无外部变量声明、无物理地址寻址。
  修订记录 Revision  :
    2026-11-21  v1.0.0  R57 首版（批 4 · 序号 20）
    2026-11-21  v1.0.1  R58 返修：执行相原退出条件只有三条，温差始终满足时
                        吹扫会持续到日间（违背利用夜间冷量的存在理由），段 6
                        新增第四条退出「NOT _bNight 夜窗末退出」，不受 tMinRun
                        门控；边界四→五重排，功能描述同步。
  ==================================================================
*)

TYPE E_DL_NpsPhase :
(
    eDwell := 0,  // 驻留：三判据评估 / dwelling, the triple criteria evaluated
    ePurge := 10, // 执行：开窗吹扫 / purging, the windows commanded
    eFault := 90  // 故障：成因锁存 / fault, the cause latched
);
END_TYPE

TYPE E_DL_NpsFault :
(
    eNone      := 0, // 无成因 / no cause
    eCfgBad    := 1, // 组态非法：温差阈值或序数越域（故障级，与 bError 配对）/ an illegal config
    eSensorBad := 2, // 温度非有限（故障级，与 bError 配对）/ a non finite temperature
    ePhaseBad  := 3  // 非法相位兜底（故障级，与 bError 配对）/ an illegal phase fallback
);
END_TYPE

FUNCTION_BLOCK FB_DL_NightPurgeSeq
VAR_INPUT
    bEnable     : BOOL := TRUE;      // 使能，失能即回驻留关窗 [-] / enable, disabling dwells and closes
    bReset      : BOOL := FALSE;     // 复位上升沿清锁存 [-] / reset rising edge clears the latch
    tNow        : TOD := T#00:00:00; // 当前时刻 [时刻]，由调用方时钟源传入 / the current time, fed by the caller clock source
    fToutC      : LREAL := 15.0;     // 室外温度实测 [摄氏度] / the outdoor temperature [degree celsius]
    fTinC       : LREAL := 26.0;     // 室内温度实测 [摄氏度] / the indoor temperature [degree celsius]
    fDiffOnK    : LREAL := 3.0;      // 温差闸进入阈值 [开尔文]，域 大于回差 / the diff entry threshold [kelvin], above the hysteresis
    bWinPermit  : BOOL := FALSE;     // 开窗许可（风雨 / 消防联锁给出）[-] / the window permit from the rain and fire interlocks
    tNightStart : TOD := T#22:00:00; // 夜间窗起点 [时刻] / the night window start [time of day]
    tNightEnd   : TOD := T#06:00:00; // 夜间窗终点 [时刻]，早于起点表跨午夜 / the night window end, earlier than the start means overnight
    nDayOfYear  : INT := 200;        // 年内序数日 [日]，域 1..366 / the day of year ordinal [day], one through three hundred sixty six
    tMinRun     : TIME := T#300S;    // 最小执行时长 [毫秒]，防反复启停 / the minimum run duration against hunting
END_VAR
VAR_OUTPUT
    bPurgeRun  : BOOL := FALSE; // 吹扫执行电平 [-] / the purge run level
    bWinCmd    : BOOL := FALSE; // 开窗命令输出（安全侧常闭）[-] / the window command outlet, normally closed
    bCondOk    : BOOL := FALSE; // 三判据满足预备指示 [-] / the criteria ready indicator
    ePhase     : E_DL_NpsPhase := E_DL_NpsPhase.eDwell; // 相位出口 [枚举] / the phase outlet
    eFault     : E_DL_NpsFault := E_DL_NpsFault.eNone; // 成因出口，锁存回放 [枚举] / the cause outlet replayed
    bError     : BOOL := FALSE; // 故障锁存标志 [-] / the fault latch flag
END_VAR
VAR
    rtReset  : R_TRIG; // 复位沿检测，段 0 无条件刷新 / the reset edge
    tonMinRun: TON;    // 最小执行窗，段 0 无条件刷新 / the minimum run window
    _ePhase  : E_DL_NpsPhase := E_DL_NpsPhase.eDwell; // 内部相位，CASE 唯一写入目标 / the internal phase
    _eFaulC  : E_DL_NpsFault := E_DL_NpsFault.eNone; // 故障级成因，锁存至复位沿 / the fault cause, latched
    _bFault  : BOOL := FALSE; // 故障锁存位 [-] / the fault latch bit
    _bInit   : BOOL := FALSE; // 首扫初始化完成标志（R310）/ the first scan flag
    _bInOk   : BOOL := FALSE; // 双温度有限 [-] / both temperatures finite
    _bCfgOk  : BOOL := FALSE; // 组态域内 [-] / the config inside the domain
    _bNight  : BOOL := FALSE; // 当拍处于夜间窗 [-] / inside the night window this scan
    _bArmed  : BOOL := FALSE; // 跨午夜窗 armed 标记（起点日晚段已过）[-] / the overnight armed flag
    _nWinDay : INT := 0;      // 夜间窗起点日序数 [日] / the ordinal day the window opened
    _bDiffOk : BOOL := FALSE; // 温差闸回差锁存 [-] / the diff hysteresis latch
END_VAR
VAR CONSTANT
    DL_NP_DIFF_HYST : LREAL := 0.5; // 温差闸回差 [开尔文]（边界一）/ the diff hysteresis [kelvin]
    DL_NP_DOY_MAX   : INT := 366;   // 年内序数上界 [日] / the ordinal upper bound [day]
END_VAR

// 段 0｜定时器与沿检测无条件周期刷新（禁入分支）/ segment 0, the unconditional refresh
rtReset(CLK := bReset); // 复位沿 / the reset edge
tonMinRun(IN := (_ePhase = E_DL_NpsPhase.ePurge) AND (NOT _bFault), PT := tMinRun); // 最小执行窗，IN 串执行相闸 / the minimum run gated by the purge phase

// 段 1｜首扫初始化（R310）/ segment 1, the first scan
IF NOT _bInit THEN // 首扫一拍 / the first scan
    _bInit := TRUE; // 置首扫标志 / raise the flag
END_IF

// 段 2｜复位沿作用域：清锁存 / 清跨日标记 / 迁驻留（三项逐项声明）/ segment 2, the reset edge scope
IF rtReset.Q THEN // 复位沿 / the reset edge
    _bFault := FALSE; // 作用域一：清故障锁存 / scope one, clear the fault latch
    _eFaulC := E_DL_NpsFault.eNone; // 作用域一：清成因 / scope one, clear the cause
    _bArmed := FALSE; // 作用域二：清跨日 armed 标记 / scope two, clear the armed flag
    _nWinDay := 0; // 作用域二：清起点日序数 / scope two, clear the opening ordinal
    _ePhase := E_DL_NpsPhase.eDwell; // 作用域三：迁驻留相 / scope three, back to dwell
END_IF

// 段 3｜组态与输入域闸（R151 全覆盖）/ segment 3, the configuration and input gates
_bInOk := (fToutC = fToutC) AND ((fToutC - fToutC) = (fToutC - fToutC)) AND (fTinC = fTinC) AND ((fTinC - fTinC) = (fTinC - fTinC)); // 双温度有限双判据 / the dual temperature finiteness
_bCfgOk := (fDiffOnK > DL_NP_DIFF_HYST) AND (fDiffOnK = fDiffOnK) AND (nDayOfYear >= 1) AND (nDayOfYear <= DL_NP_DOY_MAX) AND (tMinRun > T#0S) AND (tNightStart <> tNightEnd); // 温差阈值 / 序数 / 最小时长 / 零长窗域判定（起点=终点判零长窗非法，R253）/ the threshold, ordinal, duration and zero length window verdicts
IF (NOT _bInOk) OR (NOT _bCfgOk) THEN // 输入缺陷或组态非法 / a defect or an illegal config
    IF NOT _bFault THEN // 未锁存才迁移 / migrate only while unlatched
        _bFault := TRUE; // 置故障锁存 / raise the fault latch
        IF NOT _bInOk THEN // 传感失效优先归因（R190）/ the sensor failure first
            _eFaulC := E_DL_NpsFault.eSensorBad; // 传感成因 / the sensor cause
        ELSE // 组态非法 / the illegal config
            _eFaulC := E_DL_NpsFault.eCfgBad; // 组态成因 / the config cause
        END_IF
        _ePhase := E_DL_NpsPhase.eFault; // 迁故障相 / migrate to fault
    END_IF
END_IF

// 段 4｜夜间时段窗判定（序数法判跨日，无 MOD，边界三）/ segment 4, the night window by the ordinal method
IF tNightStart < tNightEnd THEN // 同日窗路径（相等已由段 3 组态闸判非法，R253）/ the same day window path, equality judged illegal by segment three
    _bNight := (tNow >= tNightStart) AND (tNow <= tNightEnd); // 起点终点夹逼 / the span containment
    _bArmed := FALSE; // 同日窗不涉跨日 / no overnight involved
ELSE // 跨午夜窗路径 / the overnight window path
    IF tNow >= tNightStart THEN // 晚段：窗开启并记录起点日序数 / the evening segment, the window opens
        _bNight := TRUE; // 窗内 / inside
        _bArmed := TRUE; // 置 armed / arm
        _nWinDay := nDayOfYear; // 记起点日序数 / record the opening ordinal
    ELSIF tNow <= tNightEnd THEN // 早段：仅起点日或次日有效（序数法判跨日）/ the morning segment, the opening day or the next day only
        _bNight := _bArmed AND ((nDayOfYear = _nWinDay) OR (nDayOfYear = _nWinDay + 1)); // 序数法判跨日 / the ordinal cross day verdict
    ELSE // 白天空窗段 / the daytime gap
        _bNight := FALSE; // 窗外 / outside
        _bArmed := FALSE; // 清 armed / disarm
    END_IF
END_IF

// 段 5｜温差闸回差锁存（边界一）/ segment 5, the diff hysteresis latch
IF (fTinC - fToutC) > fDiffOnK THEN // 进入判据（全阈值）/ the entry with the full threshold
    _bDiffOk := TRUE; // 置温差锁存 / raise the diff latch
ELSIF (fTinC - fToutC) < (fDiffOnK - DL_NP_DIFF_HYST) THEN // 退出判据（减回差）/ the exit minus the hysteresis
    _bDiffOk := FALSE; // 清温差锁存 / clear the diff latch
END_IF

// 段 6｜相位机：ENUM + CASE，含 ELSE 非法相位兜底（R128）/ segment 6, the phase machine
CASE _ePhase OF

E_DL_NpsPhase.eDwell: // 驻留相：三判据齐全才执行 / the dwell phase, all three criteria start the purge
    IF NOT bEnable THEN // 失能 / disabled
        _ePhase := E_DL_NpsPhase.eDwell; // 停摆驻留 / dwell
    ELSIF _bNight AND _bDiffOk AND bWinPermit AND (NOT _bFault) THEN // 三判据齐全（时段 + 温差 + 许可）/ the triple criteria met
        _ePhase := E_DL_NpsPhase.ePurge; // 迁执行相 / migrate to purge
    END_IF

E_DL_NpsPhase.ePurge: // 执行相：退出条件 ≥4（失能 / 许可失效 / 夜窗结束 / 温差退出且最小时长满足，边界二一四五）/ the purge phase, at least four exit conditions
    IF NOT bEnable THEN // 失能 / disabled
        _ePhase := E_DL_NpsPhase.eDwell; // 回驻留相 / back to dwell
    ELSIF NOT bWinPermit THEN // 许可失效即回驻留，不中断置故障（边界二）/ the permit lost returns to dwell
        _ePhase := E_DL_NpsPhase.eDwell; // 回驻留相 / back to dwell
    ELSIF NOT _bNight THEN // 夜窗结束退出：外因一次性事件，不受 tMinRun 门控（边界五，v1.0.1）/ the night window end exits without the minimum gate
        _ePhase := E_DL_NpsPhase.eDwell; // 回驻留相 / back to dwell
    ELSIF (NOT _bDiffOk) AND tonMinRun.Q THEN // 温差退出且最小时长已满足（边界一四）/ the diff exit with the minimum met
        _ePhase := E_DL_NpsPhase.eDwell; // 回驻留相 / back to dwell
    END_IF

E_DL_NpsPhase.eFault: // 故障相：成因锁存，等复位沿；窗口命令安全侧关闭 / the fault phase, the command closed on the safe side
ELSE // 非法相位兜底（R128）/ the illegal phase fallback
    _bFault := TRUE; // 置故障锁存 / raise the fault latch
    _eFaulC := E_DL_NpsFault.ePhaseBad; // 故障级成因（R45 配对 bError）/ the fault cause
    _ePhase := E_DL_NpsPhase.eFault; // 迁故障相 / migrate to fault
END_CASE

// 段 7｜统一出口 / segment 7, the unified outlet
bPurgeRun := (_ePhase = E_DL_NpsPhase.ePurge) AND (NOT _bFault); // 执行电平 / the run level
bWinCmd := bPurgeRun; // 开窗命令与执行同源（安全侧常闭）/ the command shares the run source
bCondOk := _bNight AND _bDiffOk AND bWinPermit AND bEnable AND (NOT _bFault); // 预备指示 / the ready indicator
ePhase := _ePhase; // 相位出口单点映射 / the phase outlet
IF _bFault THEN // 故障锁存优先 / the fault latch first
    eFault := _eFaulC; // 成因锁存回放（R152）/ the cause replayed
ELSE // 无锁存 / no latch
    eFault := E_DL_NpsFault.eNone; // 无成因 / no cause
END_IF
bError := _bFault; // 故障标志与锁存位同源 / the flag shares the latch
END_FUNCTION_BLOCK
