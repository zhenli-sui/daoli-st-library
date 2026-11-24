(*
  ==================================================================
  组件名 Component  : FB_DL_MultiSegmentTimer
  分类   Category   : DL_Base
  复杂度 Complexity  : 中
  版本   Version    : 1.0.0
  功能   Purpose    : 多段定时窗口组（日历窗）。8 段独立使能的日内分钟窗
                      （起止 0..1439），输出当前是否处于任一窗内 bInWindow、
                      当前活动段索引 nActiveSeg（-1 = 无）、段间重叠检测
                      bOverlap（信息级）与组态非法 bCfgErr。LGF Date and
                      Timer 多段定时语义 clean-room。
  来源   Source     : T2-1-lgf-date-timer（LGF 多段定时语义）
  溯源   Origin     : 日历窗多段定时为公开工程语义，clean-room 自研实现，
                      未复制 LGF 或任何厂商私有库源码。
  平台   Platform   : 纯 IEC 61131-3，CODESYS / TwinCAT / InoProShop 通用
  分工声明 Split     : 与 FB_DL_SchedWeekPlan 分工——后者做周计划调度，
                      本件做单日多段窗判定（无状态纯判定）。
  作者   Author     : 道莅代码库 · PLC 编程专家（R59）
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 窗语义：[aStart, aStop) 左闭右开；aStart = aStop 视
                         为全日窗（1440 分钟）；支持 aStart > aStop 跨零点窗；
                      二 输入域闸：nNowMin ∉ [0..1439] 或任一使能段起止越域
                         → bCfgErr 置位，bInWindow 安全侧 FALSE（安全侧赋值
                         不受判定量污染）；
                      三 bOverlap 为信息级提示不锁存，不参与 bInWindow 判定；
                      四 无定时器无沿检测（无状态判定件），无全局变量、无
                         外部变量声明、无物理地址寻址。
  修订记录 Revision  :
    2026-11-21  v1.0.0  R59 首版（批 1 · 序号 3）
  ==================================================================
*)

FUNCTION_BLOCK FB_DL_MultiSegmentTimer
VAR_INPUT
    nNowMin : DINT;                     // 当日时刻 [分钟]，域 0..1439 / the minute of day, zero through one thousand four hundred thirty nine
    aEn     : ARRAY[0..7] OF BOOL;      // 段使能组（8 段独立使能）[-] / the segment enable array, eight independent enables
    aStart  : ARRAY[0..7] OF DINT;      // 段起始分钟组 [分钟]，域 0..1439 / the segment start minutes array
    aStop   : ARRAY[0..7] OF DINT;      // 段结束分钟组 [分钟]，域 0..1439 / the segment stop minutes array
END_VAR
VAR_OUTPUT
    bInWindow  : BOOL := FALSE; // 当前时刻处于任一使能窗内 [-] / the now inside any enabled window flag
    nActiveSeg : DINT := -1;    // 当前活动段索引，-1 = 无活动段 [段] / the active segment index, minus one when none
    bOverlap   : BOOL := FALSE; // 使能段间存在重叠（信息级）[-] / any enabled segments overlap, informational
    bCfgErr    : BOOL := FALSE; // 组态非法（时刻越域或使能段起止越域）[-] / the configuration fault
END_VAR
VAR CONSTANT
    DL_MST_SEGMAX : DINT := 8;    // 段容量上界 [段] / the segment capacity bound
    DL_MST_DAYMIN : DINT := 1440; // 全日分钟数 [分钟] / the minutes per day
END_VAR
VAR
    _nI    : DINT; // 段遍历索引（段判定环）/ the segment loop index
    _nJ    : DINT; // 重叠比对索引（重叠检测环）/ the overlap compare index
    _bHit  : BOOL; // 段命中工作量 [-] / the segment hit work flag
    _nSeg  : DINT; // 活动段寄存（-1 起步）/ the active segment register
    _bCfg  : BOOL; // 组态非法工作量（先算后出，避免多点回夹）/ the config fault work flag
    _bOvl  : BOOL; // 重叠工作量 / the overlap work flag
END_VAR

// 段 1｜输出预置与时刻域闸（安全侧赋值不受判定量污染，边界二）/ segment 1, the preset and the time domain gate
_bCfg := FALSE; // 组态非法工作量清零 / clear the config work flag
_bOvl := FALSE; // 重叠工作量清零 / clear the overlap work flag
_nSeg := -1; // 活动段预置无 / preset the active segment none
IF (nNowMin < 0) OR (nNowMin >= DL_MST_DAYMIN) THEN // 时刻越域 / the time out of domain
    _bCfg := TRUE; // 组态非法 / raise the config fault
END_IF

// 段 2｜使能段起止域校验与活动窗判定（含跨零点窗与全日窗语义，边界一）/ segment 2, the segment validation and the active window
FOR _nI := 0 TO DL_MST_SEGMAX - 1 DO // 逐段判定 / per segment verdict
    IF aEn[_nI] THEN // 段使能才校验与判定 / validate and judge only the enabled segment
        IF (aStart[_nI] < 0) OR (aStart[_nI] >= DL_MST_DAYMIN)
        OR (aStop[_nI] < 0) OR (aStop[_nI] >= DL_MST_DAYMIN) THEN // 起止越域 / the bounds out of domain
            _bCfg := TRUE; // 组态非法 / raise the config fault
        END_IF
        IF aStart[_nI] = aStop[_nI] THEN // 全日窗语义 / the full day window
            _bHit := TRUE; // 全日窗恒命中（越域统一由出口闸拦截）/ the full day window always hits
        ELSIF aStart[_nI] < aStop[_nI] THEN // 同日窗 [start, stop) / the same day window
            _bHit := (nNowMin >= aStart[_nI]) AND (nNowMin < aStop[_nI]); // 左闭右开命中 / the half open hit
        ELSE // 跨零点窗 [start, 1439] ∪ [0, stop) / the midnight spanning window
            _bHit := (nNowMin >= aStart[_nI]) OR (nNowMin < aStop[_nI]); // 双半区命中 / the two half zone hit
        END_IF
        IF _bHit AND (_nSeg < 0) THEN // 首个命中段为准（段号小者优先）/ the first hit segment wins
            _nSeg := _nI; // 记活动段 / register the active segment
        END_IF
    END_IF
END_FOR

// 段 3｜使能段两两重叠检测（信息级，边界三）/ segment 3, the pairwise overlap detection, informational
FOR _nI := 0 TO DL_MST_SEGMAX - 2 DO // 前段遍历 / the former loop
    IF aEn[_nI] AND (aStart[_nI] >= 0) AND (aStart[_nI] < DL_MST_DAYMIN)
    AND (aStop[_nI] >= 0) AND (aStop[_nI] < DL_MST_DAYMIN) THEN // 仅合法使能段参与比对 / only the valid enabled ones
        FOR _nJ := _nI + 1 TO DL_MST_SEGMAX - 1 DO // 后段遍历 / the latter loop
            IF aEn[_nJ] AND (aStart[_nJ] >= 0) AND (aStart[_nJ] < DL_MST_DAYMIN)
            AND (aStop[_nJ] >= 0) AND (aStop[_nJ] < DL_MST_DAYMIN) THEN // 仅合法使能段参与比对 / only the valid ones
                IF (aStart[_nI] < aStop[_nJ]) AND (aStart[_nJ] < aStop[_nI]) THEN // 区间相交判据（半开域交叠）/ the interval intersection
                    _bOvl := TRUE; // 置重叠提示 / raise the overlap hint
                END_IF
            END_IF
        END_FOR
    END_IF
END_FOR

// 段 4｜统一出口（安全侧：组态非法时 bInWindow 强制 FALSE，单点赋值）/ segment 4, the unified outlet
bCfgErr := _bCfg; // 组态非法出口 / the config fault outlet
bOverlap := _bOvl; // 重叠提示出口 / the overlap outlet
nActiveSeg := _nSeg; // 活动段出口 / the active segment outlet
IF _bCfg THEN // 组态非法安全侧 / the config fault safe side
    bInWindow := FALSE; // 窗内标志强制假 / force the window flag false
ELSE // 组态合法 / the valid configuration
    bInWindow := (_nSeg >= 0); // 命中即窗内 / the hit verdict
END_IF
END_FUNCTION_BLOCK
