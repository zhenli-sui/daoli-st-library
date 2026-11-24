(*
  道莅工业代码库 | DL_Device | FB_DL_VfdStateWordMatch
  版本: 1.0.0 | 日期: 2026-11-23 | 轮次: R75
  开源溯源: brOscatLib (github.com/brOscatLib) / MIT / 借鉴 StateWordMatch 的语义，代码为 clean-room 重写
  功能: 变频器状态字与期望控制状态匹配判码——掩码位域比对、失配去抖锁存、
        低 4 位状态号提取输出；与 FB_DL_VfdCtrlWordBuild 成对（编码/判码）。
  兼容性: CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop；仅依赖标准 TON / R_TRIG，零厂商私有库
  接口: 输入 wStatWord（原始状态字）、wCareMask（关注位掩码）、wExpect（期望值）、
        tMismatchHold（失配确认延时）、bEn/bReset；输出 bMatch/bMismatch（锁存）/
        uStateNo（bit0..3 状态号）/wStatMasked/eCause/bError/nErrId。
  码表: 16#0003_0320 故障级：状态字失配锁存（掩码位域与期望不符持续 tMismatchHold）
        码段说明：0003 段故障子带 03xx，槽位经全库实扫空闲。
  边界: ① 判码口径：bMatchRaw = ((wStatWord AND wCareMask) = wExpect)，整数按位
        运算与按位字比较为合法语义（非浮点容差范畴）；
        ② 失配经 TON 去抖确认后锁存，复位沿清除；未到延时内的瞬时失配只影响
        bMatch 电平，不置故障；
        ③ uStateNo 取状态字 bit0..3（SHR 0 位后 AND 16#000F），恒 0..15 无越界；
        ④ 变换+锁存型 FB：无 CASE 相位机（判码无相位迁移语义，R6 不适用）；
        ⑤ TON/R_TRIG 段 0 无条件周期刷新；⑥ 零全局耦合。
  邻件比对: StatusWordSegDecoder（通用分段译码 vs 本件变频器状态字匹配判码）。
  修订历史: 2026-11-23 v1.0.0 R75 首版（复杂件批 B1 · C04）
*)

TYPE E_DL_VsmCause :
(
    eNone         := 0,  // 无失配 | No mismatch
    eStateMismatch:= 1   // 状态字失配（去抖确认后锁存） | Status word mismatch latched after debounce
);
END_TYPE

FUNCTION_BLOCK FB_DL_VfdStateWordMatch
VAR_INPUT
    bEn           : BOOL := FALSE;    // 判码使能 [-] | Match enable
    wStatWord     : WORD := 16#0000;  // 变频器原始状态字 [-] | Raw VFD status word
    wCareMask     : WORD := 16#00FF;  // 关注位掩码（参与比对的位）[-] | Care mask of compared bits
    wExpect       : WORD := 16#0000;  // 掩码位域期望值 [-] | Expected value in masked domain
    tMismatchHold : TIME := T#2S;     // 失配确认延时，域 > T#0S | Mismatch confirm delay
    bReset        : BOOL := FALSE;    // 复位命令，上升沿清锁存 [-] | Reset command, rising edge
END_VAR
VAR_OUTPUT
    bMatch      : BOOL;               // 本拍匹配电平（未到去抖的瞬时失配也为 FALSE）[-] | Match level this scan
    bMismatch   : BOOL;               // 失配锁存标志 [-] | Latched mismatch flag
    uStateNo    : UINT;               // 状态字低 4 位状态号 [号] | State number from low nibble
    wStatMasked : WORD;               // 掩码后状态字回显 [-] | Masked status word echo
    eCause      : E_DL_VsmCause;      // 失配成因出口 | Mismatch cause outlet
    bError      : BOOL;               // 故障锁存标志 [-] | Fault latch flag
    nErrId      : UDINT;              // 事件码，0 = 无事件 | Event code, 0 = none
END_VAR
VAR
    _bMatchRaw  : BOOL;               // 本拍掩码比对原始结果 [-] | Raw masked comparison this scan
    _bMisLatch  : BOOL;               // 失配锁存位 | Latched mismatch bit
    _eCause     : E_DL_VsmCause := E_DL_VsmCause.eNone;   // 成因锁存 | Latched cause
    tonMis      : TON;                // 失配去抖计时，段 0 无条件刷新 | Mismatch debounce timer
    rtReset     : R_TRIG;             // 复位沿实例，段 0 无条件刷新 | Reset edge instance
END_VAR

(* —— 段 0：当拍量派生 + 定时器与沿实例无条件周期刷新（R7 红线） —— *)
_bMatchRaw := ((wStatWord AND wCareMask) = wExpect);          // 掩码位域比对（整数合法判等） / Masked domain comparison
rtReset(CLK := bReset);                                       // 复位沿每拍必调 / Reset edge every scan
tonMis(IN := bEn AND (NOT _bMatchRaw), PT := tMismatchHold);  // 失配去抖 IN 挂当拍失配合取 / Debounce gated by enable and mismatch

(* —— 段 1：复位沿 —— *)
IF rtReset.Q THEN
    _bMisLatch := FALSE;                                      // 清失配锁存位 / Clear latched mismatch
    _eCause := E_DL_VsmCause.eNone;                           // 清成因 / Clear cause
END_IF

(* —— 段 2：失配去抖确认与锁存 —— *)
IF bEn AND tonMis.Q AND (NOT _bMisLatch) THEN
    _bMisLatch := TRUE;                                       // 去抖确认锁存 / Latch after debounce confirm
    _eCause := E_DL_VsmCause.eStateMismatch;                  // 归因失配 / Cause: mismatch
END_IF

(* —— 段 3：出口单点映射（名实同源；锁存码回放） —— *)
bMatch := bEn AND _bMatchRaw AND (NOT _bMisLatch);            // 匹配电平：使能 ∧ 原始匹配 ∧ 未锁存 / Match level composite
bMismatch := _bMisLatch;                                      // 失配镜像 / Mismatch mirror
uStateNo := INT_TO_UINT(WORD_TO_INT(wStatWord AND 16#000F));  // 低 4 位状态号（掩码后恒 0..15） / State number from low nibble
wStatMasked := wStatWord AND wCareMask;                       // 掩码回显 / Masked echo
eCause := _eCause;                                            // 成因出口 / Cause outlet
bError := _bMisLatch;                                         // 故障标志同源 / Error flag from latch
IF _bMisLatch THEN
    nErrId := 16#0003_0320;                                   // 失配锁存码回放 / Replay latched mismatch code
ELSE
    nErrId := 16#0000_0000;                                   // 无事件 / No event
END_IF

END_FUNCTION_BLOCK
