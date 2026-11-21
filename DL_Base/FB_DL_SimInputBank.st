(*
  ==================================================================
  组件名 Component  : FB_DL_SimInputBank
  分类   Category   : DL_Base
  复杂度 Complexity  : cx5
  版本   Version    : 1.0.0
  功能   Purpose    : 调试仿真输入注入组。8 通道手动假值旁路真实输入：通道
                      仿真使能 + 组武装锁存（沿置沿清，防误碰）双闸满足才
                      旁路；退出（通道撤使能 / 组撤武装）自动回真实值；
                      组级与通道级仿真指示出口。与 OutputForcingBank 输出侧
                      强制组成对（R216 互引）。
  来源   Source     : self（库内对称件，R216 互引）
  溯源   Origin     : IEC 61131-3 标准语义的道莅防御性实现；调试输入旁路与
                      武装锁存为公开调试工程语义，clean-room 自研实现，未复
                      制任何厂商私有库源码。
  平台   Platform   : 纯 IEC 61131-3（Standard.library: R_TRIG，无私有库）
  分工声明 Split     : 与 DL_Base 存量 FB_DL_OutputForcingBank 分工——本件为
                      输入侧仿真注入组，OutputForcingBank 为输出侧强制组；
                      本件不做输出强制，也不做信号源切换诊断。
  作者   Author     : 道莅代码库 · PLC 编程专家（R58）
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 双闸条件：组武装 _bArmed（沿锁存）AND 组使能
                         bBankEn AND 通道使能 abSimEn[i]，三者同真才旁路；
                      二 武装锁存解除路径 = bSimDisarmReq 上升沿（唯一沿，
                         R188 头注释声明）；置位路径 = bSimArmReq 上升沿；
                      三 退出自动回真实值：旁路条件任一失效，输出组合逻辑
                         即刻跟随真实输入（无保持延迟）；
                      四 数组按固定界 0..7 遍历（无动态下标，结构性越界
                         防御）；输出 abOut 与输入数组同长度同序；
                      五 无全局变量、无外部变量声明、无物理地址寻址。
  修订记录 Revision  :
    2026-11-21  v1.0.0  R58 首版（批 1 · 序号 2）
  ==================================================================
*)

FUNCTION_BLOCK FB_DL_SimInputBank
VAR_INPUT
    abRealIn     : ARRAY[0..7] OF BOOL; // 真实输入数组（正常过程信号）[-] / the real input array, the normal process signals
    abSimVal     : ARRAY[0..7] OF BOOL; // 仿真假值数组（手动注入）[-] / the simulated value array, manually injected
    abSimEn      : ARRAY[0..7] OF BOOL; // 通道仿真使能数组 [-] / the per channel simulation enable array
    bBankEn      : BOOL := TRUE;  // 组使能（总闸）[-] / the bank enable, the master gate
    bSimArmReq   : BOOL := FALSE; // 武装请求，上升沿置武装锁存 [-] / the arm request, the rising edge raises the arm latch
    bSimDisarmReq: BOOL := FALSE; // 撤武装请求，上升沿清武装锁存 [-] / the disarm request, the rising edge clears the arm latch
END_VAR
VAR_OUTPUT
    abOut      : ARRAY[0..7] OF BOOL; // 混合输出数组（旁路时为假值，否则真实值）[-] / the mixed output array, the fake value when bypassed
    abChnSim   : ARRAY[0..7] OF BOOL; // 通道仿真生效指示数组 [-] / the per channel simulation active array
    bSimActive : BOOL := FALSE; // 组级仿真指示（任一通道旁路中）[-] / the bank simulation indicator, any channel bypassed
    bArmed     : BOOL := FALSE; // 武装锁存指示 [-] / the arm latch indicator
END_VAR
VAR
    rtArm   : R_TRIG; // 武装请求沿检测，段 0 无条件刷新 / the arm request edge, refreshed unconditionally
    rtDisarm: R_TRIG; // 撤武装请求沿检测，段 0 无条件刷新 / the disarm request edge, refreshed unconditionally
    _nI     : DINT;   // 通道遍历索引 [槽] / the channel loop index [slot]
    _bAny   : BOOL;   // 任一通道旁路中工作量 [-] / the any channel bypassed work flag
END_VAR

// 段 0｜沿检测无条件周期刷新（禁入分支）/ segment 0, the unconditional refresh
rtArm(CLK := bSimArmReq); // 武装沿 / the arm edge
rtDisarm(CLK := bSimDisarmReq); // 撤武装沿 / the disarm edge

// 段 1｜武装锁存沿置沿清（边界二，解除路径 = 撤武装上升沿，R188 声明）/ segment 1, the arm latch edge set and edge clear
IF rtArm.Q THEN // 武装上升沿 / the arm rising edge
    bArmed := TRUE; // 置武装锁存 / raise the arm latch
END_IF
IF rtDisarm.Q THEN // 撤武装上升沿（唯一解除路径）/ the disarm rising edge, the only release path
    bArmed := FALSE; // 清武装锁存 / clear the arm latch
END_IF

// 段 2｜通道混合输出（固定界遍历，双闸条件，边界一二三）/ segment 2, the channel mixing, the dual gate
_bAny := FALSE; // 组级指示工作量预置假 / preset the any flag false
FOR _nI := 0 TO 7 DO // 固定界循环，无死循环风险 / the fixed bound loop
    abChnSim[_nI] := bArmed AND bBankEn AND abSimEn[_nI]; // 通道旁路生效判定 / the per channel bypass verdict
    IF abChnSim[_nI] THEN // 旁路生效 / bypassed
        abOut[_nI] := abSimVal[_nI]; // 输出假值 / output the fake value
        _bAny := TRUE; // 组级指示置位 / raise the any flag
    ELSE // 未旁路（边界三：自动回真实值）/ not bypassed, back to the real value
        abOut[_nI] := abRealIn[_nI]; // 输出真实值 / output the real value
    END_IF
END_FOR
bSimActive := _bAny; // 组级仿真指示出口 / the bank simulation indicator
END_FUNCTION_BLOCK
