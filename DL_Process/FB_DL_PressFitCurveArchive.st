(*
  Component : FB_DL_PressFitCurveArchive
  Category  : DL_Process
  Type      : FB
  Version   : 1.0.0
  CodeSeg   : 16#06_0_3B
  Summary   : 压装曲线特征点归档与批次追溯：四特征点环形缓存按批次号索引，R_TRIG 沿触发归档。
              Press-fit curve feature archive by batch index in a ring buffer, triggered on a rising edge.
  溯源声明  : 道莅自研 clean-room
  边界安全  : 批次号域闸（> 0，防非法索引）；环形缓冲下标 1..NMAX 硬界，写前钳制防越界；
              特征点非有限（NaN 自反 + Inf 上限）拦截；查询命中用整数相等（DINT）；
              R_TRIG 每拍无条件刷新（段 0）；缓冲满环回写并置 bWrapped 提示；计数防回卷。
  复用      : 无
*)

FUNCTION_BLOCK FB_DL_PressFitCurveArchive
VAR_INPUT
    bRun       : BOOL;                  (* 归档使能 · Enable *)
    bArchCmd   : BOOL;                  (* 归档指令 [事件]，沿触发 · Archive command, edge *)
    nBatchNo   : DINT;                  (* 批次号 [号]，域 > 0 · Batch number *)
    fF1KN      : LREAL;                 (* 特征点 1：起步压力 [kN] · Feature 1 onset force *)
    fF2MM      : LREAL;                 (* 特征点 2：起步位移 [mm] · Feature 2 onset travel *)
    fF3KN      : LREAL;                 (* 特征点 3：峰值压力 [kN] · Feature 3 peak force *)
    fF4MM      : LREAL;                 (* 特征点 4：终点位移 [mm] · Feature 4 end travel *)
    nQueryNo   : DINT;                  (* 追溯查询批次号 [号] · Query batch number *)
    fEps       : LREAL := 1.0E-6;       (* 浮点判零容差 [实数域] · Floating zero tolerance *)
END_VAR
VAR_OUTPUT
    bArchOk  : BOOL;                    (* 本拍归档成功 [开关] · Archive succeeded this scan *)
    bWrapped : BOOL;                    (* 环已回卷覆盖标志 · Ring wrapped flag *)
    bFound   : BOOL;                    (* 查询命中标志 · Query hit flag *)
    fQ1KN    : LREAL;                   (* 查询特征 1 [kN] · Queried feature 1 *)
    fQ2MM    : LREAL;                   (* 查询特征 2 [mm] · Queried feature 2 *)
    fQ3KN    : LREAL;                   (* 查询特征 3 [kN] · Queried feature 3 *)
    fQ4MM    : LREAL;                   (* 查询特征 4 [mm] · Queried feature 4 *)
    nUsed    : INT;                     (* 环内已用槽数 [槽] · Used slots *)
    bError   : BOOL;                    (* 故障标志，与故障码配对 · Fault flag paired with codes *)
    uErrorId : UDINT;                   (* 事件码 16#0000_003B，0 无事件 · Event code *)
END_VAR
VAR
    uCode   : WORD;     (* 码位暂存，每拍重算 [码] · Code staging *)
    rTrigArc: R_TRIG;   (* 归档上升沿，每拍无条件刷新 · Archive edge detection *)
    aIdx    : ARRAY[1..8] OF DINT;      (* 批次号索引槽 [号] · Batch index slots *)
    aF1     : ARRAY[1..8] OF LREAL;     (* 特征 1 缓存 [kN] · Feature 1 buffer *)
    aF2     : ARRAY[1..8] OF LREAL;     (* 特征 2 缓存 [mm] · Feature 2 buffer *)
    aF3     : ARRAY[1..8] OF LREAL;     (* 特征 3 缓存 [kN] · Feature 3 buffer *)
    aF4     : ARRAY[1..8] OF LREAL;     (* 特征 4 缓存 [mm] · Feature 4 buffer *)
    nHead   : INT;      (* 环形写头下标 [索引] · Ring head index *)
    nI      : INT;      (* 查询循环下标 [索引] · Query loop index *)
    bSigOk  : BOOL;     (* 输入有效标志 · Input validity flag *)
    nCycles : UDINT;    (* 归档累计 [次]，防回卷 · Archive count *)
END_VAR
VAR CONSTANT
    DL_PCA_NMAX : INT := 8;             (* 环形缓冲容量 [槽] · Ring capacity *)
    DL_PCA_WRAP : UDINT := 4294967290;  (* 计数防回卷余量 [次] · Counter wrap guard *)
END_VAR

(* === 段 0 · 实例刷新（每拍无条件，红线 7）=== *)
IF nHead < 1 THEN
    nHead := 1;                         (* 写头初值钳 1，防数组零下标越界 / Clamp the head to one *)
END_IF
rTrigArc(CLK := bArchCmd);              (* 归档沿检测 / Archive edge *)

(* === 段 1 · 输入校验与量程闸 === *)
uCode := 16#0000;                       // 每拍清码（可达清零基线）/ Clear codes each scan
bSigOk := (nBatchNo > 0)                                             // 批次号正域闸 / Batch number gate
          AND (fF1KN = fF1KN) AND (fF2MM = fF2MM)                     // 特征点非有限拦截 / Non-finite guards
          AND (fF3KN = fF3KN) AND (fF4MM = fF4MM)
          AND (ABS(fF1KN) < 1.0E308) AND (ABS(fF3KN) < 1.0E308)       // Inf 上限判据 / Inf limits
          AND (ABS(fF2MM) < 1.0E308) AND (ABS(fF4MM) < 1.0E308)
          AND (fF3KN > fF1KN);                                        // 峰值起步序闸 / Peak above onset
IF NOT bSigOk THEN
    uCode := 16#003B;                   // 故障级：域外，归档拒绝 / Fault: domain invalid
END_IF

(* === 段 2 · 主逻辑：环形归档与批次追溯 === *)
bArchOk := FALSE;                       (* 归档成功标志单拍重建 / Rebuild the success flag *)
IF rTrigArc.Q AND bRun THEN
    IF bSigOk THEN
        aIdx[nHead] := nBatchNo;        (* 写批次索引（头下标受 NMAX 硬界）/ Write the index *)
        aF1[nHead] := fF1KN;            (* 写特征 1 [kN] / Write feature 1 *)
        aF2[nHead] := fF2MM;            (* 写特征 2 [mm] / Write feature 2 *)
        aF3[nHead] := fF3KN;            (* 写特征 3 [kN] / Write feature 3 *)
        aF4[nHead] := fF4MM;            (* 写特征 4 [mm] / Write feature 4 *)
        bArchOk := TRUE;                (* 归档成功 / Archive done *)
        IF nUsed < DL_PCA_NMAX THEN
            nUsed := nUsed + 1;         (* 未满先增用量 / Grow usage *)
        ELSE
            bWrapped := TRUE;           (* 满环回卷提示 / Ring wrapped flag *)
        END_IF
        nHead := (nHead MOD DL_PCA_NMAX) + 1;   (* 写头循环推进，界内 / Advance the head in bounds *)
        IF nCycles < DL_PCA_WRAP THEN
            nCycles := nCycles + 1;     (* 归档计数 / Count archives *)
        END_IF
    END_IF
END_IF
(* 追溯查询：按批次号线性匹配（DINT 等值合法）/ Trace query by batch number *)
bFound := FALSE;                        (* 命中标志单拍重建 / Rebuild the hit flag *)
IF (nQueryNo > 0) AND (nUsed >= 1) THEN
    FOR nI := 1 TO DL_PCA_NMAX DO
        IF nI <= nUsed THEN
            IF aIdx[nI] = nQueryNo THEN
                fQ1KN := aF1[nI];       (* 命中回放特征 1 [kN] / Replay feature 1 *)
                fQ2MM := aF2[nI];       (* 回放特征 2 [mm] / Replay feature 2 *)
                fQ3KN := aF3[nI];       (* 回放特征 3 [kN] / Replay feature 3 *)
                fQ4MM := aF4[nI];       (* 回放特征 4 [mm] / Replay feature 4 *)
                bFound := TRUE;         (* 命中 / Hit *)
                EXIT;                   (* 单命中即止 / Stop on first hit *)
            END_IF
        END_IF
    END_FOR
END_IF

(* === 段 3 · 输出映射与故障码 === *)
IF NOT bFound THEN
    fQ1KN := 0.0;                       (* 未命中输出安全零（哨兵）/ Safe zeros on miss *)
    fQ2MM := 0.0;
    fQ3KN := 0.0;
    fQ4MM := 0.0;
END_IF
IF NOT bRun THEN
    bWrapped := FALSE;                  (* 撤使能清回卷提示（可达清零）/ Clear on disable *)
END_IF
bError := (uCode <> 16#0000);           (* 故障标志配对 / Fault flag paired *)
uErrorId := WORD_TO_UDINT(uCode);       (* 码位单点写入（16#0000_003B 形态）/ Single write point *)
END_FUNCTION_BLOCK
