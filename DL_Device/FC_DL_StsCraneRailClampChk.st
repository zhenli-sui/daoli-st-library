(*
 * FC_DL_StsCraneRailClampChk | C1 | DL_Device
 * 功能：夹轨器/顶轨器状态与联锁判定（命令-反馈一致性与轨道在位）       单位：xClampOk/xIllegal 为布尔，nFaultCode 为 INT 码位
 * 工况边界：仅判定静态组合，不持定时器（超时由调用方 FB 计时）；xAnchorFb 作为轨道在位的冗余反证（顶轨器伸出必然压轨）；无轨命令夹轨最危险，码位优先级最高
 * 代数值回代：xClampCmd=TRUE、xClampFb=TRUE、xRailPresent=TRUE、xAnchorFb=FALSE → xClampOk=TRUE、xIllegal=FALSE、nFaultCode=0（与 spec 判定式一致）
 * 开源溯源：clean-room 自研，未复制任何第三方代码（无外部来源）
 *)
FUNCTION FC_DL_StsCraneRailClampChk : BOOL
VAR_INPUT
    xClampCmd   : BOOL;              // 夹轨命令 | rail clamp command
    xClampFb    : BOOL;              // 夹轨到位反馈 | rail clamp engaged feedback
    xRailPresent: BOOL;              // 轨道在位检测 | rail presence detection
    xAnchorFb   : BOOL;              // 顶轨器/锚定销到位反馈 | jack or anchor pin engaged feedback
END_VAR
VAR_OUTPUT
    xClampOk   : BOOL;               // 夹轨有效（命令+反馈+轨道三者成立）| clamp effective, command and feedback and rail
    xIllegal   : BOOL;               // 联锁非法 | interlock violation
    nFaultCode : INT;                // 0=无 / 9202=命令反馈不一致 / 9203=无轨夹轨 | 0 none, 9202 command-feedback mismatch, 9203 clamping without rail
    xRailOk    : BOOL;               // 轨道在位判定结果（含顶轨器冗余反证）| rail verdict including the jack redundancy
    xValid     : BOOL;               // 输出有效（无联锁非法）| outputs valid, no interlock violation
END_VAR

// 段1｜轨道在位：直接检测 OR 顶轨器到位反证（两个独立来源任一生效即认为在位）
xRailOk := xRailPresent OR xAnchorFb;

// 段2｜夹轨有效：命令、到位反馈、轨道三者同时成立
xClampOk := xClampCmd AND xClampFb AND xRailOk;

// 段3｜联锁非法判定（按危险度排序：无轨夹轨优先于命令反馈不一致）
xIllegal := FALSE;
nFaultCode := 0;
IF xClampCmd AND (NOT xRailOk) THEN
    xIllegal := TRUE;
    nFaultCode := 9203;              // 无轨夹轨：机构空夹，最危险 | clamping without a rail, the most dangerous case
ELSIF xClampCmd AND (NOT xClampFb) THEN
    xIllegal := TRUE;
    nFaultCode := 9202;              // 命令已给但未到位（由调用方 FB 计时判超时）| command given but not engaged, timed by the caller
ELSIF (NOT xClampCmd) AND xClampFb THEN
    xIllegal := TRUE;
    nFaultCode := 9202;              // 无命令却有到位反馈（反馈粘连或指令丢失）| feedback stuck on without a command
END_IF

// 段4｜出口
xValid := NOT xIllegal;
FC_DL_StsCraneRailClampChk := xValid;
END_FUNCTION
