(*
  道莅工业代码库 / Daoli Industrial ST Library
  组件: FC_DL_PmScheduleNext
  分类: DL_Device
  开源溯源: 无（clean-room 工程公式自研；参考公开工艺计算公式，未复制任何受版权保护代码）
  许可证: 本项目自有 (MIT)
  功能: 由上次 PM 时刻与周期天数推算下次 PM 时刻、下次 PM 日期与逾期天数
  时基声明: 时刻统一经 DT_TO_DINT 折算为「自 1970-01-01 起的秒计数」做整数运算，
            避免 TIME 型毫秒量在 24.8 天以上溢出 DINT；最大 3650 d × 86400 s = 3.15E8 s 安全
*)
FUNCTION FC_DL_PmScheduleNext : BOOL
VAR_INPUT
    dtLast : DT; // 上次 PM 完成时刻 [DT] / last PM completion timestamp
    dtNow : DT; // 当前时刻 [DT] / current timestamp
    iIntervalDays : INT; // PM 周期 [d]，域 (0, 3650] / PM interval in days
END_VAR
VAR_OUTPUT
    dtNext : DT; // 下次 PM 到期时刻 [DT] / next PM due timestamp
    dNextDate : DATE; // 下次 PM 到期日期 [DATE] / next PM due date, operator friendly
    iOverdueDays : INT; // 逾期天数 [d]，未逾期为 0 / overdue days, zero when not overdue
    bValid : BOOL; // 结果有效位 [-] / result valid flag
    bOverdue : BOOL; // 逾期标志 [-] / overdue flag
    iErrCode : INT; // 事件码 0=正常 1=周期超域 2=上次时刻未初始化 3=秒计数溢出 / event code
END_VAR
VAR CONSTANT
    diSecPerDay : DINT := 86400; // 每日秒数 [s/d] / seconds per day
    diIntervalMax : DINT := 3650; // 周期天数上限 [d] / interval upper bound
END_VAR
VAR
    diLastSec : DINT; // 上次 PM 秒计数 [s] / last PM as seconds
    diNowSec : DINT; // 当前时刻秒计数 [s] / now as seconds
    diSpanSec : DINT; // 周期秒数 [s] / interval in seconds
    diNextSec : DINT; // 下次 PM 秒计数 [s] / next due as seconds
    diDiffSec : DINT; // 逾期秒数 [s] / overdue seconds
END_VAR

    // —— 段 0：全路径预清 —— //
    diLastSec := 0;
    diNowSec := 0;
    diSpanSec := 0;
    diNextSec := 0;
    diDiffSec := 0;
    dtNext := dtLast;
    dNextDate := DT_TO_DATE(dtLast);
    iOverdueDays := 0;
    bValid := FALSE;
    bOverdue := FALSE;
    iErrCode := 0;
    FC_DL_PmScheduleNext := FALSE;
    // —— 段 1：周期域闸 (0, 3650]d —— //
    IF (iIntervalDays <= 0) OR (INT_TO_DINT(iIntervalDays) > diIntervalMax) THEN
        iErrCode := 1; // 周期超域，不生成计划 / interval out of domain, no schedule issued
        RETURN;
    END_IF;
    // —— 段 2：上次时刻有效性闸（零值 = 未初始化） —— //
    diLastSec := DT_TO_DINT(dtLast); // 上次 PM 秒计数 [s] / last PM in seconds
    IF diLastSec <= 0 THEN
        iErrCode := 2; // 上次时刻未初始化 / last timestamp not initialised
        RETURN;
    END_IF;
    // —— 段 3：量纲链 (d)×(s/d) = s；加法后反查是否溢出为负 —— //
    diSpanSec := INT_TO_DINT(iIntervalDays) * diSecPerDay; // 周期秒数 [s] / interval in seconds
    diNextSec := diLastSec + diSpanSec; // 下次秒计数 [s] / next due in seconds
    IF diNextSec < diLastSec THEN
        iErrCode := 3; // 秒计数溢出，放弃本次计划 / second counter overflow, schedule dropped
        RETURN;
    END_IF;
    dtNext := DINT_TO_DT(diNextSec); // 下次到期时刻 [DT] / next due timestamp
    dNextDate := DT_TO_DATE(dtNext); // 到期日期 [DATE] / due date
    // —— 段 4：逾期天数 = MAX(0, (now-next)/86400) —— //
    diNowSec := DT_TO_DINT(dtNow); // 当前秒计数 [s] / now in seconds
    IF diNowSec > diNextSec THEN
        diDiffSec := diNowSec - diNextSec; // 逾期秒数 [s] / overdue seconds
        iOverdueDays := DINT_TO_INT(diDiffSec / diSecPerDay); // 逾期天数 [d] / overdue days
        bOverdue := TRUE;
    ELSE
        bOverdue := FALSE; // 未逾期 / not overdue
    END_IF;
    bValid := TRUE;
    FC_DL_PmScheduleNext := TRUE;
END_FUNCTION
