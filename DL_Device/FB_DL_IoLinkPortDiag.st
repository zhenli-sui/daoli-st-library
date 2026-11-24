(*
  道莅工业代码库 | DL_Device | FB_DL_IoLinkPortDiag
  版本: 1.0.0 | 日期: 2026-11-23 | 轮次: R75
  开源溯源: self-cleanroom（无外部来源；IO-Link 端口诊断语义，零代码行复制）
  功能: IO-Link 端口诊断聚合——8 端口设备质量码/过程数据有效位逐口判坏与计数，
        主站循环翻转看门狗（tWdTimeout 内无翻转判通信丢失，锁存需复位）。
  兼容性: CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop；仅依赖标准 TON / R_TRIG / F_TRIG，零厂商私有库
  接口: 输入 aPortQuality（8 端口质量码，0=好）/aPdValid（8 端口 PD 有效）/
        bCycleTog（主站循环翻转输入）/tWdTimeout/bEn/bReset；输出 bAllPortsOk/
        bWdOk/uBadCnt/aPortBad/eState/eCause/bError/nErrId。
  码表: 16#0003_038A 故障级：循环看门狗超时（翻转丢失锁存至复位沿）
        16#0003_0410 信息级：存在坏端口（质量码非零或 PD 无效，当拍重算）
        码段说明：0003 段故障子带 03xx / 信息子带 04xx，槽位经全库实扫空闲。
  边界: ① 数组全部固定上界 [1..8]（零 VLA，R75 口径），下标 1..8 由 FOR 常量界
        证明无越界；
        ② 看门狗：rtTog/ftTog 任一沿喂狗，TON IN := NOT 沿，翻转丢失经去抖
        窗锁存；翻转正常时 IN 周期性落 FALSE 自复位（R188 自复位口径）；
        ③ 端口坏为电平判据（不锁存），信息级每拍重算；看门狗丢失为锁存故障；
        ④ TON/R_TRIG/F_TRIG 段 0 无条件周期刷新；⑤ 零全局耦合。
  邻件比对: ProfinetAlarmDiag（PROFINET vs 本件 IO-Link，协议域不同）。
  修订历史: 2026-11-23 v1.0.0 R75 首版（复杂件批 B3 · C12）
*)

TYPE E_DL_IldState :
(
    eOk        := 0,   // 全端口健康且看门狗正常 | All ports healthy, watchdog ok
    ePortFault := 10,  // 存在坏端口 | At least one bad port
    eWdLost    := 20   // 循环看门狗丢失（锁存） | Cycle watchdog lost, latched
);
END_TYPE

TYPE E_DL_IldCause :
(
    eNone        := 0,  // 无故障 | No cause
    eWdNoToggle  := 1,  // 循环翻转丢失 | Cycle toggle lost
    ePortQuality := 2,  // 端口质量码非零 | Port quality code non-zero
    ePdInvalid   := 3   // 端口过程数据无效 | Port PD invalid
);
END_TYPE

FUNCTION_BLOCK FB_DL_IoLinkPortDiag
VAR_INPUT
    bEn          : BOOL := FALSE;    // 诊断使能 [-] | Diagnostics enable
    aPortQuality : ARRAY[1..8] OF BYTE;   // 每端口设备质量码（0=好）[码] | Per-port device quality code, 0 = good
    aPdValid     : ARRAY[1..8] OF BOOL;   // 每端口过程数据有效 [-] | Per-port process data valid
    bCycleTog    : BOOL := FALSE;    // 主站循环翻转输入（每循环取反）[-] | Master cycle toggle input
    tWdTimeout   : TIME := T#100MS;  // 看门狗超时，域 > T#0S | Watchdog timeout
    bReset       : BOOL := FALSE;    // 复位命令，上升沿清锁存 [-] | Reset command, rising edge
END_VAR
VAR_OUTPUT
    bAllPortsOk : BOOL;             // 全端口健康且看门狗正常 [-] | All ports ok and watchdog ok
    bWdOk       : BOOL;             // 循环看门狗正常 [-] | Cycle watchdog ok
    uBadCnt     : UINT;             // 坏端口计数 [口] | Bad port count
    aPortBad    : ARRAY[1..8] OF BOOL;   // 每端口坏标志 [-] | Per-port bad flag
    eState      : E_DL_IldState;    // 状态出口 | State outlet
    eCause      : E_DL_IldCause;    // 成因出口 | Cause outlet
    bError      : BOOL;             // 故障锁存标志 [-] | Fault latch flag
    nErrId      : UDINT;            // 事件码，0 = 无事件 | Event code, 0 = none
END_VAR
VAR
    _bWdLatch : BOOL;               // 看门狗丢失锁存位 | Watchdog lost latch bit
    _eCause   : E_DL_IldCause := E_DL_IldCause.eNone;   // 成因锁存 | Latched cause
    _ePortCau : E_DL_IldCause := E_DL_IldCause.eNone;   // 端口成因当拍归因 | Port cause attribution this scan
    _nBad     : INT;                // 坏端口计数当拍量 [口] | Bad port count this scan
    _bAnyBad  : BOOL;               // 存在坏端口当拍量 [-] | Any bad port this scan
    i         : INT;                // 端口游标（1..8 常量界）| Port cursor, constant bounds
    rtTog     : R_TRIG;             // 翻转上升沿实例，段 0 无条件刷新 | Toggle rising edge instance
    ftTog     : F_TRIG;             // 翻转下降沿实例，段 0 无条件刷新 | Toggle falling edge instance
    rtReset   : R_TRIG;             // 复位沿实例，段 0 无条件刷新 | Reset edge instance
    tonWd     : TON;                // 看门狗计时（喂狗自复位），段 0 无条件刷新 | Watchdog timer, fed by edges
END_VAR

(* —— 段 0：沿与定时器实例无条件周期刷新（R7 红线） —— *)
rtTog(CLK := bCycleTog);                    // 翻转上升沿每拍必调 / Rising edge every scan
ftTog(CLK := bCycleTog);                    // 翻转下降沿每拍必调 / Falling edge every scan
tonWd(IN := NOT (rtTog.Q OR ftTog.Q), PT := tWdTimeout);   // 喂狗：任一沿 IN 落假自复位（边界②）/ Fed by any edge, self-reset
rtReset(CLK := bReset);                     // 复位沿每拍必调 / Reset edge every scan

(* —— 段 1：复位沿 + 看门狗锁存 —— *)
IF rtReset.Q THEN
    _bWdLatch := FALSE;                     // 清看门狗锁存位 / Clear watchdog latch
    _eCause := E_DL_IldCause.eNone;         // 清成因 / Clear cause
END_IF
IF bEn AND tonWd.Q AND (NOT _bWdLatch) THEN
    _bWdLatch := TRUE;                      // 翻转丢失超时锁存 / Toggle loss timeout latch
    _eCause := E_DL_IldCause.eWdNoToggle;   // 归因翻转丢失 / Cause: toggle lost
END_IF

(* —— 段 2：逐端口判坏与计数（下标 1..8 常量界，无越界路径） —— *)
_nBad := 0;                                 // 计数当拍量预清 / Count preset
_bAnyBad := FALSE;                          // 坏标志预清 / Any-bad preset
_ePortCau := E_DL_IldCause.eNone;           // 端口成因预清 / Port cause preset
FOR i := 1 TO 8 DO
    IF (aPortQuality[i] <> 0) OR (NOT aPdValid[i]) THEN
        aPortBad[i] := TRUE;                // 端口坏：质量码非零或 PD 无效 / Port bad by quality or PD
        _nBad := _nBad + 1;                 // 坏端口计数 / Count increment
        _bAnyBad := TRUE;                   // 存在坏端口 / Any bad flag
        IF NOT aPdValid[i] THEN
            _ePortCau := E_DL_IldCause.ePdInvalid;      // 归因 PD 无效（先到先归因）/ Cause: PD invalid
        ELSE
            _ePortCau := E_DL_IldCause.ePortQuality;    // 归因质量码 / Cause: quality code
        END_IF
    ELSE
        aPortBad[i] := FALSE;               // 端口好 / Port good
    END_IF
END_FOR

(* —— 段 3：出口单点映射（名实同源；锁存码回放 + 信息码重算） —— *)
bWdOk := (NOT tonWd.Q) AND (NOT _bWdLatch);              // 看门狗正常判据（锁存后保持坏）/ Watchdog ok judgement
uBadCnt := INT_TO_UINT(_nBad);                           // 坏端口计数出口 / Bad count outlet
bAllPortsOk := (NOT _bWdLatch) AND (_nBad = 0);          // 总健康判据 / All-ok judgement
IF _bWdLatch THEN
    eState := E_DL_IldState.eWdLost;                     // 看门狗丢失态 / Watchdog lost state
ELSIF bEn AND _bAnyBad THEN
    eState := E_DL_IldState.ePortFault;                  // 坏端口态 / Port fault state
ELSE
    eState := E_DL_IldState.eOk;                         // 健康态 / Ok state
END_IF
IF _bWdLatch THEN
    eCause := _eCause;                                   // 锁存成因出口（看门狗）/ Latched watchdog cause
ELSE
    eCause := _ePortCau;                                 // 当拍端口成因出口 / Per-scan port cause
END_IF
bError := _bWdLatch;                                     // 故障标志同源 / Error flag from latch
IF _bWdLatch THEN
    nErrId := 16#0003_038A;                              // 看门狗锁存码回放 / Replay watchdog latch code
ELSIF _bAnyBad THEN
    nErrId := 16#0003_0410;                              // 信息级：存在坏端口（每拍重算）/ Info: bad port present
ELSE
    nErrId := 16#0000_0000;                              // 无事件 / No event
END_IF

END_FUNCTION_BLOCK
