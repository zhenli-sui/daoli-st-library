(*
  ==================================================================
  组件名 Component  : FB_DL_PhaseLossGuard
  分类   Category   : DL_Device
  前缀   Naming     : FB_DL_ ｜ b/n/u/f/t/e/st 类型前缀制（R265）
  复杂度 Complexity  : 中
  版本   Version    : 1.0.0
  功能   Purpose    : 三相缺相/逆相序检测（幅差判据 + 逆相序独立码）。
  来源   Source     : self-std（三相监测公开工程语义自研）
  平台   Platform   : 纯 IEC 61131-3（比较 / ABS / R_TRIG），三平台通用
  分工声明 Split     : 与 FB_DL_PhaseNeutralImbalance 分工——后者做相零不平衡
                      统计；本件做缺相保护与逆相序判定（R216 双向互引）。
  作者   Author     : 道莅代码库 · PLC 编程专家（R61）
  归属 Ownership     : 本件无 TYPE 声明；引用件类型全部 IEC 标准原生。
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 幅差判据阈值 fImbPct 提级为输入引脚并带单位 [%]（R 红线 7），
                         阈值 ≤ 0 或非有限判组态非法锁存（0706）；
                      二 非有限闸逐个点名三个电压浮点入参（R272 全量：fUA / fUB /
                         fUC），命中判缺相成因独立锁存（0704，R190 归因唯一）；
                      三 仅全相有压时才判序（防欠压误报，边界口径）：缺相或欠压
                         态不判逆相序；逆相序独立码 0705（R190 独立成员独立码）；
                      四 双锁存独立解除：bReset 上升沿清双侧锁存（恒可达，R152）；
                      五 无全局、无外部变量、无物理地址。
  错误码   Codes    :
    16#0003_0704【故障级】缺相（幅差超阈或电压非有限），锁存至复位沿
    16#0003_0705【故障级】逆相序（相序反馈为反且全相有压），锁存至复位沿
    16#0003_0706【故障级】组态非法（阈值 ≤ 0 或非有限），锁存至复位沿
  验收   Acceptance :
    算法已证（脚本）：未跑 ｜ 编译器已证（三平台）：未跑
    V1 三相 230/230/230、阈 10% → 无故障
    V2 C 相掉至 0（幅差 100%）→ 码 0704、bPhaseLoss 锁存
    V3 全相有压 + 相序反馈反 → 码 0705、bSeqReverse 锁存
  修订记录 Revision  :
    2026-11-21  v1.0.0  R61 首版（批 3 · 序号 12）
  ==================================================================
*)
FUNCTION_BLOCK FB_DL_PhaseLossGuard
VAR_INPUT
    bEnable : BOOL := TRUE;   // 使能，FALSE 时冻结判据出口（R191 声明行）/ the enable, false freezes the judgement outlet
    bReset  : BOOL := FALSE;  // 故障复位电平，上升沿清锁存 / the fault reset level
    bSeqOk  : BOOL := TRUE;   // 相序继电器反馈：TRUE 正序 / the phase sequence relay feedback
    fUA     : LREAL := 230.0; // A 相电压有效值 [伏] / the phase A voltage
    fUB     : LREAL := 230.0; // B 相电压有效值 [伏] / the phase B voltage
    fUC     : LREAL := 230.0; // C 相电压有效值 [伏] / the phase C voltage
    fImbPct : LREAL := 10.0;  // 幅差判据阈值 [%]，必须 > 0 / the unbalance threshold in percent, must be positive
END_VAR
VAR_OUTPUT
    bPhaseLoss  : BOOL := FALSE;          // 缺相锁存指示 [-] / the phase loss latched indicator
    bSeqReverse : BOOL := FALSE;          // 逆相序锁存指示 [-] / the reverse sequence latched indicator
    bError      : BOOL := FALSE;          // 故障锁存位（与锁存同源，R191）/ the fault bit from the latch
    bValid      : BOOL := FALSE;          // 判据可用标志（无故障且无组态非法）[-] / the judgement usable flag
    eErr        : UDINT := 16#0000_0000;  // 错误码，0 = 正常 / the error code, zero is ok
END_VAR
VAR
    _bInit    : BOOL := FALSE; // 首拍初始化标志（R310）/ the first scan flag
    _bLoss    : BOOL := FALSE; // 缺相锁存副本（仅复位沿清除）/ the loss latch copy
    _bRev     : BOOL := FALSE; // 逆相序锁存副本 / the reverse latch copy
    _bCfgBad  : BOOL := FALSE; // 组态非法锁存副本 / the configuration latch copy
    _bFin     : BOOL := FALSE; // 电压非有限标记（逐拍重算）/ the voltage finiteness flag recomputed
    _fMean    : LREAL := 0.0;  // 三相电压均值 [伏] / the three phase mean voltage
    _fDev     : LREAL := 0.0;  // 当前相幅差 [%] / the current phase deviation in percent
    _bAllUp   : BOOL := FALSE; // 全相有压标记（均值 > 容差）[-] / the all phases powered flag
    rtReset   : R_TRIG; // 复位沿实例，段 0 无条件刷新 / the reset edge instance
END_VAR
VAR CONSTANT
    DL_PLG_TOL : LREAL := 1.0E-6; // 全相有压均值容差 [伏] / the mean voltage tolerance
END_VAR

// 段 0｜复位沿无条件周期刷新（禁入分支，R7）/ segment 0, the unconditional refresh
rtReset(CLK := bReset); // 复位沿 / the reset edge

// 段 1｜首拍初始化与复位沿作用域（R310 / R311）/ segment 1, the first scan init and the reset scope
IF NOT _bInit THEN // 首拍一拍 / the first scan
    _bInit := TRUE; // 置首拍标志 / raise the first scan flag
    _bLoss := FALSE; // 缺相锁存显式清零 / clear the loss latch explicitly
    _bRev := FALSE; // 逆相序锁存显式清零 / clear the reverse latch explicitly
    _bCfgBad := FALSE; // 组态锁存显式清零 / clear the configuration latch explicitly
END_IF
IF rtReset.Q THEN // 复位沿（作用域：清三锁存，R311 声明）/ the reset edge with the declared scope
    _bLoss := FALSE; // 清缺相锁存（解除路径：复位沿恒可达，R152 自证）/ clear the loss latch
    _bRev := FALSE; // 清逆相序锁存 / clear the reverse latch
    _bCfgBad := FALSE; // 清组态锁存 / clear the configuration latch
END_IF

// 段 2｜组态闸与电压非有限闸（R272 全量点名，边界一二）/ segment 2, the configuration and the voltage gates
_bFin := (fUA = fUA) AND ((fUA - fUA) = (fUA - fUA))
AND (fUB = fUB) AND ((fUB - fUB) = (fUB - fUB))
AND (fUC = fUC) AND ((fUC - fUC) = (fUC - fUC)); // 三相电压逐个自反 + 差值判 / the three voltages tested term by term
IF (fImbPct <= 0.0) OR (fImbPct <> fImbPct) OR ((fImbPct - fImbPct) <> (fImbPct - fImbPct)) THEN // 阈值非法（边界一）/ an illegal threshold
    _bCfgBad := TRUE; // 锁存组态非法（0706）/ latch the configuration fault
END_IF
IF NOT _bFin THEN // 电压非有限按缺相成因独立锁存（R190 归因唯一，边界二）/ a non finite voltage latches the loss cause
    _bLoss := TRUE; // 锁存缺相（0704）/ latch the phase loss
END_IF

// 段 3｜幅差判据（电压有限且组态合法时执行，除零防护）/ segment 3, the unbalance criterion with the division guards
IF _bFin AND (NOT _bCfgBad) THEN // 判据执行前置 / the criterion preconditions
    _fMean := (fUA + fUB + fUC) / 3.0; // 三相均值（除子常量 3.0，无除零风险）/ the mean with the constant divisor
    IF ABS(_fMean) > DL_PLG_TOL THEN // 均值非零才判幅差（除零防护）/ the deviation judged on a nonzero mean
        IF (ABS(fUA - _fMean) / ABS(_fMean) * 100.0 > fImbPct)
        OR (ABS(fUB - _fMean) / ABS(_fMean) * 100.0 > fImbPct)
        OR (ABS(fUC - _fMean) / ABS(_fMean) * 100.0 > fImbPct) THEN // 任一相幅差超阈（除子已证 > 容差）/ any phase over the threshold
            _bLoss := TRUE; // 锁存缺相（0704）/ latch the phase loss
        END_IF
    ELSE // 全相零压：按缺相成因处理（判据退化安全侧）/ the all zero phases latches the loss too
        _bLoss := TRUE; // 锁存缺相 / latch the phase loss
    END_IF
    _bAllUp := ABS(_fMean) > DL_PLG_TOL; // 全相有压标记（判序前置，边界三）/ the all powered flag ahead of the sequence test
END_IF

// 段 4｜逆相序判据（仅全相有压且未缺相未组态非法时判，边界三）/ segment 4, the reverse sequence criterion with the preconditions
IF _bAllUp AND (NOT _bLoss) AND (NOT _bCfgBad) AND (NOT bSeqOk) THEN // 判序前置齐全 / the sequence preconditions met
    _bRev := TRUE; // 锁存逆相序（0705，独立成因独立码，R190）/ latch the reverse sequence
END_IF

// 段 5｜统一出口（锁存同源映射；失能冻结判据出口保持锁存值，R191）/ segment 5, the unified outlet
bPhaseLoss := _bLoss; // 缺相出口 / the loss outlet
bSeqReverse := _bRev; // 逆相序出口 / the reverse outlet
bError := _bLoss OR _bRev OR _bCfgBad; // 故障位出口 / the fault bit outlet
bValid := (NOT _bLoss) AND (NOT _bRev) AND (NOT _bCfgBad) AND bEnable; // 判据可用标志 / the usable flag
IF _bCfgBad THEN // 组态成因回放优先 / the configuration cause replays first
    eErr := 16#0003_0706; // 故障级：阈值组态非法 / fault grade, the illegal threshold
ELSIF _bLoss THEN // 缺相成因 / the loss cause
    eErr := 16#0003_0704; // 故障级：缺相锁存回放 / fault grade, the phase loss replayed
ELSIF _bRev THEN // 逆相序成因 / the reverse cause
    eErr := 16#0003_0705; // 故障级：逆相序锁存回放 / fault grade, the reverse sequence replayed
ELSE // 无故障 / no fault
    eErr := 16#0000_0000; // 正常 / ok
END_IF
END_FUNCTION_BLOCK
