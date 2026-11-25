(*
  道莅工业代码库 / Daoli Industrial ST Library
  组件: FC_DL_ClarifierSurfaceLoad
  分类: DL_Process
  开源溯源: 无（clean-room 工程公式自研；参考公开工艺计算公式，未复制任何受版权保护代码）
  许可证: 本项目自有 (MIT)
  功能: 沉淀池表面水力负荷计算与上限越限判定
*)
FUNCTION FC_DL_ClarifierSurfaceLoad : BOOL
VAR_INPUT
    rFlowM3h : REAL; // 进水流量 [m3/h] / influent flow
    rAreaM2 : REAL; // 沉淀池有效沉淀面积 [m2] / effective settling area
    rLimitM3m2h : REAL; // 表面负荷设计上限 [m3/(m2·h)] / design surface loading limit
END_VAR
VAR_OUTPUT
    rLoadM3m2h : REAL; // 表面水力负荷 [m3/(m2·h)] / surface hydraulic loading
    bValid : BOOL; // 结果有效位 [-] / result valid flag
    bOver : BOOL; // 越限标志（负荷高于设计上限）[-] / over-limit flag
    iErrCode : INT; // 事件码 0=正常 1=面积非法 2=结果非有限 / event code
END_VAR
VAR
    rLoadRaw : REAL; // 未限幅负荷 [m3/(m2·h)] / unlimited loading
END_VAR

    // —— 段 0：全路径预清 —— //
    rLoadRaw := 0.0;
    rLoadM3m2h := 0.0;
    bValid := FALSE;
    bOver := FALSE;
    iErrCode := 0;
    FC_DL_ClarifierSurfaceLoad := FALSE;
    // —— 段 1：分母闸（沉淀面积必须为正） —— //
    IF rAreaM2 <= 0.0 THEN
        iErrCode := 1; // 面积非法，负荷无定义 / invalid area, loading undefined
        RETURN;
    END_IF;
    // —— 段 2：量纲链 (m3/h)/(m2) = m3/(m2·h) —— //
    rLoadRaw := rFlowM3h / rAreaM2; // 表面负荷 [m3/(m2·h)] / surface loading
    // —— 段 3：结果域闸（非有限即归零作废） —— //
    IF ABS(rLoadRaw) > 1.0E15 THEN
        iErrCode := 2; // 结果非有限，强制归零 / non-finite result, forced to zero
        RETURN;
    END_IF;
    // —— 段 4：负流量防御与出参收口 —— //
    IF rLoadRaw < 0.0 THEN
        rLoadM3m2h := 0.0; // 负流量无物理意义 / negative flow is unphysical
    ELSE
        rLoadM3m2h := rLoadRaw;
    END_IF;
    bOver := rLoadM3m2h > rLimitM3m2h; // 越限判定 [-] / over-limit test
    bValid := TRUE;
    FC_DL_ClarifierSurfaceLoad := TRUE;
END_FUNCTION
