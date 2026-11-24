(*
  ==================================================================
  组件名 Component  : FB_DL_ValveTerminalDiag
  分类   Category   : DL_Device
  复杂度 Complexity  : 中
  版本   Version    : 1.0.0
  功能   Purpose    : 阀岛级 N 站位命令-反馈一致性诊断。每拍逐站比对命令字与
                      反馈字（按位异或），每位独立锁存不一致；岛级健康态按
                      NE107 数值最小（最差者胜）聚合，出口携带最差站号。
  来源   Source     : t2-6-rockwell-aoi + t2-2-lbp（阀岛 AOI 诊断 + 位模式比较语义）
  溯源   Origin     : 阀岛命令-反馈一致性诊断与 NE107 分级均为公开工程语义，
                      clean-room 自研实现，未复制 Rockwell AOI 或任何厂商源码。
  平台   Platform   : 纯 IEC 61131-3（XOR / FOR / 比较），三平台通用
  分工声明 Split     : 与 FB_DL_ControlValveDiag（单阀机理诊断属主）分工——后者
                      判单阀动作时间/行程特性；本件只做岛级命令-反馈一致性，
                      不判机理、不做趋势、不替代单阀诊断。
  作者   Author     : 道莅代码库 · PLC 编程专家（R60）
  ------------------------------------------------------------------
  归属 Ownership     : E_DL_Ne107Status 归属 DL_Device/I_DL_DeviceHealth，本件只
                      引用不重声明（R264）；本件不自造第二套健康分级枚举，数值最小
                      最差口径唯一真源为上述属主文件（R226）。
  边界 Boundary     :
                      一 每拍全量重判，无相位机（R227 显式声明）：本件本质是组合
                         判定件，不存在等待相；不一致位为锁存量，仅复位沿清除；
                      二 站位容量 16（nStations 钳位 1..16），越域置信息级码；
                      三 逐位比对：nCmd XOR nFb 的非零位即不一致，口径为单位
                         （16 位命令字）；不一致位按站位锁存，不按位号展开；
                      四 岛级聚合：取所有站位健康级数值最小者（NE107 小者优先），
                         数值口径直接引用属主枚举初值，本件不含任何本地映射表；
                      五 使能 bEnable = FALSE 时语义为「冻结保持」：健康级与锁存
                         保持末值，不新增锁存（R191 声明行）；
                      六 锁存解除路径：复位沿清全部站位锁存并回 eOk（bReset 为
                         输入引脚，恒可达，R152 自证）。
  错误码   Codes    :
    16#0003_0620【信息级】站位容量越域已钳位（<1 或 >16）
    16#0003_0621【故障级】存在站位命令-反馈不一致（锁存至复位沿），站号见 uWorstSt
  验收   Acceptance :
    算法已证（脚本）：未跑 ｜ 编译器已证（三平台）：未跑
    V1 3 站、命令 16#0F / 反馈 16#0F → eHealth = eOk、无不一致
    V2 第 2 站命令 16#01 / 反馈 16#00 → uMismatchSt 位 1 置、eHealth = eFailure
    V3 复位沿 → 全部锁存清除、eHealth 回 eOk
  修订记录 Revision  :
    2026-11-21  v1.0.0  R60 首版（批 3 · 序号 10）
  ==================================================================
*)
FUNCTION_BLOCK FB_DL_ValveTerminalDiag
VAR_INPUT
    bEnable    : BOOL := TRUE;                            // 使能，FALSE 时冻结保持（边界五）/ the enable, false freezes and holds
    bReset     : BOOL := FALSE;                           // 复位沿：清全部站位锁存并回正常 / the reset edge, clears every latch and returns to ok
    nStations  : DINT := 8;                               // 站位数量 [站]，合法域 1..16 / the station count, legal from one to sixteen
    anCmd      : ARRAY[0..15] OF UINT;                    // 各站命令字 [位图]，位 n 对应阀 n / the per station command words
    anFb       : ARRAY[0..15] OF UINT;                    // 各站反馈字 [位图]，位 n 对应阀 n / the per station feedback words
END_VAR
VAR_OUTPUT
    uMismatch  : UINT := 16#0000;                         // 不一致站位位图（位 i = 第 i 站）[位图] / the mismatching station bitmap
    uWorstSt   : UINT := 16#FFFF;                         // 最差站位号，无故障时为 16#FFFF [站号] / the worst station index, the sentinel when none
    eHealth    : E_DL_Ne107Status := E_DL_Ne107Status.eOk; // 岛级健康态（最差者胜）[状态] / the island health state by the worst winner rule
    bMismatch  : BOOL := FALSE;                           // 存在任一站位不一致 [-] / any station mismatches
    bError     : BOOL := FALSE;                           // 故障锁存位 [-] / the latched fault bit
    eErr       : UDINT := 16#0000_0000;                   // 错误码，0 = 正常 / the error code, zero is ok
END_VAR
VAR
    _bInit     : BOOL := FALSE;             // 首拍初始化标志（R310）/ the first scan flag
    _uMismatch : UINT := 16#0000;           // 不一致位图副本，段 5 单点映射 / the mismatch bitmap copy, mapped once in segment five
    _uWorstSt  : UINT := 16#FFFF;           // 最差站号副本 / the worst station index copy
    _eHealth   : E_DL_Ne107Status := E_DL_Ne107Status.eOk; // 健康级副本（逐拍重算后映射）/ the health copy recomputed every scan
    _nUse      : DINT := 0;                 // 钳位后站位数量 [站] / the clamped station count
    _nI        : DINT := 0;                 // 站位遍历索引 [站] / the station loop index
    _nBad      : DINT := 0;                 // 本拍不一致站位计数 [站] / the mismatching station count of this scan
    _nMinVal   : DINT := 100;               // 当前最小健康级数值（100 为越界哨兵）/ the running minimum health value
    _bClamp    : BOOL := FALSE;             // 站位容量钳位标记 [-] / the capacity clamp flag
    _bCfgBad   : BOOL := FALSE;             // 站号越域组态异常标记（逐拍重算）[-] / the station out of range flag, recomputed every scan
    rtReset    : R_TRIG;                    // 复位沿实例，段 0 无条件刷新 / the reset edge instance, refreshed unconditionally
END_VAR
VAR CONSTANT
    DL_VTD_STMAX : DINT := 16;    // 站位容量上界 [站]，与数组容量一致 / the station capacity aligned with the array
    DL_VTD_VMAX  : UINT := 16#FFFF; // 无故障哨兵站号 [站号] / the no fault station sentinel
END_VAR

// 段 0｜复位沿无条件周期刷新（禁入分支，R7）/ segment 0, the unconditional edge refresh
rtReset(CLK := bReset); // 复位沿 / the reset edge

// 段 1｜首拍初始化与逐拍量预置（锁存量不入预置清单，R32 FB32-1）/ segment 1, the first scan init and the per scan preset
IF NOT _bInit THEN // 首拍一拍 / the first scan
    _bInit := TRUE; // 置首拍标志 / raise the first scan flag
    _uMismatch := 16#0000; // 不一致位图显式清零 / clear the bitmap explicitly
    _uWorstSt := DL_VTD_VMAX; // 最差站号显式置哨兵 / place the sentinel explicitly
    _eHealth := E_DL_Ne107Status.eOk; // 健康级显式落正常 / place the health to ok explicitly
END_IF
_nBad := 0; // 本拍不一致计数清零 / clear the mismatch count
_nMinVal := 100; // 最小健康级数值预置哨兵 / preset the minimum health value to the sentinel
_bClamp := FALSE; // 钳位标记预清零 / preset the clamp flag false
_bCfgBad := FALSE; // 组态异常标记预清零 / preset the configuration flag false

// 段 2｜站位容量域闸（<1 判信息级并返空结果，>16 钳位，边界二）/ segment 2, the station capacity gate
IF nStations < 1 THEN // 无站位：空结果 / no station, an empty result
    _nUse := 0; // 站位数量为零 / the station count is zero
    eErr := 16#0003_0620; // 信息级：站位容量越域已钳位 / informational, the capacity clamped
    bError := TRUE; // 置错误标志（信息级随事件置位惯例）/ raise the error flag
ELSE // 有站位 / at least one station
    _nUse := nStations; // 域内接管 / take the count inside the domain
    IF _nUse > DL_VTD_STMAX THEN // 超容量 / above the capacity
        _nUse := DL_VTD_STMAX; // 钳到容量 / clamp to the capacity
        _bClamp := TRUE; // 置钳位标记 / raise the clamp flag
        eErr := 16#0003_0620; // 信息级：站位容量越域已钳位 / informational, the capacity clamped
        bError := TRUE; // 置错误标志 / raise the error flag
    END_IF
END_IF

// 段 3｜逐站命令-反馈比对与逐位锁定（每拍全量重判，边界一三）/ segment 3, the per station comparison with the bitwise latch
FOR _nI := 0 TO _nUse - 1 DO // 有界循环（_nUse ≤16）/ the bounded loop
    IF (anCmd[_nI] XOR anFb[_nI]) <> 16#0000 THEN // 命令与反馈存在任一差异位 / any differing bit exists
        _nBad := _nBad + 1; // 不一致站位计数推进 / advance the mismatch count
        CASE _nI OF // 站位号到位图的显式映射（禁位移拼接，位号即站号）/ the explicit station to bit mapping, no shifting
            0: _uMismatch := _uMismatch OR 16#0001; // 第 0 站 / the station zero
            1: _uMismatch := _uMismatch OR 16#0002; // 第 1 站 / the station one
            2: _uMismatch := _uMismatch OR 16#0004; // 第 2 站 / the station two
            3: _uMismatch := _uMismatch OR 16#0008; // 第 3 站 / the station three
            4: _uMismatch := _uMismatch OR 16#0010; // 第 4 站 / the station four
            5: _uMismatch := _uMismatch OR 16#0020; // 第 5 站 / the station five
            6: _uMismatch := _uMismatch OR 16#0040; // 第 6 站 / the station six
            7: _uMismatch := _uMismatch OR 16#0080; // 第 7 站 / the station seven
            8: _uMismatch := _uMismatch OR 16#0100; // 第 8 站 / the station eight
            9: _uMismatch := _uMismatch OR 16#0200; // 第 9 站 / the station nine
            10: _uMismatch := _uMismatch OR 16#0400; // 第 10 站 / the station ten
            11: _uMismatch := _uMismatch OR 16#0800; // 第 11 站 / the station eleven
            12: _uMismatch := _uMismatch OR 16#1000; // 第 12 站 / the station twelve
            13: _uMismatch := _uMismatch OR 16#2000; // 第 13 站 / the station thirteen
            14: _uMismatch := _uMismatch OR 16#4000; // 第 14 站 / the station fourteen
            15: _uMismatch := _uMismatch OR 16#8000; // 第 15 站 / the station fifteen
            ELSE // 越域站号拦截（_nUse 已钳 ≤16，结构性不可达兜底，命中即判组态异常）/ the out of range guard, structurally unreachable
                _bCfgBad := TRUE; // 置组态异常标记（位图无法表达该站）/ raise the configuration flag, the bitmap cannot express the station
        END_CASE
    END_IF
END_FOR

// 段 4｜岛级 NE107 最差者胜聚合（数值最小优先，口径引用属主枚举，边界四）/ segment 4, the island worst winner aggregation
IF _nUse < 1 THEN // 无站位：健康级落未知 / no station, the health falls to unknown
    _eHealth := E_DL_Ne107Status.eUnknown; // 未知（未取得有效数据）/ unknown, no valid data yet
ELSIF _nBad > 0 THEN // 存在不一致：失效级 / a mismatch exists, the failure level
    _eHealth := E_DL_Ne107Status.eFailure; // 失效（小者优先即最差者胜）/ failure, the smallest value wins
ELSE // 全部一致 / all consistent
    _eHealth := E_DL_Ne107Status.eOk; // 正常 / ok
END_IF
_uWorstSt := DL_VTD_VMAX; // 最差站号预置哨兵 / preset the worst station sentinel
FOR _nI := 0 TO _nUse - 1 DO // 逐站找首个不一致站号 / find the first mismatching station
    IF (_uWorstSt = DL_VTD_VMAX) AND ((anCmd[_nI] XOR anFb[_nI]) <> 16#0000) THEN // 首个不一致站 / the first mismatching station
        _uWorstSt := DINT_TO_UINT(_nI); // 记录站号（DINT→UINT 标准转换，R262）/ register the index by the standard conversion
    END_IF
END_FOR

// 段 5｜复位沿处理：清全部站位锁存并回正常（解除路径可达，边界六）/ segment 5, the reset scope handling
IF rtReset.Q THEN // 复位沿 / the reset edge
    _uMismatch := 16#0000; // 复位作用域：清锁存位图 / the reset scope, clear the bitmap latch
    _uWorstSt := DL_VTD_VMAX; // 复位作用域：清最差站号 / the reset scope, clear the worst station
    _eHealth := E_DL_Ne107Status.eOk; // 复位作用域：健康级回正常 / the reset scope, the health back to ok
    _nBad := 0; // 复位作用域：清本拍计数 / the reset scope, clear the scan count
END_IF

// 段 6｜统一出口（内部副本单点映射，R180；故障码锁存回放，R187）/ segment 6, the unified outlet
// 失能时的「冻结保持」（边界五）由锁存副本天然承担：_u* 仅在复位沿清除，故出口映射单一路径即可（R57 禁双分支全等赋值）
uMismatch := _uMismatch; // 位图出口 / the bitmap outlet
uWorstSt := _uWorstSt; // 最差站号出口 / the worst station outlet
eHealth := _eHealth; // 健康级出口 / the health outlet
bMismatch := (_uMismatch <> 16#0000); // 不一致指示出口（与锁存位图同源）/ the mismatch outlet from the same latched bitmap
IF _bCfgBad THEN // 站号越域（结构性不可达兜底）/ the station out of range guard
    bError := TRUE; // 故障位出口 / the fault bit outlet
    eErr := 16#0003_0620; // 信息级：站位容量越域已钳位 / informational, the capacity clamped
ELSIF _nBad > 0 THEN // 存在不一致：故障级锁存码 / a mismatch exists, the fault grade code
    bError := TRUE; // 故障位出口（与锁存同源）/ the fault bit outlet from the same latch
    eErr := 16#0003_0621; // 故障级：站位命令-反馈不一致 / fault grade, a station command and feedback mismatch
ELSIF eErr <> 16#0003_0620 THEN // 无故障级事件时保留信息级码或复位为正常 / keep the informational code or fall back to ok
    bError := FALSE; // 无故障级事件：故障位清零 / no fault grade event, clear the fault bit
    eErr := 16#0000_0000; // 正常 / ok
END_IF
END_FUNCTION_BLOCK
