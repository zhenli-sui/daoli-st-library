(*==============================================================================
 * 名称 : FC_DL_ClampDintChk —— DINT 限幅 + 越界方向标志（nLo>nHi 判参数非法）
 * 分类 / 前缀 / 版本 : DL_Algo / FC_DL_ / 1.0.0
 * 溯源 : 开源语义参考（OSCAT/AixOCAT 族，MIT）或 clean-room IEC 实现，未复制源码
 * 平台 : 纯 IEC 61131-3
 * 功能说明 : 将 nIn 限幅到 [nLo,nHi] 并输出越界方向：nDir=-1 下限截断 /
 *            0 未截断 / +1 上限截断，供下游统计截断频次或触发量程告警。
 *            边界处理：nLo>nHi 判参数非法（区间为空），返回 0、nDir=0、
 *            bValid=FALSE 并置 eErr；nIn 恰等于边界值属未截断（nDir=0）。
 * 错误码 : 16#0001_1C05 = 区间非法（nLo>nHi，无合法限幅区间）
 *          eErr=0 且 bValid=TRUE 表示限幅结果与方向标志可用
 * 状态机 : R6 标注 N/A（纯函数无顺序状态，以本节替代 ELSE 兜底）
 * 红线 : R1/R2/R3 ✓ 零全局/零IO/纯IEC ｜ R4 ✓ 区间校验 ｜ R10 ✓ 标准转换 ｜ R11 ✓ 分号收尾 ｜ R15 ✓ 无保留字撞名
 * 修订记录 : 2026-11-23 v1.0.0 首次入库（R76）
 *============================================================================*)
FUNCTION FC_DL_ClampDintChk : DINT
VAR_INPUT
    nIn : DINT;    // 被限幅输入量 [-2147483648..2147483647] / input value to clamp
    nLo : DINT;    // 限幅下界（须 <=nHi）/ clamp lower bound, must be <= nHi
    nHi : DINT;    // 限幅上界（须 >=nLo）/ clamp upper bound, must be >= nLo
END_VAR
VAR_OUTPUT
    nDir   : INT;      // 越界方向 -1 下截断 / 0 未截断 / +1 上截断 / clamp direction
    eErr   : UDINT;    // 故障码，0=正常，1C05=区间非法 / error code, 0=ok, 1C05=invalid range
    bError : BOOL;     // TRUE=本件发生故障 / TRUE when fault occurred
    bValid : BOOL;     // TRUE=限幅结果可用 / TRUE when result is usable
END_VAR

FC_DL_ClampDintChk := 0;                     // 返回值预设 0 / preset return to zero
nDir   := 0;                                // 方向预设未截断 / preset direction to none
eErr   := 16#0000_0000;                     // 故障码清零 / clear error code
bError := FALSE;                            // 故障标志清零 / clear error flag
bValid := TRUE;                             // 预设输出可用 / preset valid flag

IF nLo > nHi THEN                           // 区间为空：参数非法 / empty range invalid
    eErr   := 16#0001_1C05;                 // 置区间非法码 / set invalid-range code
    bError := TRUE;                         // 置故障标志 / set error flag
    bValid := FALSE;                        // 输出不可用 / outputs not usable
    nDir   := 0;                            // 方向保持 0 / keep direction zero
    RETURN;                                 // 返回 0 / return zero
END_IF

IF nIn < nLo THEN                           // 低于下界 / below lower bound
    FC_DL_ClampDintChk := nLo;              // 截到下界 / clamp to lower bound
    nDir := -1;                             // 标记下限截断 / flag lower clamp
ELSIF nIn > nHi THEN                        // 高于上界 / above upper bound
    FC_DL_ClampDintChk := nHi;              // 截到上界 / clamp to upper bound
    nDir := 1;                              // 标记上限截断 / flag upper clamp
ELSE                                        // 区间内 / inside range
    FC_DL_ClampDintChk := nIn;              // 原值透传 / pass through
    nDir := 0;                              // 未截断 / not clamped
END_IF

END_FUNCTION
