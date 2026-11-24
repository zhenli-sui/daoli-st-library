(*
  ==================================================================
  组件名 Component  : FB_DL_CraneAntiSway
  分类   Category   : DL_Algo
  复杂度 Complexity  : 中
  版本   Version    : 1.0.0
  功能   Purpose    : 桥式起重机防摆控制。摆角/摆速反馈相位对消：补偿量
                      fCorr = K1·角度 + K2·摆速 叠加到运行速度指令；输出
                      钳位 ±fVmax；防摆-定位双模：|角度| < 角容差 且 |摆速|
                      < 速容差 时置定位带内 bInPosBand（供定位模切换判据）。
                      GitHub topics crane 线公开语义 clean-room。
  来源   Source     : T1-8-github-topics（crane 防摆公开语义）
  溯源   Origin     : 摆角/摆速相位对消为公开控制语义，clean-room 自研实现，
                      未复制任何厂商私有库源码。
  平台   Platform   : 纯 IEC 61131-3，CODESYS / TwinCAT / InoProShop 通用
  分工声明 Split     : 与 FB_DL_LookaheadVelPlanner 分工——后者做速度前瞻，
                      本件做摆动反馈补偿叠加。
  作者   Author     : 道莅代码库 · PLC 编程专家（R59）
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 非有限闸（自反双判据，三输入全覆盖）：命中置 bBad
                         （本库纪律②），fVout 安全侧零；
                      二 输出硬钳位 ±fVmax 单点回夹并置 bClamped（信息级）；
                      三 失能安全语义：bEnable = FALSE 时 fVout = 0（安全侧
                         零速，防摆-定位双模声明 R191）；
                      四 补偿增益组态域由调用方保证（K1/K2 为负值使摆角正
                         馈回拉），本件不二次钳制；
                      五 无全局变量、无外部变量声明、无物理地址寻址。
  修订记录 Revision  :
    2026-11-21  v1.0.0  R59 首版（批 3 · 序号 12）
  ==================================================================
*)

FUNCTION_BLOCK FB_DL_CraneAntiSway
VAR_INPUT
    fVcmd       : LREAL := 0.0;  // 运行速度指令 [毫米每秒] / the travel velocity command [millimeter per second]
    fAngDeg     : LREAL := 0.0;  // 摆角反馈 [度] / the sway angle feedback [degree]
    fAngVelDegS : LREAL := 0.0;  // 摆速反馈 [度每秒] / the sway angular velocity feedback [degree per second]
    fK1         : LREAL := -2.0; // 摆角补偿增益 [（毫米每秒）每度] / the angle compensation gain
    fK2         : LREAL := -8.0; // 摆速补偿增益 [（毫米每秒）每（度每秒）] / the velocity compensation gain
    fVmax       : LREAL := 500.0; // 输出速度上界 [毫米每秒] / the outlet velocity bound [millimeter per second]
    fPosAngTol  : LREAL := 1.0;  // 定位带角容差 [度] / the positioning angle tolerance [degree]
    fPosVelTol  : LREAL := 2.0;  // 定位带速容差 [度每秒] / the positioning velocity tolerance [degree per second]
    bAntiSwayEn : BOOL := TRUE;  // 防摆补偿使能（定位模可关）[-] / the anti sway enable
    bEnable     : BOOL := FALSE; // 输出使能，失能安全侧零 [-] / the outlet enable, the safe zero when disabled
END_VAR
VAR_OUTPUT
    fVout     : LREAL := 0.0; // 补偿后速度输出 [毫米每秒] / the compensated velocity outlet
    fCorr     : LREAL := 0.0; // 防摆补偿量（观测用）[毫米每秒] / the anti sway compensation, observable
    bInPosBand: BOOL := FALSE; // 定位带内判据（双模切换依据）[-] / the in position band verdict
    bClamped  : BOOL := FALSE; // 输出钳位发生（信息级）[-] / the outlet clamp happened, informational
    bBad      : BOOL := FALSE; // 非有限输入实时标志 [-] / the non finite input flag
    bValid    : BOOL := FALSE; // 输出可用标志 [-] / the output usable flag
END_VAR
VAR
    _fV   : LREAL; // 补偿后速度工作量 [毫米每秒] / the compensated velocity work value
    _bFin : BOOL;  // 输入有限工作量 [-] / the input finiteness work flag
END_VAR

// 段 1｜输出预置与非有限闸（四段式，R45 + 本库纪律②）/ segment 1, the preset and the non finite gate
fVout := 0.0; // 输出预置安全零 / preset the safe zero
fCorr := 0.0; // 补偿预置零 / preset the compensation zero
bClamped := FALSE; // 钳位预置假 / preset the clamp false
bValid := FALSE; // 有效预置假 / preset the valid false
_bFin := (fVcmd = fVcmd) AND ((fVcmd - fVcmd) = (fVcmd - fVcmd)) // 指令有限 / the command finite
    AND (fAngDeg = fAngDeg) AND ((fAngDeg - fAngDeg) = (fAngDeg - fAngDeg)) // 摆角有限 / the angle finite
    AND (fAngVelDegS = fAngVelDegS) AND ((fAngVelDegS - fAngVelDegS) = (fAngVelDegS - fAngVelDegS)); // 摆速有限 / the velocity finite
bBad := NOT _bFin; // 拒收实时标志（R191 名实双出口）/ the rejection flag
IF bBad THEN // 非有限命中 / a non finite hit
    bInPosBand := FALSE; // 定位带判据安全假 / the safe false
    RETURN; // 早退（输出保持安全零）/ return early
END_IF

// 段 2｜防摆补偿叠加（相位对消，增益负值回拉语义，边界四）/ segment 2, the anti sway compensation
IF bAntiSwayEn THEN // 防摆使能 / the anti sway enabled
    fCorr := (fK1 * fAngDeg) + (fK2 * fAngVelDegS); // 相位对消补偿量 / the phase cancellation compensation
END_IF
_fV := fVcmd + fCorr; // 叠加 / the superposition

// 段 3｜输出钳位（±fVmax 单点回夹，边界二）/ segment 3, the outlet clamp
IF _fV > fVmax THEN // 上越界 / above the ceiling
    _fV := fVmax; // 夹到上界 / clamp to the ceiling
    bClamped := TRUE; // 信息级 / informational
ELSIF _fV < -fVmax THEN // 下越界 / below the floor
    _fV := -fVmax; // 夹到下界 / clamp to the floor
    bClamped := TRUE; // 信息级 / informational
END_IF

// 段 4｜定位带判据与统一出口（双模切换，边界三）/ segment 4, the positioning band and the outlet
bInPosBand := (ABS(fAngDeg) < fPosAngTol) AND (ABS(fAngVelDegS) < fPosVelTol); // 双容差判据 / the dual tolerance verdict
IF bEnable THEN // 输出使能 / the outlet enabled
    fVout := _fV; // 补偿速度直通 / the compensated pass through
    bValid := TRUE; // 可用 / usable
ELSE // 失能：安全侧零速显式降级（R191 降级显式声明）/ disabled, the explicit safe zero downgrade
    fVout := 0.0; // 零速 / the zero velocity
    bValid := FALSE; // 可用降假 / drop the valid
END_IF
END_FUNCTION_BLOCK
