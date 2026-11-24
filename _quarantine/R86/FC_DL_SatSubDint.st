(*
  FC_DL_SatSubDint —— DINT 减法饱和
  分类：DL_MathData | 复杂度：2 | 轮次：R86
  开源溯源：道莅原创（clean-room 自研，纯 IEC 61131-3 通用算法），无外部代码引用
  许可证：MIT
  职责：有符号双整数减法，越界时钳到 DINT 上下界并置 xSat；用带符号双侧直比判溢出，禁用 ABS 单侧比较。
  契约：diA 被减数、diB 减数；diOut 饱和差；xSat 报告饱和（信息级）。DINT 上下界在本文件内定义。
  边界：① 异号必不溢出，同号才可能溢出；② 上界判据 diA > MAX + diB（diB < 0），下界判 diA < MIN + diB（diB > 0）；
        ③ 零全局、零物理地址、零库件依赖。
*)
FUNCTION FC_DL_SatSubDint : DINT
VAR_INPUT
    diA : DINT := 0;                  // 被减数 A [—] / The minuend A
    diB : DINT := 0;                  // 减数 B [—] / The subtrahend B
END_VAR
VAR_OUTPUT
    xSat : BOOL;                      // 饱和发生标志（信息级） [—] / The saturation flag, informational
END_VAR
VAR CONSTANT
    DL_DINT_MAX : DINT := 2147483647; // DINT 上界（本件私有） [-] / The DINT maximum, private to this file
    DL_DINT_MIN : DINT := -2147483647 - 1; // DINT 下界（本件私有） [-] / The DINT minimum, private to this file
END_VAR

xSat := FALSE;                                        // 饱和标志预置假 / preset the saturation flag false
IF (diB < 0) AND (diA > (DL_DINT_MAX + diB)) THEN     // 减去负数上溢判据（双侧直比） / the positive overflow test
    FC_DL_SatSubDint := DL_DINT_MAX;                  // 钳到上界 / clamp to the maximum
    xSat := TRUE;                                     // 置饱和标志 / raise the saturation flag
ELSIF (diB > 0) AND (diA < (DL_DINT_MIN + diB)) THEN  // 减去正数下溢判据（双侧直比） / the negative overflow test
    FC_DL_SatSubDint := DL_DINT_MIN;                  // 钳到下界 / clamp to the minimum
    xSat := TRUE;                                     // 置饱和标志 / raise the saturation flag
ELSE
    FC_DL_SatSubDint := diA - diB;                    // 界内直接相减 / the safe subtraction
END_IF
END_FUNCTION
