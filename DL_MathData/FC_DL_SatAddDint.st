(*
  FC_DL_SatAddDint —— DINT 加法饱和，上下界检测
  分类：DL_MathData | 复杂度：2 | 轮次：R86
  开源溯源：道莅原创（clean-room 自研，纯 IEC 61131-3 通用算法），无外部代码引用
  许可证：MIT
  职责：有符号双整数加法，越界时钳到 DINT 上下界并置 xSat；用「带符号双侧直比」判溢出，
        禁用 ABS 单侧比较（ABS(DINT_MIN) 自身会溢出）。
  契约：diA / diB 加数；diOut 饱和和；xSat 报告饱和（信息级）。DINT 上下界在本文件内定义，不跨文件引用。
  边界：① 同号才可能溢出，异号必不溢出；② 上界判据 diA > MAX - diB（diB > 0），下界判 diA < MIN - diB（diB < 0）；
        ③ 零全局、零物理地址、零库件依赖。
*)
FUNCTION FC_DL_SatAddDint : DINT
VAR_INPUT
    diA : DINT := 0;                  // 加数 A [—] / The addend A
    diB : DINT := 0;                  // 加数 B [—] / The addend B
END_VAR
VAR_OUTPUT
    xSat : BOOL;                      // 饱和发生标志（信息级） [—] / The saturation flag, informational
END_VAR
VAR CONSTANT
    DL_DINT_MAX : DINT := 2147483647; // DINT 上界（本件私有） [-] / The DINT maximum, private to this file
    DL_DINT_MIN : DINT := -2147483647 - 1; // DINT 下界（本件私有，减法写法避免字面量越域） [-] / The DINT minimum
END_VAR

xSat := FALSE;                                        // 饱和标志预置假 / preset the saturation flag false
IF (diB > 0) AND (diA > (DL_DINT_MAX - diB)) THEN     // 正加数上溢判据（双侧直比） / the positive overflow test
    FC_DL_SatAddDint := DL_DINT_MAX;                  // 钳到上界 / clamp to the maximum
    xSat := TRUE;                                     // 置饱和标志 / raise the saturation flag
ELSIF (diB < 0) AND (diA < (DL_DINT_MIN - diB)) THEN  // 负加数下溢判据（双侧直比） / the negative overflow test
    FC_DL_SatAddDint := DL_DINT_MIN;                  // 钳到下界 / clamp to the minimum
    xSat := TRUE;                                     // 置饱和标志 / raise the saturation flag
ELSE
    FC_DL_SatAddDint := diA + diB;                    // 界内直接相加 / the safe addition
END_IF
END_FUNCTION
