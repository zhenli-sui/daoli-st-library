(*
  Name        : FC_DL_WrapIndexNeg
  Category    : DL_MathData
  Version     : 1.0.0
  Purpose     : 环窗下标负值模归正：把任意（含负）下标折叠进 [1..N] 或 [0..N-1] 合法区间，修正 IEC MOD 负余数语义；/ Fold any index (negative allowed) into [1..N] or [0..N-1], correcting IEC MOD negative-remainder semantics
  溯源        : 自研·环窗族治理（R193 配套），IEC 61131-3 标准语义的道莅防御性实现
  Boundary    : ① 模基数 diMod <= 0 → 返回 0 哨兵，不做除法（防除零）；
                ② IEC MOD 余数符号随被除数（负被除数得负余数），本件统一 +diMod 归正一次；
                ③ 1 基口径下 (diIdx - 1) 有下溢风险，先钳到 DINT 可表区间再折算；
                ④ 纯整型运算，无浮点比较、无 NaN/Inf 路径。
*)
FUNCTION FC_DL_WrapIndexNeg : DINT
VAR_INPUT
    diIdx     : DINT := 0;                   (* 输入下标，允许负值（如倒序回看 -3 表示前 3 个）[-] / Input index, negative allowed *)
    diMod     : DINT := 1;                   (* 模基数（窗深/表长），域 > 0 [-] / Modulus base, must be > 0 *)
    xOneBased : BOOL := TRUE;                 (* TRUE = 1 基口径 [1..diMod]；FALSE = 0 基口径 [0..diMod-1] [-] / 1-based or 0-based *)
END_VAR
VAR
    diBase : DINT;                            (* 折算到 0 基的中间量 [-] / Value folded to 0-based *)
    diRem  : DINT;                            (* IEC MOD 余数（可负，须归正）[-] / IEC MOD remainder, may be negative *)
END_VAR
VAR CONSTANT
    DL_WIN_DINTMAX : DINT := 2147483647;      (* DINT 可表上限（折算前钳位基准，R28 双边界）[#] / DINT representable max *)
    DL_WIN_DINTMIN : DINT := -2147483647;     (* 安全下限（避开 -2^31 取负溢出的自反陷阱）[#] / Safe DINT min avoiding negation overflow *)
END_VAR

(* —— 段 1：模基数闸（除零与非法基数唯一出入口，返回哨兵 0） —— *)
IF diMod <= 0 THEN
    FC_DL_WrapIndexNeg := 0;                  (* 哨兵 0：调用侧须以 diMod 闸先行拒绝 / Sentinel 0, caller must gate diMod *)
    RETURN;
END_IF

(* —— 段 2：输入下标双侧钳位（防 -2^31 取负溢出与 1 基折算下溢） —— *)
IF diIdx > DL_WIN_DINTMAX THEN
    diIdx := DL_WIN_DINTMAX;                  (* 上限钳位（可表性反算，非饱和业务语义） / Upper clamp for representability *)
ELSIF diIdx < DL_WIN_DINTMIN THEN
    diIdx := DL_WIN_DINTMIN;                  (* 下限钳位（-2^31 不参与折算，避开自反溢出） / Lower clamp avoiding self-negation overflow *)
END_IF

(* —— 段 3：折算到 0 基 + 负余数归正 —— *)
IF xOneBased THEN
    diBase := diIdx - 1;                      (* 1 基 → 0 基（已钳位，无下溢） / 1-based to 0-based *)
ELSE
    diBase := diIdx;                          (* 0 基直接用 / 0-based direct *)
END_IF
diRem := diBase MOD diMod;                    (* IEC MOD：余数符号随被除数，负被除数得负余数 / IEC MOD keeps dividend sign *)
IF diRem < 0 THEN
    diRem := diRem + diMod;                   (* 归正一次即落入 [0, diMod-1]（|diRem| < diMod 保证一次足够） / One fold suffices *)
END_IF

(* —— 段 4：回写目标口径 —— *)
IF xOneBased THEN
    FC_DL_WrapIndexNeg := diRem + 1;          (* 0 基 → 1 基，域 [1..diMod] / Back to 1-based *)
ELSE
    FC_DL_WrapIndexNeg := diRem;              (* 0 基直接输出，域 [0..diMod-1] / 0-based output *)
END_IF
END_FUNCTION
