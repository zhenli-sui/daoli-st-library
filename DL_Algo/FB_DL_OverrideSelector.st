(*
  FB_DL_OverrideSelector  —  高选/低选超驰选择器 / High-select and low-select override selector
  分类 Category : DL_Algo
  版本 Version  : 1.0.0
  来源 Source   : t2-5-modpid — 超驰选择族零检索深化
  溯源 Origin   : clean-room 实现，未复制任何源码行
  功能 Function : 1) 对前 nCh 路输入按 eSel 做 eHigh（高选）/ eLow（低选）仲裁，
                  输出胜出值 fOut 与胜出通道号 uWin（1 基；0 = 无有效输入）；
                  2) 只统计 aEn 使能且非有限的通道；平值取首路（严格 > / < 比较）；
                  3) nCh <= 0 或 > 8 → 故障级 03A3 拒绝；eSel 落枚举域外 → CASE ELSE → 03A4；
                  4) 首次出现有效输出沿置信息级 0489；全通道无效置信息级 048A。
  边界 Boundary : ① 判界先行：通道数域闸在仲裁前完成；
                  ② 仲裁循环带守卫计数，防失控；
                  ③ 非有限输入自动失格（NaN 自反判），不参与仲裁；
                  ④ 无 GVL 依赖：纯引脚输入输出，无外部变量引用，无物理 IO 地址。
  依赖 Depends  : 仅 Standard.library（LREAL/REAL 算术）
  码表 Error codes（Algo 段 0002，窗口 03A3~03A4 / 0489~048A）:
    16#0002_03A3 故障级：通道数非法（nCh <= 0 或 > 8），输出强制无效，bError = TRUE
    16#0002_03A4 故障级：选择模式落 CASE ELSE 兜底（非法 eSel），bError = TRUE
    16#0002_0489 信息级：首次有效输出沿（uWin 从 0 变非 0）
    16#0002_048A 信息级：全通道无效（无有效输出）
  修订历史 Revision :
    2026-11-19  v1.0.0  R41 首版（批次 2 · 序号 3）
*)

TYPE E_DL_OvrMode :
(
    eHigh := 0,    // 高选：取最大有效值 / High-select, take the maximum valid value
    eLow  := 10    // 低选：取最小有效值 / Low-select, take the minimum valid value
);
END_TYPE

FUNCTION_BLOCK FB_DL_OverrideSelector
VAR_INPUT
    aIn          : ARRAY[1..8] OF REAL;   // 候选输入数组 [EU] / Candidate inputs
    aEn          : ARRAY[1..8] OF BOOL;   // 通道使能数组 [-] / Channel enable array
    nCh          : INT := 8;          // 参与通道数 [路]，域 1..8 / Active channel count
    eSel         : E_DL_OvrMode := E_DL_OvrMode.eHigh;  // 选择模式 / Selection mode
END_VAR
VAR_OUTPUT
    fOut         : REAL;              // 胜出输出 [EU] / Winning output
    uWin         : UINT;              // 胜出通道号 [路]，0 = 无有效输入 / Winning channel, 0 = none
    bValid       : BOOL;              // 输出有效标志 / Output valid flag
    bError       : BOOL;              // 故障级标志（信息级不置位）/ Fault-level flag
    nErrId       : UDINT;             // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    _uWin        : UINT;              // 内部胜出通道（出口镜像）/ Internal winning channel
    _fBest       : REAL;              // 当前最优值 [EU] / Current best value
    _bFound      : BOOL;              // 是否找到有效候选 / Valid candidate found
    _bAnyPrev    : BOOL;              // 上拍有输出口径镜像（首次有效沿判据）/ Previous valid mirror
    _nGuard      : INT;               // 仲裁守卫计数 [次] / Arbitration guard counter
    i            : INT;               // 仲裁循环游标 [索引] / Arbitration loop cursor
    _bNonFin     : BOOL;              // 当前元素非有限标志 / Non-finite flag of current element
END_VAR

(* —— 段 0｜单拍量预清零（纯派生件，无定时器/沿实例） —— *)
uWin := 0;                          // 胜出通道缺省 0（无有效输入）
fOut := 0.0;                        // 胜出值缺省 0
bValid := FALSE;                    // 有效出口缺省 FALSE
bError := FALSE;                    // 故障标志缺省 FALSE
nErrId := 16#0000_0000;             // 事件码缺省无事件
_bFound := FALSE;                   // 候选未找到
_uWin := 0;                         // 内部胜出清零
_nGuard := 0;                       // 守卫清零

(* —— 段 1｜判界先行：通道数域闸（越界直接故障出口，R101 配对） —— *)
IF (nCh <= 0) OR (nCh > 8) THEN
    nErrId := 16#0002_03A3;         // 故障级：通道数非法
    bError := TRUE;                 // 故障码配对置位
    RETURN;                         // 直接出口 / early exit
END_IF

(* —— 段 2｜仲裁：CASE 全覆盖 + ELSE 兜底落 03A4（R190：模式归因唯一） —— *)
CASE eSel OF

E_DL_OvrMode.eHigh:
    FOR i := 1 TO nCh DO
        _nGuard := _nGuard + 1;                 // 守卫递增
        IF _nGuard > 8 THEN
            EXIT;                               // 守卫兜底退出（理论不可达）
        END_IF
        _bNonFin := (aIn[i] <> aIn[i]) OR ((aIn[i] - aIn[i]) <> (aIn[i] - aIn[i]));
                                                    // NaN 自反判 OR Inf 差值自减判
        IF aEn[i] AND (NOT _bNonFin) THEN
            IF (NOT _bFound) OR (aIn[i] > _fBest) THEN
                _fBest := aIn[i];               // 高选：严格大于才换（平值取首路）
                _uWin := INT_TO_UINT(i);        // 记胜出通道
                _bFound := TRUE;                // 已找到
            END_IF
        END_IF
    END_FOR

E_DL_OvrMode.eLow:
    FOR i := 1 TO nCh DO
        _nGuard := _nGuard + 1;                 // 守卫递增
        IF _nGuard > 8 THEN
            EXIT;                               // 守卫兜底退出（理论不可达）
        END_IF
        _bNonFin := (aIn[i] <> aIn[i]) OR ((aIn[i] - aIn[i]) <> (aIn[i] - aIn[i]));
                                                    // 非有限判定同高选口径
        IF aEn[i] AND (NOT _bNonFin) THEN
            IF (NOT _bFound) OR (aIn[i] < _fBest) THEN
                _fBest := aIn[i];               // 低选：严格小于才换（平值取首路）
                _uWin := INT_TO_UINT(i);        // 记胜出通道
                _bFound := TRUE;                // 已找到
            END_IF
        END_IF
    END_FOR

ELSE
    nErrId := 16#0002_03A4;         // 故障级：非法选择模式兜底
    bError := TRUE;                 // 故障码配对置位
    RETURN;                         // 直接出口（出口保持缺省无效）/ early exit

END_CASE

(* —— 段 3｜出口单点映射（名实同源） —— *)
IF _bFound THEN
    fOut := _fBest;                 // 胜出值出口
    uWin := _uWin;                  // 胜出通道出口
    bValid := TRUE;                 // 有效出口
    IF NOT _bAnyPrev THEN
        nErrId := 16#0002_0489;     // 信息级：首次有效输出沿
    END_IF
ELSE
    uWin := 0;                      // 无有效输入（哨兵零通道）
    nErrId := 16#0002_048A;         // 信息级：全通道无效
END_IF
_bAnyPrev := _bFound;               // 首次有效沿判据快照

END_FUNCTION_BLOCK
