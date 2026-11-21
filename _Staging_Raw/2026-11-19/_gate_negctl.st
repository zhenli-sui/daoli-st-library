FUNCTION_BLOCK FB_DL_NegControl
VAR_INPUT
    bGo : BOOL;  // 触发
END_VAR
VAR
    nI : INT;  // 计数
END_VAR
IF bGo THEN
    nI := nI + 1;
    (* 未闭合块注释
END_IF;
