(*
  FB_DL_CellOcvBinSort  —  OCV 分选档位落 bin（档位映射 + 满 bin 换道） / OCV bin sorting with grade mapping and full-bin lane change
  分类 Category : DL_Process
  版本 Version  : 1.0.0
  来源 Source   : roadmap-li-p1 — 锂电 OCV 分选工站真缺口
  溯源 Origin   : 道莅 clean-room 实现；四档电压阈值映射 + 落料计时 + 满 bin 换道停机为公开分选工艺逻辑，未复制任何源码行
  功能 Function : 1) 档位映射：fOcvMv 按 fTh1Mv~fTh4Mv 四阶梯阈值映射到档位 1~4
                  （阈值默认升序，第 4 档为 >= 阈值兜底档）；2) 落料相 eDispatch 由 tDrop 计时；
                  3) 档位 bin 计数 nBinUsed[档位] 递增，达 nBinCap 即 bBinFull 置位并在
                  段 3 以 03A1 锁存（满 bin 换道请求，须人工清空后复位）；
                  4) 故障级单码 03A1，归因由 eCause 独立成员承载（R190）；
                  5) 信息级 04C9 = 单件分选完成沿；6) 解除式全当拍量（R240）。
  接口 Interface: 输入 OCV 电压 + 四阈 + 容量 + 落料时间；输出状态/档位/各 bin 计数/码
  边界 Boundary : ① 组态闸：四阈值非严格升序（fTh2Mv <= fTh1Mv 等）、nBinCap = 0、
                  tDrop <= T#0S 任一成立 → 03A1 锁存；
                  ② 档位数组下标写前显式钳制（nGrade 落在 1..4，越界不写，ELSE 兜底归 4 档）；
                  ③ 浮点阈值判据为「>=」单侧直比（阈值本身无容差语义，避免误判），电压量纲
                  mV 整数化输入；④ 落料 TON 与 R_TRIG 段 0 无条件周期调用；
                  ⑤ 故障相迁出唯一路径 = bReset 上升沿；⑥ 零全局耦合（无 GVL / %I %Q %M）。
  依赖 Depends  : Standard.library（TON / R_TRIG）
  码表 Error codes（Process 段 0005，故障窗口 03A1 / 信息窗口 04C9）:
    16#0005_03A1 故障级：分选故障总码（组态非法 / 落料超时 / 目标 bin 已满需换道），
                 锁存至 bReset 上升沿；归因见 eCause，不新增码位（派单硬约束单码）
    16#0005_04C9 信息级：单件分选完成沿（落料完成计数后单拍）
  修订历史 Revision :
    2026-11-19  v1.0.0  R43 首版（批次 1 · 序号 5）
*)

TYPE E_DL_OcvState :
(
    eIdle     := 0,   // 未使能待启动 / Idle, waiting start
    eClassify := 10,  // 档位判定中 / Grade classification
    eDispatch := 20,  // 落料中（落料计时） / Dispatching with drop timer
    eDone     := 50,  // 单件完成 / Single piece done
    eFault    := 90   // 故障锁存相 / Fault latched phase
);
END_TYPE

TYPE E_DL_OcvCause :
(
    eNone       := 0, // 无故障成因 / No cause
    eCfgIllegal := 1, // 组态非法 / Illegal configuration
    eDropTmo    := 2, // 落料超时 / Drop timeout
    eBinFull    := 3  // 目标 bin 已满（换道请求） / Target bin full, lane change
);
END_TYPE

FUNCTION_BLOCK FB_DL_CellOcvBinSort
VAR_INPUT
    fOcvMv      : REAL := 0.0;        // 单体 OCV 电压 [mV] / Cell OCV voltage
    fTh1Mv      : REAL := 3300.0;     // 1/2 档分界阈值 [mV] / Grade 1-2 threshold
    fTh2Mv      : REAL := 3350.0;     // 2/3 档分界阈值 [mV] / Grade 2-3 threshold
    fTh3Mv      : REAL := 3400.0;     // 3/4 档分界阈值 [mV] / Grade 3-4 threshold
    fTh4Mv      : REAL := 3450.0;     // 4 档上界（>= 归 4 档） [mV] / Grade 4 upper threshold
    nBinCap     : UINT := 500;        // 单 bin 容量 [件]，域 > 0 / Bin capacity
    tDrop       : TIME := T#800MS;    // 落料时长 [ms]，域 > 0 / Drop duration
    bStart      : BOOL := FALSE;      // 启动命令（电平）[-] / Start command
    bBinCleared : BOOL := FALSE;      // bin 已清空确认（电平）[-] / Bin cleared acknowledge
    bReset      : BOOL := FALSE;      // 复位命令，上升沿清故障 [-] / Reset edge
END_VAR
VAR_OUTPUT
    eState      : E_DL_OcvState;      // 状态出口，段 6 单点映射 / State outlet
    eCause      : E_DL_OcvCause;      // 故障成因出口（R190） / Fault cause outlet
    nGrade      : UINT;               // 当前档位 0~4，0 = 未判定 / Current grade
    anBinUsed   : ARRAY[1..4] OF UDINT;   // 各档 bin 已用计数 [件] / Per-grade bin usage
    bBinFull    : BOOL;               // 满 bin 标志镜像 [-] / Bin full mirror
    bCycleDone  : BOOL;               // 单件完成标志 [-] / Piece done flag
    bError      : BOOL;               // 故障锁存标志 [-] / Fault latch flag
    nErrId      : UDINT;              // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    _eState     : E_DL_OcvState := E_DL_OcvState.eIdle;   // 内部相位（CASE 唯一写入目标） / Internal phase
    _eCause     : E_DL_OcvCause := E_DL_OcvCause.eNone;   // 故障成因锁存（锁存量） / Latched cause
    tonDrop     : TON;                // 落料计时实例，每周期无条件调用 / Drop timer
    rtReset     : R_TRIG;             // 复位沿实例，每周期无条件调用 / Reset edge
    _anBinUsed  : ARRAY[1..4] OF UDINT;   // 内部 bin 计数（持久，段 6 映射） / Internal bin usage
    _nGrade     : UINT;               // 档位判定结果（当拍量） / Grade verdict
    _bCfgBad    : BOOL;               // 组态非法当拍量 [-] / Config illegal
    _bFault     : BOOL;               // 故障锁存位（锁存量） / Latched fault bit
    _uFault     : UDINT;              // 故障码锁存（锁存量） / Latched fault code
    _uInfo      : UDINT;              // 信息码，每拍重算 / Transient info code
END_VAR

(* —— 段 0：沿实例与定时器无条件周期刷新 + 档位判定（纯函数式，无副作用） —— *)
IF fOcvMv < fTh1Mv THEN                        // 低于 1/2 分界：1 档 / Below first threshold: grade 1
    _nGrade := 1;
ELSIF fOcvMv < fTh2Mv THEN                     // 低于 2/3 分界：2 档 / Grade 2
    _nGrade := 2;
ELSIF fOcvMv < fTh3Mv THEN                     // 低于 3/4 分界：3 档 / Grade 3
    _nGrade := 3;
ELSE                                           // 兜底：>= 3/4 分界归 4 档 / Fallback grade 4
    _nGrade := 4;
END_IF
_bCfgBad := (fTh2Mv <= fTh1Mv) OR (fTh3Mv <= fTh2Mv) OR (fTh4Mv <= fTh3Mv)
            OR (nBinCap = 0) OR (tDrop <= T#0S);                   // 组态非法当拍量 / Config illegal
rtReset(CLK := bReset);                                            // 复位沿，每拍必调 / Reset edge
tonDrop(IN := (_eState = E_DL_OcvState.eDispatch), PT := tDrop);   // 落料计时 / Drop timer

(* —— 段 1：单拍量预清零（锁存量与 bin 计数均不入清单） —— *)
_uInfo := 16#0000_0000;            // 信息码每拍重算 / Info recomputed
nGrade := 0;                       // 档位出口缺省 0 / Grade default
bBinFull := FALSE;                 // 满 bin 镜像缺省 FALSE / Bin full default
bCycleDone := FALSE;               // 完成标志缺省 FALSE / Done default
nErrId := 16#0000_0000;            // 事件码缺省无事件 / Event code default

(* —— 段 2：复位沿 + 组态域闸 —— *)
IF rtReset.Q THEN                              // rtReset.Q = 当拍量 / current scan
    _bFault := FALSE;                          // 清故障锁存位（锁存量） / Clear fault latch
    _uFault := 16#0000_0000;                   // 清故障锁存码（锁存量） / Clear fault code
    _eCause := E_DL_OcvCause.eNone;            // 清成因（锁存量） / Clear cause
    IF _eState = E_DL_OcvState.eFault THEN
        _eState := E_DL_OcvState.eIdle;        // 故障相迁出：回未使能 / Fault exit to idle
    END_IF
END_IF
IF _bCfgBad THEN                               // 组态域闸 / Config gate
    _uFault := 16#0005_03A1;                   // 故障级：分选故障总码 / Process fault code
    _eCause := E_DL_OcvCause.eCfgIllegal;      // 归因：组态非法 / Cause: illegal config
    _bFault := TRUE;                           // 标志与码位配对（R45） / Flag paired with code
END_IF

(* —— 段 3：落料超时与满 bin 换道（判据当拍量；下标写前钳制） —— *)
IF (NOT _bFault) AND tonDrop.Q THEN            // 落料超时 / Drop timeout
    _uFault := 16#0005_03A1;
    _eCause := E_DL_OcvCause.eDropTmo;         // 归因：落料超时 / Cause: drop timeout
    _bFault := TRUE;
END_IF
IF (NOT _bFault) AND (_nGrade >= 1) AND (_nGrade <= 4)
   AND (_anBinUsed[_nGrade] >= nBinCap) AND (NOT bBinCleared) THEN   // 目标 bin 已满且未清空 / Target bin full
    _uFault := 16#0005_03A1;
    _eCause := E_DL_OcvCause.eBinFull;         // 归因：满 bin 换道 / Cause: bin full
    _bFault := TRUE;
END_IF

(* —— 段 4：故障解除式（R240；全当拍量）：rtReset.Q / NOT _bCfgBad / NOT tonDrop.Q / bBinCleared —— *)
IF rtReset.Q AND (NOT _bCfgBad) AND (NOT tonDrop.Q) AND bBinCleared THEN
    _bFault := FALSE;                          // 清故障锁存位（锁存量） / Clear fault latch
    _uFault := 16#0000_0000;                   // 清故障锁存码（锁存量） / Clear fault code
    _eCause := E_DL_OcvCause.eNone;            // 清成因（锁存量） / Clear cause
END_IF

(* —— 段 4A：故障锁存相位迁移闸 —— *)
IF _bFault AND (_eState <> E_DL_OcvState.eFault) THEN
    _eState := E_DL_OcvState.eFault;           // 锁存即入故障相 / Latch enters fault phase
END_IF

(* —— 段 5：相位机（CASE 全覆盖 + ELSE 兜底） —— *)
CASE _eState OF

E_DL_OcvState.eIdle:
    IF bStart AND (NOT _bFault) THEN           // 启动条件 / Start gate
        _eState := E_DL_OcvState.eClassify;    // 进档位判定相 / Enter classification
    END_IF

E_DL_OcvState.eClassify:
    IF (_nGrade >= 1) AND (_nGrade <= 4) THEN  // 出口 1：档位有效（下标已钳制） / Valid grade
        _eState := E_DL_OcvState.eDispatch;    // 进落料相 / Enter dispatch
    ELSIF NOT bStart THEN                      // 出口 2：撤启动（R98 双出口） / Start released
        _eState := E_DL_OcvState.eIdle;
    END_IF

E_DL_OcvState.eDispatch:
    IF tonDrop.Q THEN                          // 落料到时 / Drop elapsed
        IF (_nGrade >= 1) AND (_nGrade <= 4) AND (NOT (_anBinUsed[_nGrade] >= nBinCap)) THEN
            _anBinUsed[_nGrade] := _anBinUsed[_nGrade] + 1;   // 计数递增（钳制下标 + 容量复核） / Increment with clamped index
        END_IF
        _uInfo := 16#0005_04C9;                // 信息级：单件分选完成沿 / Info: piece sorted edge
        _eState := E_DL_OcvState.eDone;        // 进完成相 / Enter done
    ELSIF NOT bStart THEN                      // 撤启动：中止 / Abort
        _eState := E_DL_OcvState.eIdle;
    END_IF

E_DL_OcvState.eDone:
    IF NOT bStart THEN                         // 撤启动回空闲 / Start released returns idle
        _eState := E_DL_OcvState.eIdle;
    END_IF

E_DL_OcvState.eFault:
    ;                                          // 故障相：仅段 4 复位沿可迁出 / Only reset exits

ELSE
    _uFault := 16#0005_03A1;                   // 故障级：非法相位兜底（归并总码） / Illegal phase fallback
    _eCause := E_DL_OcvCause.eCfgIllegal;      // 归因：相位非法归并组态 / Cause: phase illegal
    _bFault := TRUE;
    _eState := E_DL_OcvState.eFault;           // 强制回故障相 / Force fault phase

END_CASE

(* —— 段 6：出口单点映射（名实同源；锁存码回放） —— *)
nGrade := _nGrade;                             // 档位出口 / Grade outlet
anBinUsed[1] := _anBinUsed[1];                 // 1 档计数映射 / Grade 1 usage
anBinUsed[2] := _anBinUsed[2];                 // 2 档计数映射 / Grade 2 usage
anBinUsed[3] := _anBinUsed[3];                 // 3 档计数映射 / Grade 3 usage
anBinUsed[4] := _anBinUsed[4];                 // 4 档计数映射 / Grade 4 usage
bBinFull := (_nGrade >= 1) AND (_nGrade <= 4) AND (_anBinUsed[_nGrade] >= nBinCap);  // 满 bin 镜像 / Bin full mirror
bCycleDone := (_eState = E_DL_OcvState.eDone);// 完成标志 / Done flag
IF _bFault THEN
    nErrId := _uFault;                         // 故障锁存码回放 / Replay latched code
ELSE
    nErrId := _uInfo;                          // 信息码 / Transient info
END_IF
bError := _bFault;                             // 故障标志同源 / Flag from latch
eState := _eState;                             // 状态出口 / State outlet
eCause := _eCause;                             // 成因出口 / Cause outlet

END_FUNCTION_BLOCK
