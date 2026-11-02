# 协议核对记录

核对日期：2026-11-03（Asia/Shanghai）。本文区分“源码是什么”与“用户硬件实际运行什么”。后者必须实测，公开仓库的 `.hex` 不能直接证明与源码或用户实刷版本一致。

## TXi 固件证据

项目：[miotislucifugis/Telex_teensy4](https://github.com/miotislucifugis/Telex_teensy4)。本次固定到提交 **39e51af16802b7e92c99c5f96d08d964231961f5**。仅阅读，不修改、不刷写，也不将上游代码混入本仓库。

### 地址

[`telex.h` L98–106](https://github.com/miotislucifugis/Telex_teensy4/blob/39e51af16802b7e92c99c5f96d08d964231961f5/TELEXi_T4/telex.h#L98-L106) 定义起始地址 `TI = 0x68`，地址范围 `0x68`–`0x6F`。

[`setup()` L75–84、L115–119](https://github.com/miotislucifugis/Telex_teensy4/blob/39e51af16802b7e92c99c5f96d08d964231961f5/TELEXi_T4/TELEXi_T4.ino#L75-L119) 把引脚 `{2,1,0}` 读成三个配置位，加到 `0x68` 后传给 `Wire.begin(configID)`。传给 NT Getter 的是 **7 位地址**，不是左移后的 `0xD0`，也不是 NT 自身的 Follower 地址。实物跳线状态仍待确认。

### Getter 请求：单字节选择器

[`receiveEvent()` L166–195](https://github.com/miotislucifugis/Telex_teensy4/blob/39e51af16802b7e92c99c5f96d08d964231961f5/TELEXi_T4/TELEXi_T4.ino#L166-L195)：收到长度为 **1** 的数据时，选择 activeInput 与 activeMode；长度大于 1 则进入命令处理。因此不能构造“TI_PARAM + 通道号”这种两字节读请求。

[`TxHelper::DecodeIO()` L45–55](https://github.com/miotislucifugis/Telex_teensy4/blob/39e51af16802b7e92c99c5f96d08d964231961f5/TELEXi_T4/TxHelper.cpp#L45-L55)：`port = selector % 8`，`mode = selector >> 3`。[`setup()` 的 reader 初始化](https://github.com/miotislucifugis/Telex_teensy4/blob/39e51af16802b7e92c99c5f96d08d964231961f5/TELEXi_T4/TELEXi_T4.ino#L97-L102) 与 AnalogReader 的 reverse 逻辑说明前四个是旋钮，后四个是 CV。

| 来源 | raw 选择字节 | 量化电压模式 | 音符编号模式 |
|---|---|---|---|
| K1 | `0x00` | `0x08` | `0x10` |
| K2 | `0x01` | `0x09` | `0x11` |
| K3 | `0x02` | `0x0A` | `0x12` |
| K4 | `0x03` | `0x0B` | `0x13` |
| CV1 | `0x04` | `0x0C` | `0x14` |
| CV2 | `0x05` | `0x0D` | `0x15` |
| CV3 | `0x06` | `0x0E` | `0x16` |
| CV4 | `0x07` | `0x0F` | `0x17` |

本版只发送 raw 的 `0x00`–`0x07`。`telex.h` 里的 `TI_PARAM = 0x10` 等是另一层命令常量，不能据名字直接当作单字节 Knob 读取：单独发 `0x10` 按这里的逻辑会变成 K1 的音符模式。

### 响应与解码

[`requestEvent()` L202–230](https://github.com/miotislucifugis/Telex_teensy4/blob/39e51af16802b7e92c99c5f96d08d964231961f5/TELEXi_T4/TELEXi_T4.ino#L202-L230) 读取对应的 int，转换成 `uint16_t` 保存位模式，再先发送高八位、后发送低八位。接收后按 **16 位二进制补码有符号大端整数**还原：

```lua
local n = data[1] * 256 + data[2]
if n >= 32768 then n = n - 65536 end
```

例：`00 00 → 0`，`3F FF → 16383`，`C0 00 → -16384`，`FF FF → -1`。最后一项是合法编码，不可凭它单独判断 NACK 或通信成功。

### 数值范围的重要疑点

[`TELEXi_T4.ino` L83–84](https://github.com/miotislucifugis/Telex_teensy4/blob/39e51af16802b7e92c99c5f96d08d964231961f5/TELEXi_T4/TELEXi_T4.ino#L83-L84) 设置 12 位 ADC，而 [`AnalogReader.cpp` L13、L36、L46–71](https://github.com/miotislucifugis/Telex_teensy4/blob/39e51af16802b7e92c99c5f96d08d964231961f5/TELEXi_T4/AnalogReader.cpp#L13-L71) 仍有 8192 滤波分辨率、MAXPOT 16379，以及旋钮左移 1 位/CV 左移 2 位的处理。

**推论，不是硬件结论：** 若 ADC 实际为 0–4095、滤波输出相近且无校准，旋钮可能只到约 8192，CV 路径可能只覆盖约 3–16383 的正值，而非旧范围的完整双极性数值。EEPROM 校准、实际板上模拟调理与刷入的 hex 都可能改变结果。不能宣称所有设备必然如此，也不应先改固件来“修复”。用 probe 测端点、0V 与极性后再决定。

“raw”在本项目中指未选择量化模式的 `inputValue`，它已经过固件滤波与可能的 EEPROM 校准，不是裸 ADC，也不是能直接解释为伏特的数值。

### 上拉代码不构成实物证明

`enablePullups = false` 仍存在，但使用该变量的旧 `i2c_t3` 初始化行被注释，实际调用是 `Wire.begin(configID)`。不能根据这个变量就声称 TXi 无上拉或上拉已经关闭。库的电气配置与板上电阻必须另外检查。

## NT 官方 Lua API

[NT Lua scripting 1.18，第 28 页](https://www.expert-sleepers.co.uk/downloads/manuals/disting_NT_lua_scripting_1.18.pdf)：`sendI2CGetter(address, responseBytes, ...)` 接受地址、期望响应字节数及请求负载；负载也可用 table。返回**字节数组**，不是解码后的整数或 callback。

本项目 Knob 1 的最小调用：

```lua
local data = sendI2CGetter(0x68, 2, 0x00)
```

Lua 在调用处拿到响应数组，所以程序按同步调用处理。官方没有在这里说明底层 NACK/超时、阻塞上限、总线时钟、STOP 与 repeated-START 的精确组合。不得把错误假设成必然返回 nil 或抛出异常；也不能声称是非阻塞调用。后续用逻辑分析仪确认“写一个选择字节 → 读两个响应字节”在该 Teensy4 库上的实际时序。

官方文档描述的 `step` 使用秒为单位的 dt；本项目据此累计时间。目标 50 Hz 不是对实际硬件调度精度的保证。

## 为什么先走原生 CV Mapping

[NT 用户手册 1.18，第 44–48 页](https://www.expert-sleepers.co.uk/downloads/manuals/disting_NT_user_manual_1.18.pdf) 允许内部总线作为 CV Mapping 来源，Mapping 随预设保存；CV 采用基础值加偏移。I²C Mapping 则处理接收到的控制器消息。官方 Lua 文档没有提供“把 Getter 响应注入本机 I²C Controller Mapping”的接口。

因此本版桥接输出内部 0–10V 信号，使用 NT 的 CV Mapping 菜单。若以后需要绝对参数控制，可研究 `setParameterNormalized(algorithmIndex, parameterIndex, value, false)`；最后一个 false 可避免抢占显示。它仍不等于本机原生 I²C Mapping，不在本版脚本中调用。

## Helper 交叉检查

2026-11-03 使用用户连接的 **Disting NT Helper** 搜索 `sendI2CGetter`、TXi 与 Lua 输出实例。检索返回了官方仓库中的 `sendI2CCommand` 与 init/output 例子，但未返回真正匹配 TXi Getter 的实现。没有将相关性搜索结果当作支持 Getter 细节的证据，也没有复制社区实现。
