(*
  Name        : FB_DL_HealthStatusArbiter
  Category    : DL_Device
  Version     : 1.0.0
  Purpose     : 多源 NE107 健康仲裁聚合：N 路健康枚举逐件直比最差胜出（仅已知源参与），聚合出口单一健康态；/ Multi-source NE107 health arbitration: N health status entries compared item-wise with the worst known winning, aggregated into a single health outlet
  溯源        : 借 t2-8 NE107/ISA-18.2 的分类/参数域组织，clean-room 实现
  依赖声明    : 引用 E_DL_Ne107Status（唯一属主 DL_Device 契约件 I_DL_DeviceHealth），不重造枚举；
                该枚举数值即优先级：数值最小最差（eFailure = 0 最差，eOk = 40，eUnknown = 99 不参与仲裁）。
  Boundary    : ① 源计数越界钳 NMAX（8），负数/零计数聚合出 eUnknown 且来源序号出口 0；
                ② 最差态判定为数值直比取最小（编号即优先级），逐件遍历无排序无锁存；
                ③ 单路 eUnknown 不抬高也不拉低聚合结论（仅已知源参与），全部未知时聚合出 eUnknown；
                ④ 仲裁为纯组合重算（无状态机、无锁存），每拍全量重判防陈旧（本件按边界④不设相位机）；
                ⑤ 出口与 I_DL_DeviceHealth 六态契约同源（E_DL_Ne107Status），不重造枚举；
                ⑥ 零外部全局、零物理地址，纯函数式聚合可跨平台移植。
*)
FUNCTION_BLOCK FB_DL_HealthStatusArbiter
VAR_INPUT
    aHealth : ARRAY[1..8] OF E_DL_Ne107Status;   (* 各源 NE107 健康态（六态契约同源）[-] / Health status per source *)
    nCount  : INT := 8;                      (* 参与仲裁源计数，域 1..8 [路] / Source count in arbitration *)
END_VAR
VAR_OUTPUT
    eAgg    : E_DL_Ne107Status;              (* 聚合健康态出口（最差胜出）[-] / Aggregated health outlet *)
    nWorstSrc: INT;                          (* 最差来源序号（1 基，0 = 无已知源）[-] / Worst source index *)
    nKnown  : INT;                           (* 已知源计数（诊断）[路] / Known source count *)
END_VAR
VAR CONSTANT
    DL_HSA_NMAX   : INT := 8;                (* 源数容量上限（钳位）[路] / Source capacity limit *)
END_VAR
VAR
    _eWorst : E_DL_Ne107Status := E_DL_Ne107Status.eUnknown;   (* 当前最差态（哨兵 = 未知，枚举直存不转整数） / Current worst status *)
    _nKnown : INT;                           (* 已知源计数累加量 [路] / Known source accumulator *)
    _i      : INT;                           (* 生效源计数（钳位后）[路] / Effective source count *)
    _j      : INT;                           (* 遍历游标 [路] / Loop cursor *)
END_VAR

(* —— 段 1：出口预清（组合确定性出口，无陈旧，R107） —— *)
eAgg := E_DL_Ne107Status.eUnknown;                       (* 聚合出口预置未知 / Agg outlet preset unknown *)
nWorstSrc := 0;                                          (* 最差来源序号预置 0 / Worst source preset zero *)
_nKnown := 0;                                            (* 已知源计数清零 / Known count clear *)
_eWorst := E_DL_Ne107Status.eUnknown;                    (* 最差态预置哨兵（未遇到已知源） / Worst preset sentinel *)
nKnown := 0;                                             (* 已知源计数出口预清 / Known count outlet preset *)

(* —— 段 2：源计数域闸 + 钳位（边界①） —— *)
IF (nCount < 1) OR (nCount > DL_HSA_NMAX) THEN
    _i := DL_HSA_NMAX;                                   (* 越界钳上限（含负数与零保护） / Clamp to capacity *)
ELSE
    _i := nCount;                                        (* 域内直用 / In domain direct *)
END_IF

(* —— 段 3：逐件直比仲裁（枚举有序比较，最小 = 最差胜出，边界②③；FOR 有界无死循环） —— *)
FOR _j := 1 TO _i DO
    IF aHealth[_j] <> E_DL_Ne107Status.eUnknown THEN     (* 未知源不参与仲裁（边界③） / Unknown source skipped *)
        _nKnown := _nKnown + 1;                          (* 已知源计数累加 / Known count accumulate *)
        IF aHealth[_j] < _eWorst THEN                    (* 枚举有序直比取最小 = 最差（编号即优先级） / Enum ordered compare, min wins *)
            _eWorst := aHealth[_j];                      (* 更新最差态 / Update worst *)
            nWorstSrc := _j;                             (* 记录最差来源序号 / Record worst source *)
        END_IF
    END_IF
END_FOR
nKnown := _nKnown;                                       (* 已知源计数出口 / Known count outlet *)

(* —— 段 4：聚合出口映射（全未知 → eUnknown 哨兵保持，边界③④） —— *)
IF _eWorst <> E_DL_Ne107Status.eUnknown THEN
    eAgg := _eWorst;                                     (* 最差态回映射聚合出口 / Worst to aggregate outlet *)
END_IF
END_FUNCTION_BLOCK
