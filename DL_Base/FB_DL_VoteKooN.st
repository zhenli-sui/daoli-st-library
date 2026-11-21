(*
  ==================================================================
  组件名 Component  : FB_DL_VoteKooN
  分类   Category   : DL_Base
  复杂度 Complexity  : cx5
  版本   Version    : 1.0.0
  功能   Purpose    : N 中取 K 安全表决器（MooN 架构）。对 N 个通道的触发量
                      与健康位做 KooN 表决：健康通道中触发数 ≥ K 即表决输出
                      置位；支持通道故障掩码注入（强制剔除指定通道）与 K/N
                      可组态；组态越域锁存故障并输出安全侧。与固定 2oo3 的
                      FB_DL_Vote2oo3 分工互引（固定架构 vs 通用 KooN）。
  来源   Source     : self-std（IEC 61508 MooN 架构公开表决语义）
  溯源   Origin     : IEC 61131-3 标准语义的道莅防御性实现；KooN（MooN）表决
                      为 IEC 61508 公开安全架构语义，clean-room 自研实现，未
                      复制任何厂商私有库源码。
  平台   Platform   : 纯 IEC 61131-3（Standard.library: R_TRIG，无私有库）
  分工声明 Split     : 与 DL_Base 存量 FB_DL_Vote2oo3 分工——Vote2oo3 为固定
                      2oo3 单一架构快捷件，本件为通用 KooN（K 与 N 均可组态，
                      通道数 2..8）架构件；两者不互相替代。
  作者   Author     : 道莅代码库 · PLC 编程专家（R58）
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 组态域：nN ∈ [2..8]，nK ∈ [1..nN]；越域锁存 bCfgBad
                         （解除路径 = bReset 上升沿，且组态恢复后不再重锁），
                         锁存期表决出口置安全侧 TRUE（fail-safe 跳闸，R191
                         显式声明为降级安全值 + 置标志）；
                      二 健康位 FALSE 或掩码注入 TRUE 的通道不计入表决基数；
                         掩码通道的触发量不参与任何判定；
                      三 数组按固定界 0..7 遍历，nN 越界的槽位天然不入基数
                         （无动态下标，结构性越界防御）；
                      四 失能（bEnable = FALSE）输出冻结保持末值（R191 冻结
                         保持声明），组态闸与计数仍每拍刷新；
                      五 无全局变量、无外部变量声明、无物理地址寻址。
  修订记录 Revision  :
    2026-11-21  v1.0.0  R58 首版（批 1 · 序号 1）
  ==================================================================
*)

TYPE E_DL_VknCause :
(
    eNone   := 0, // 无成因 / no cause
    eCfgBad := 1  // 组态非法：N 或 K 越域（故障级，与 bError 配对）/ an illegal config, N or K out of the domain
);
END_TYPE

FUNCTION_BLOCK FB_DL_VoteKooN
VAR_INPUT
    abChnTrip : ARRAY[0..7] OF BOOL; // 通道触发量数组，槽位即通道号 [-] / the channel trip array, the slot is the channel number
    abChnOk   : ARRAY[0..7] OF BOOL; // 通道健康位，FALSE = 通道故障剔除 [-] / the channel health bits, false excludes the faulty channel
    abChnMask : ARRAY[0..7] OF BOOL; // 通道故障掩码注入，TRUE = 强制剔除 [-] / the channel mask injection, true forces the exclusion
    nN        : USINT := 3;   // 表决基数 N（参与通道数）[个]，域 2..8 / the voter base N [channel], two through eight
    nK        : USINT := 2;   // 表决门限 K（跳闸所需触发数）[个]，域 1..N / the voter threshold K [channel], one through N
    bEnable   : BOOL := TRUE; // 使能，失能冻结输出末值 [-] / enable, disabling freezes the outputs
    bReset    : BOOL := FALSE; // 复位上升沿清组态故障锁存 [-] / reset rising edge clears the config fault latch
END_VAR
VAR_OUTPUT
    bTrip    : BOOL := FALSE; // 表决出口，TRUE = 健康通道触发数 ≥ K [-] / the vote outlet, true when the healthy trips reach K
    nHealthy : USINT := 0;    // 参与表决的健康通道数 [个] / the healthy channel count participating [channel]
    nTripChn : USINT := 0;    // 健康通道中的触发通道数 [个] / the tripped channel count among the healthy [channel]
    eCause   : E_DL_VknCause := E_DL_VknCause.eNone; // 成因出口，锁存回放 [枚举] / the cause outlet replayed
    bError   : BOOL := FALSE; // 故障锁存标志（组态越域）[-] / the fault latch flag, a config violation
END_VAR
VAR
    rtReset  : R_TRIG; // 复位沿检测，段 0 无条件刷新 / the reset edge, refreshed unconditionally
    _nI      : DINT;   // 通道遍历索引 [槽] / the channel loop index [slot]
    _nBase   : DINT;   // 参与基数（健康且未掩码）[个] / the participating base [channel]
    _nTrip   : DINT;   // 健康通道触发计数 [个] / the trip count among the healthy [channel]
    _nND     : DINT;   // N 的 DINT 工作副本 [个]（规避 USINT 混型比较）/ the DINT working copy of N [channel]
    _nKD     : DINT;   // K 的 DINT 工作副本 [个] / the DINT working copy of K [channel]
    _bCfgL   : BOOL := FALSE; // 组态故障锁存位 [-] / the config fault latch bit
END_VAR

// 段 0｜沿检测无条件周期刷新（禁入分支）/ segment 0, the unconditional refresh
rtReset(CLK := bReset); // 复位沿 / the reset edge

// 段 1｜复位沿作用域：清组态故障锁存（作用域逐项声明）/ segment 1, the reset edge scope
IF rtReset.Q THEN // 复位沿 / the reset edge
    _bCfgL := FALSE; // 作用域一：清组态锁存 / scope one, clear the config latch
    eCause := E_DL_VknCause.eNone; // 作用域一：清成因 / scope one, clear the cause
END_IF

// 段 2｜组态域闸（边界一）：N ∈ [2..8]，K ∈ [1..N] / segment 2, the config gate
_nND := USINT_TO_DINT(nN); // 升宽比较副本 / the widened comparison copy
_nKD := USINT_TO_DINT(nK); // 升宽比较副本 / the widened comparison copy
IF (nN < 2) OR (nN > 8) OR (nK < 1) OR (nK > nN) THEN // 越域判定（双侧直比，无 ABS）/ the domain verdict, both sides direct
    IF NOT _bCfgL THEN // 未锁存才置位（锁存回放 R152）/ latch only while unlatched
        _bCfgL := TRUE; // 置组态故障锁存 / raise the config fault latch
        eCause := E_DL_VknCause.eCfgBad; // 故障级成因（R45 配对 bError）/ the fault cause
    END_IF
END_IF
bError := _bCfgL; // 故障标志与锁存位同源（R191 名实双出口）/ the flag shares the latch

// 段 3｜通道遍历计数（固定界 0..7，槽位越 nN 的不入基数，边界三）/ segment 3, the channel scan with a fixed bound
_nBase := 0; // 基数清零 / clear the base
_nTrip := 0; // 触发计数清零 / clear the trip count
FOR _nI := 0 TO 7 DO // 固定界循环，无死循环风险 / the fixed bound loop
    IF (_nI < _nND) AND abChnOk[_nI] AND (NOT abChnMask[_nI]) THEN // 在 N 域内且健康且未掩码 / inside N, healthy, and unmasked
        _nBase := _nBase + 1; // 基数推进 / advance the base
        IF abChnTrip[_nI] THEN // 通道触发 / the channel tripped
            _nTrip := _nTrip + 1; // 触发计数推进 / advance the trip count
        END_IF
    END_IF
END_FOR
nHealthy := DINT_TO_USINT(_nBase); // 健康数出口 / the healthy count outlet
nTripChn := DINT_TO_USINT(_nTrip); // 触发数出口 / the trip count outlet

// 段 4｜表决与出口（组态锁存期 fail-safe 置 TRUE，边界一）/ segment 4, the vote and the outlets
IF _bCfgL THEN // 组态故障锁存期 / while the config fault latches
    bTrip := TRUE; // 安全侧跳闸（fail-safe，降级安全值 + bError 置位，R191）/ the fail safe trip with the flag raised
END_IF
IF (NOT _bCfgL) AND bEnable THEN // 组态正常且使能才刷新表决出口 / refresh the vote outlet only when the config is fine and enabled
    bTrip := (_nTrip >= _nKD); // 表决判定：健康触发数 ≥ 门限 K / the vote verdict, the trips reach K
END_IF
// 失能且无组态故障时不进入任何刷新分支：bTrip 冻结保持末值（边界四，R191 冻结保持声明）
// with no config fault and disabled, no refresh branch runs, bTrip freezes at the last value
END_FUNCTION_BLOCK
