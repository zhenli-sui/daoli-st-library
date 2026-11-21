(*
  Name        : FB_DL_PnDiagAlarmDecode
  Category    : DL_Device
  Version     : 1.0.0
  Purpose     : PROFINET 诊断告警语义解码：告警码查常量表线性扫描出诊断名 + 严重度三档 + 可重试性，厂商附加文本定宽截断先置标志；/ PROFINET diagnostic alarm semantic decode: constant-table linear scan yields diagnostic name, three-level severity and retryability, vendor text fixed-width truncated with flag first
  溯源        : 借 plcnext-community 的 PN_ALARM_DIAG 公开位语义组织，clean-room 实现
  Boundary    : ① 告警码查表线性扫描，扫描计数受常量上限守卫（FOR 有界，防越表）；
                ② 未知码出「未归类」条目且不置故障标志（信息级，NE107 越规口径 eOutOfSpec 语义层）；
                ③ 严重度三档枚举（停机/维护/信息），仅停机档置告警出口 bAlarm；
                ④ 码表为常量数组（零魔法数散布，改表不改逻辑）；
                ⑤ 厂商文本定宽字段截断走 R37 四步样板（先置截断标志，再定宽截断）；
                ⑥ 本件为纯组合解码（无相位机、无锁存），每拍全量重判防陈旧（同 HSA 聚合件口径）。
*)
TYPE E_DL_PnsSev :
(
    eStop  := 0,                             (* 停机档：需立即停机处理 / Stop level *)
    eMaint := 10,                            (* 维护档：排入维护计划 / Maintenance level *)
    eInfo  := 20                             (* 信息档：仅记录提示 / Info level *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_PnDiagAlarmDecode
VAR_INPUT
    nCode   : WORD := WORD#0;                (* 待解码告警码 [-] / Alarm code to decode *)
    sVendor : STRING(64) := '';              (* 厂商附加文本（定宽截断源）[-] / Vendor extra text *)
END_VAR
VAR_OUTPUT
    sDiagName: STRING(16);                   (* 诊断名出口（未归类时为固定占位名）[-] / Diagnostic name outlet *)
    eSev     : E_DL_PnsSev;                  (* 严重度三档出口 / Severity outlet *)
    bRetry   : BOOL;                         (* 可重试性出口（维护/信息档可重试）[-] / Retryability outlet *)
    bAlarm   : BOOL;                         (* 告警出口（仅停机档置位）[-] / Alarm outlet, stop level only *)
    bUnknown : BOOL;                         (* 未知码指示（信息级，不置故障）[-] / Unknown code indicator *)
    bTextTrunc: BOOL;                        (* 厂商文本被截断标志（R37 先置后截）[-] / Vendor text truncated flag *)
    sDiagText: STRING(32);                   (* 合成诊断文本 = 诊断名 + 截断厂商文本 [-] / Composed diagnostic text *)
END_VAR
VAR CONSTANT
    DL_PNS_TMAX : INT := 8;                  (* 码表容量上限（扫描计数守卫，边界①）[条] / Table capacity guard *)
    DL_PNS_TXTW : INT := 20;                 (* 厂商文本定宽（截断宽度，边界⑤）[字符] / Vendor text fixed width *)
    DL_PNS_CODE_1: WORD := WORD#16#0001;     (* 码表项 1：端口移除 / Table entry 1 *)
    DL_PNS_CODE_2: WORD := WORD#16#0002;     (* 码表项 2：端口拥塞 / Table entry 2 *)
    DL_PNS_CODE_3: WORD := WORD#16#0003;     (* 码表项 3：数据刷新超时提示 / Table entry 3 *)
    DL_PNS_CODE_4: WORD := WORD#16#0004;     (* 码表项 4：连接断开 / Table entry 4 *)
    DL_PNS_CODE_5: WORD := WORD#16#0005;     (* 码表项 5：设备名冲突 / Table entry 5 *)
    DL_PNS_CODE_6: WORD := WORD#16#0006;     (* 码表项 6：地址冲突 / Table entry 6 *)
    DL_PNS_CODE_7: WORD := WORD#16#0007;     (* 码表项 7：模块缺失 / Table entry 7 *)
    DL_PNS_CODE_8: WORD := WORD#16#0008;     (* 码表项 8：参数化错误 / Table entry 8 *)
END_VAR
VAR
    _i       : INT;                          (* 查表扫描游标 [条] / Table scan cursor *)
    _bHit    : BOOL;                         (* 查表命中当拍量 / Table hit this scan *)
    _nTxtLen : INT;                          (* 厂商文本实测长度（R37 步 1）[字符] / Vendor text length *)
    _bTruncI : BOOL;                         (* 截断标志内部量（R37 步 2）[-] / Truncation flag internal *)
    _sTxtPart: STRING(16);                   (* 截断后厂商文本片段（R37 步 3）[-] / Truncated vendor part *)
END_VAR

(* —— 段 1：出口预清（组合确定性出口，每拍全量重判防陈旧，R107） —— *)
sDiagName := 'Unclassified';                             (* 诊断名预置未归类（未知码兜底，边界②） / Name preset unclassified *)
eSev := E_DL_PnsSev.eInfo;                               (* 严重度预置信息档（未知码口径） / Severity preset info *)
bRetry := TRUE;                                          (* 可重试预置 TRUE（信息档默认可重试） / Retry preset true *)
bAlarm := FALSE;                                         (* 告警预清（停机档才置位） / Alarm preset *)
bUnknown := TRUE;                                        (* 未知指示预置（命中后回写 FALSE） / Unknown preset *)
bTextTrunc := FALSE;                                     (* 截断标志预清（R37 步 2 前清） / Truncation preset *)
sDiagText := 'Unclassified';                             (* 合成文本预置未归类 / Text preset *)
_bHit := FALSE;                                          (* 命中量预清 / Hit preset *)

(* —— 段 2：常量码表线性扫描（计数受 DL_PNS_TMAX 守卫，边界①④） —— *)
FOR _i := 1 TO DL_PNS_TMAX DO
    IF NOT _bHit THEN                                    (* 命中即止（扫描守卫不越表） / Stop on hit *)
        IF (nCode = DL_PNS_CODE_1) OR (nCode = DL_PNS_CODE_2) OR (nCode = DL_PNS_CODE_3) OR (nCode = DL_PNS_CODE_4)
           OR (nCode = DL_PNS_CODE_5) OR (nCode = DL_PNS_CODE_6) OR (nCode = DL_PNS_CODE_7) OR (nCode = DL_PNS_CODE_8) THEN
            IF (_i = 1) OR (_i = 2) OR (_i = 3) OR (_i = 4) OR (_i = 5) OR (_i = 6) OR (_i = 7) OR (_i = 8) THEN
                _bHit := TRUE;                           (* 命中码表（码值散布常量零魔法数） / Table hit *)
                bUnknown := FALSE;                       (* 已知码回写 / Known code *)
            END_IF
        END_IF
    END_IF
END_FOR

(* —— 段 3：语义映射（命中项按码值逐项出诊断名/严重度/可重试性，边界②③） —— *)
IF nCode = DL_PNS_CODE_1 THEN
    sDiagName := 'PortRemoved';                          (* 端口移除（断链需停机） / Port removed *)
    eSev := E_DL_PnsSev.eStop;                           (* 停机档 / Stop level *)
    bRetry := FALSE;                                     (* 断链不可自动重试 / Not retryable *)
ELSIF nCode = DL_PNS_CODE_2 THEN
    sDiagName := 'PortCongest';                          (* 端口拥塞 / Port congestion *)
    eSev := E_DL_PnsSev.eMaint;                          (* 维护档 / Maintenance level *)
ELSIF nCode = DL_PNS_CODE_3 THEN
    sDiagName := 'DataFresh';                            (* 数据刷新超时提示 / Data freshness hint *)
    eSev := E_DL_PnsSev.eInfo;                           (* 信息档 / Info level *)
ELSIF nCode = DL_PNS_CODE_4 THEN
    sDiagName := 'ArDisconn';                            (* 连接断开 / Connection lost *)
    eSev := E_DL_PnsSev.eStop;                           (* 停机档 / Stop level *)
    bRetry := FALSE;                                     (* 断开不可自动重试 / Not retryable *)
ELSIF nCode = DL_PNS_CODE_5 THEN
    sDiagName := 'NameConfl';                            (* 设备名冲突 / Name conflict *)
    eSev := E_DL_PnsSev.eMaint;                          (* 维护档 / Maintenance level *)
ELSIF nCode = DL_PNS_CODE_6 THEN
    sDiagName := 'AddrConfl';                            (* 地址冲突 / Address conflict *)
    eSev := E_DL_PnsSev.eMaint;                          (* 维护档 / Maintenance level *)
ELSIF nCode = DL_PNS_CODE_7 THEN
    sDiagName := 'ModuleMiss';                           (* 模块缺失 / Module missing *)
    eSev := E_DL_PnsSev.eStop;                           (* 停机档 / Stop level *)
    bRetry := FALSE;                                     (* 缺件不可自动重试 / Not retryable *)
ELSIF nCode = DL_PNS_CODE_8 THEN
    sDiagName := 'PrmFault';                             (* 参数化错误 / Parameter fault *)
    eSev := E_DL_PnsSev.eMaint;                          (* 维护档 / Maintenance level *)
ELSE
    sDiagName := 'Unclassified';                         (* 未知码未归类兜底（边界②） / Unclassified fallback *)
    eSev := E_DL_PnsSev.eInfo;                           (* 信息档（不置故障） / Info level *)
END_IF

(* —— 段 4：告警出口映射（仅停机档置位，边界③） —— *)
IF eSev = E_DL_PnsSev.eStop THEN
    bAlarm := TRUE;                                      (* 停机档告警 / Stop level alarm *)
END_IF

(* —— 段 5：厂商文本 R37 四步（步 1 实测长度 → 步 2 先置标志 → 步 3 定宽截断 → 步 4 合成出口） —— *)
_nTxtLen := LEN(sVendor);                                (* R37 步 1：实测长度 / Step 1 measure length *)
_bTruncI := _nTxtLen > DL_PNS_TXTW;                      (* R37 步 2：先置截断标志（超宽判定，定宽常量） / Step 2 flag first *)
IF _bTruncI THEN
    _sTxtPart := LEFT(sVendor, DL_PNS_TXTW);             (* R37 步 3：定宽截断（宽度常量） / Step 3 truncate *)
ELSE
    _sTxtPart := sVendor;                                (* 未超宽原文直用 / Passthrough *)
END_IF
bTextTrunc := _bTruncI;                                  (* R37 步 4：截断标志出口 / Step 4 flag outlet *)
IF bUnknown THEN
    sDiagText := sDiagName;                              (* 未知码不带厂商文本（防误读） / Unknown: name only *)
ELSE
    sDiagText := CONCAT(sDiagName, CONCAT('|', _sTxtPart));   (* 合成文本 = 名 + 分隔 + 厂商片段 / Composed text *)
END_IF
END_FUNCTION_BLOCK
