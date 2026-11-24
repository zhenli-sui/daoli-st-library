(*
  FB_DL_ElTestStation  —  EL 检测工站（相机触发、缺陷坐标映射、OK/NG 归档） / EL test station: camera trigger, defect coordinate mapping, OK/NG archive
  分类 Category : DL_Process
  版本 Version  : 1.0.1
  来源 Source   : roadmap-pv-p2 — 光伏行业池 EL 检测缺口件
  溯源 Origin   : clean-room 实现，未复制任何源码行
  功能 Function : 1) 五相顺控：eIdle → eTrig（单发相机触发 bCamTrig，等回读
                  bCamDone，tCamTo 超时判）→ eMap（缺陷坐标映射：首缺陷
                  (fDefX,fDefY) 换算单元号 nDefCell，除法前域闸防除零）
                  → eDone（OK/NG 归档出口）→ 回 eIdle；
                  2) NG 判据：uDefCount > 0 且坐标在板面域内 → NG 归档
                  （uNgCount 累计）；uDefCount = 0 → OK 归档（uOkCount 累计）；
                  3) 故障级：0397 触发后超时无回读 / 0398 缺陷坐标越界或
                  非有限锁存（NG 侧防御，归档冻结）/ 0399 组态非法（行列、
                  单元尺寸域）+ ELSE 兜底归并；
                  4) 信息级三码：触发发出 / NG 归档 / OK 归档（单拍沿）；
                  5) 解除式全当拍量（R240 落地），逐 BOOL 标注见段 4。
  边界 Boundary : ① 组态闸：nRows/nCols = 0、fCellW/fCellH <= 0、tCamTo <= 0
                  → 0399 锁存，顺控停发；
                  ② 坐标映射前先做板面域闸（0 <= fDefX < fCellW*nCols 等），
                  域外或非有限 → 0398（NaN 自反判，R79）；TRUNC 前实数域钳制
                  （R151 实数转整数前域钳）；
                  ③ uDefCount 信任来源为相机契约 bCamDone 当拍（头注释声明）；
                  ④ 无 GVL 依赖：纯引脚输入输出，无外部变量引用，无物理 IO 地址。
  依赖 Depends  : Standard.library（TON / R_TRIG）
  码表 Error codes（Process 段 0005，窗口 0397~0399 / 04BF~04C1）:
    16#0005_0397 故障级：触发后超时无回读锁存（tCamTo），锁存至 bReset
    16#0005_0398 故障级：缺陷坐标越界或非有限锁存（防御兜底），锁存至 bReset
    16#0005_0399 故障级：组态非法（行列/单元尺寸/超时域非法）或相位落 ELSE 兜底（归并声明），锁存至 bReset
    16#0005_04BF 信息级：触发发出沿（bCamTrig 单发拍）
    16#0005_04C0 信息级：NG 归档沿（NG 判定拍）
    16#0005_04C1 信息级：OK 归档沿（OK 判定拍）
  修订历史 Revision :
    2026-11-19  v1.0.0  R42 首版（批次 3 · 序号 4）
    2026-11-19  v1.0.1  R42 终审返修：新增段 4A 故障锁存相位迁移闸——0397/0398/0399
                        锁存后 _eState 强制迁 eFault，断 tonCamTo 跨锁存期 IN 保持
                        （否则复位清锁后下一拍 Q 恒 TRUE 立即重锁 0397，解除式不可达），
                        并冻结 eTrig/eMap 相内快照与归档计数副作用；对外引脚契约不变。
*)

TYPE E_DL_EtsState :
(
    eIdle  := 0,     // 空闲：等测试指令 / Idle, waiting test command
    eTrig  := 10,    // 触发：等相机回读 / Trigger, waiting camera readback
    eMap   := 20,    // 映射：缺陷坐标换算单元号 / Map, defect coordinate to cell
    eDone  := 30,    // 完成：归档出口 / Done, archived
    eFault := 90     // 故障：超时或越界锁定 / Fault, latched
);
END_TYPE

FUNCTION_BLOCK FB_DL_ElTestStation
VAR_INPUT
    bTestCmd     : BOOL := FALSE;     // 测试指令，上升沿启动 [-] / Test command edge
    bCamDone     : BOOL := FALSE;     // 相机回读完成（当拍量）[-] / Camera readback done, current-scan
    uDefCount    : UDINT := 0;        // 缺陷点数（bCamDone 当拍采信）[个] / Defect count
    fDefX        : REAL := 0.0;       // 首缺陷 X 坐标 [mm]，板面域 / First defect X coordinate
    fDefY        : REAL := 0.0;       // 首缺陷 Y 坐标 [mm]，板面域 / First defect Y coordinate
    fCellW       : REAL := 50.0;      // 单元宽 [mm]，域 > 0 / Cell width
    fCellH       : REAL := 50.0;      // 单元高 [mm]，域 > 0 / Cell height
    nRows        : USINT := 6;        // 板面单元行数 [个]，域 > 0 / Cell rows
    nCols        : USINT := 10;       // 板面单元列数 [个]，域 > 0 / Cell cols
    tCamTo       : TIME := T#3S;      // 相机回读超时 [ms]，域 > 0 / Camera readback timeout
    bReset       : BOOL := FALSE;     // 复位，上升沿清故障锁存与归档计数 / Reset edge
END_VAR
VAR_OUTPUT
    eState       : E_DL_EtsState;     // 状态出口，段尾单点映射 / State outlet
    bCamTrig     : BOOL;              // 相机触发输出（eTrig 相电平）[-] / Camera trigger output
    nDefCell     : DINT;              // 首缺陷单元号 [0..nRows*nCols-1]，-1 = 无映射 / First defect cell index
    uNgCount     : UDINT;             // NG 归档累计 [片] / NG archive count
    uOkCount     : UDINT;             // OK 归档累计 [片] / OK archive count
    bError       : BOOL;              // 故障锁存标志 / Fault latch flag
    nErrId       : UDINT;             // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    tonCamTo     : TON;               // 相机回读超时（单相独占），无条件刷新 / Camera timeout
    rtTestCmd    : R_TRIG;            // 测试指令沿实例，无条件刷新 / Test command edge instance
    rtReset      : R_TRIG;            // 复位沿实例，无条件刷新 / Reset edge instance
    _eState      : E_DL_EtsState := E_DL_EtsState.eIdle;  // 内部相位（CASE 唯一写入目标）/ Internal phase
    _bTrigSent   : BOOL;              // 触发单发标志（eTrig 相内保持）/ Trigger one-shot flag
    _uDefSnap    : UDINT;             // 缺陷点数采信快照（锁存量）/ Defect count trusted snapshot
    _fXSnap      : REAL;              // 首缺陷 X 采信快照 [mm]（锁存量）/ First defect X snapshot
    _fYSnap      : REAL;              // 首缺陷 Y 采信快照 [mm]（锁存量）/ First defect Y snapshot
    _bNonFin     : BOOL;              // 坐标非有限当拍量 [-] / Non-finite coordinate flag
    _bInPanel    : BOOL;              // 坐标在板面域当拍量 [-] / Coordinate-in-panel flag
    _bFault      : BOOL;              // 故障锁存位（锁存量）/ Latched fault bit
    _uFault      : UDINT;             // 故障码锁存（锁存量）/ Latched fault code
    _uInfo       : UDINT;             // 信息码，每拍重算 / Transient info code
END_VAR

(* —— 段 0：定时器与沿实例无条件周期刷新（禁置于 IF/CASE 内） —— *)
_bNonFin := (fDefX <> fDefX) OR (fDefY <> fDefY)
         OR ((fDefX - fDefX) <> (fDefX - fDefX))
         OR ((fDefY - fDefY) <> (fDefY - fDefY));        // 坐标非有限防御（NaN 自反 + 差值自减）
_bInPanel := (NOT _bNonFin) AND (fDefX >= 0.0) AND (fDefX < fCellW * UDINT_TO_REAL(UINT(nCols)))
          AND (fDefY >= 0.0) AND (fDefY < fCellH * UDINT_TO_REAL(UINT(nRows)));
                                        // 坐标在板面域（当拍量，NaN 与一切比较 FALSE 故先排非有限）
rtTestCmd(CLK := bTestCmd);             // 测试沿（每拍必调）
rtReset(CLK := bReset);                 // 复位沿（每拍必调）
tonCamTo(IN := (_eState = E_DL_EtsState.eTrig), PT := tCamTo);   // 回读超时（单相独占）

(* —— 段 1：单拍量预清零（锁存量 _bFault/_uFault 与采信快照不入清单，禁同拍抹除） —— *)
_uInfo := 16#0000_0000;             // 信息码每拍重算
bCamTrig := FALSE;                  // 触发输出缺省 FALSE（单相承载）
nDefCell := -1;                     // 单元号缺省 -1
nErrId := 16#0000_0000;             // 事件码缺省无事件

(* —— 段 2：复位沿 + 组态域闸（判据当拍量） —— *)
IF rtReset.Q THEN                   // rtReset.Q = 当拍量
    _bFault := FALSE;               // 清故障锁存位
    _uFault := 16#0000_0000;        // 清故障锁存码
    _bTrigSent := FALSE;            // 触发单发标志清零
    uNgCount := 16#0000_0000;       // NG 累计清零
    uOkCount := 16#0000_0000;       // OK 累计清零
END_IF
IF (nRows = 0) OR (nCols = 0) OR (fCellW <= 0.0) OR (fCellH <= 0.0)
   OR (TIME_TO_DINT(tCamTo) <= 0) THEN
    _uFault := 16#0005_0399;        // 故障级：组态非法
    _bFault := TRUE;                // 故障标志与码位配对（R45）
END_IF

(* —— 段 3：回读超时与坐标防御锁存（判据当拍量） —— *)
IF (NOT _bFault) AND tonCamTo.Q THEN
    _uFault := 16#0005_0397;        // 故障级：触发后超时无回读
    _bFault := TRUE;
END_IF
IF (NOT _bFault) AND (_eState = E_DL_EtsState.eMap) AND ((_bNonFin) OR (NOT _bInPanel)) THEN
    _uFault := 16#0005_0398;        // 故障级：坐标越界或非有限
    _bFault := TRUE;
END_IF

(* —— 段 4：故障解除式（R240 落地，逐 BOOL 标注）：
     rtReset.Q = 当拍量；NOT bTestCmd = 当拍量；NOT bCamDone = 当拍量。
     均不含锁存量（_bFault/_uFault），解除边真实可达（指令撤销 + 复位沿）。 —— *)
IF rtReset.Q AND (NOT bTestCmd) AND (NOT bCamDone) THEN
    _bFault := FALSE;               // 清故障锁存位（锁存量，仅此当拍量解除沿可清）
    _uFault := 16#0000_0000;        // 清故障锁存码（锁存量，仅本当拍量解除沿可清）
    IF _eState = E_DL_EtsState.eFault THEN
        _eState := E_DL_EtsState.eIdle;     // 故障相迁出：回空闲
    END_IF
END_IF

(* —— 段 4A：故障锁存相位迁移闸（R42 终审返修，v1.0.1）：
     锁存置位而相位未迁出（0397 超时相 eTrig / 0398 越界相 eMap / 0399 组态任意相）
     时强制入故障相：断 tonCamTo 跨锁存期 IN 保持（IN 恒 TRUE 则 Q 恒 TRUE，
     复位清锁后下一拍立即重锁，解除式不可达），并冻结 eTrig/eMap 相内快照
     与归档副作用；置于段 4 之后，解除沿当拍清锁不触发迁移，无同拍抢迁。 —— *)
IF _bFault AND (_eState <> E_DL_EtsState.eFault) THEN
    _eState := E_DL_EtsState.eFault;        // 锁存即入故障相（锁存量 _bFault 仅解除沿可清，迁移保持至解除）
END_IF

(* —— 段 5：相位机（CASE 全覆盖 + ELSE 兜底） —— *)
CASE _eState OF

E_DL_EtsState.eIdle:
    IF rtTestCmd.Q AND (NOT _bFault) THEN
        _bTrigSent := FALSE;            // 单发标志复位（进相预置）
        _eState := E_DL_EtsState.eTrig; // 进触发相
    END_IF

E_DL_EtsState.eTrig:
    bCamTrig := TRUE;                   // 触发电平（相承载）
    IF NOT _bTrigSent THEN
        _uInfo := 16#0005_04BF;         // 信息级：触发发出沿（进相首拍单发）
        _bTrigSent := TRUE;             // 单发标志
    END_IF
    IF bCamDone THEN                    // 回读完成（当拍量）：采信契约快照
        bCamTrig := FALSE;              // 触发撤销
        _uDefSnap := uDefCount;         // 缺陷数快照（锁存量，仅此处写）
        _fXSnap := fDefX;               // X 快照（锁存量，仅此处写）
        _fYSnap := fDefY;               // Y 快照（锁存量，仅此处写）
        _eState := E_DL_EtsState.eMap;  // 进映射相
    END_IF
    (* 回读超时迁出在段 3 承载 *)

E_DL_EtsState.eMap:
    IF (_bNonFin) OR (NOT _bInPanel) THEN
        ;                               // 越界/非有限迁出在段 3 承载（映射冻结）
    ELSE
        IF _uDefSnap > 0 THEN           // NG 判据（快照域）
            nDefCell := TRUNC(_fXSnap / fCellW) + TRUNC(_fYSnap / fCellH) * USINT_TO_DINT(nCols);
                                        // 单元号映射（域闸已保分母 > 0 与商 < 行列数，无越界；TRUNC 向零取整）
            uNgCount := uNgCount + 1;   // NG 累计递增
            _uInfo := 16#0005_04C0;     // 信息级：NG 归档沿
        ELSE
            uOkCount := uOkCount + 1;   // OK 累计递增
            _uInfo := 16#0005_04C1;     // 信息级：OK 归档沿
        END_IF
        _eState := E_DL_EtsState.eDone; // 进完成相
    END_IF

E_DL_EtsState.eDone:
    IF NOT bTestCmd THEN                // 测试指令撤销：回空闲
        _eState := E_DL_EtsState.eIdle;
    END_IF

E_DL_EtsState.eFault:
    ;                                   // 故障相：归档冻结，等解除沿（段 4 承载迁出）

ELSE
    _uFault := 16#0005_0399;            // 故障级：非法相位兜底（归并组态码，码表声明）
    _bFault := TRUE;
    _eState := E_DL_EtsState.eFault;    // 强制回故障相

END_CASE

(* —— 段 6：出口单点映射（名实同源；锁存码回放，禁同拍抹除） —— *)
IF _bFault THEN
    nErrId := _uFault;              // 故障锁存码回放
    bCamTrig := FALSE;              // 故障相触发输出强制 FALSE（安全侧）
    nDefCell := -1;                 // 故障相单元号恢复哨兵
ELSE
    nErrId := _uInfo;               // 信息码
END_IF
bError := _bFault;                  // 故障标志与锁存位同源
eState := _eState;                  // 状态出口单点映射

END_FUNCTION_BLOCK
