# Disting NT × Telex TXi

Lua 实验项目：由 **disting NT 作为唯一 I²C Leader**，读取 Teensy 4.0 TXi 的四旋钮与四路 CV，再控制 NT 参数。适用起点：NT 固件 **1.18+**、`miotislucifugis/Telex_teensy4` 移植固件。

**当前状态：协议经源码核对、桌面 Lua 模拟测试通过；尚未在真实 NT/TXi 上验证。** 本项目独立于 `nt-disperser`，不修改其代码、Issues、PR、Actions 或自动化，也不刷写 TXi。

## 先理解信号怎么走

第一步只做 `NT 发问 → TXi 回答 → NT 屏幕显示原始数值`。Leader 是主动发问的一方，Follower 是回答的一方；这与音频信号方向没有关系。

第二步做 `TXi → Lua → 八路 NT 内部 CV 总线 → 原生 CV Mapping → 参数`。这些“CV”可以完全留在 NT 内部，不需要再用八根跳线接回面板。

这里实现的是 **原生 CV Mapping**。TXi 不会因此自动出现在原生 **I²C Mapping / Learn** 中。后者接收控制器消息；现有 TXi 固件是等待读取的 Follower，不能把这两件事混为一谈。直接 `setParameterNormalized()` 控制参数是另一种可行设计，但本版选择菜单中可配置、随预设保存的 CV Mapping 路径。[官方用户手册，Mapping 章节](https://www.expert-sleepers.co.uk/downloads/manuals/disting_NT_user_manual_1.18.pdf)

## 文件与安装

| 仓库文件 | 复制到 NT MicroSD |
|---|---|
| `lua/lib/nt_telex.lua` | `/programs/lua/lib/nt_telex.lua` |
| `lua/txi_probe.lua` | `/programs/lua/txi_probe.lua` |
| `lua/txi_bridge.lua` | `/programs/lua/txi_bridge.lua` |

`nt_telex.lua` 是共用的读取工具，另外两个才是在 **Lua Script** 算法中选择的程序。文件名不要改；两个程序用 `require("nt_telex")` 找工具。更新共用工具后重启 NT，以免 Lua 的加载缓存仍使用旧版本。

## 接线前先检查电气条件

1. 关掉模块电源后接线。只连接 **SDA ↔ SDA、SCL ↔ SCL、GND ↔ GND**。NT 使用背面 **J8**，以电路板标记为准，不凭插头朝向猜顺序。不要互接两台设备的 3.3V/5V 电源输出。
2. Teensy 4.0 的数字引脚只接受 **0–3.3V，不能承受 5V**。若 TXi 总线上拉到 5V，必须先处理上拉电压或电平转换。CV 只接 TXi 面板输入，不直接接 Teensy 或 SDA/SCL。[PJRC 官方说明](https://www.pjrc.com/store/teensy40.html)
3. NT 有 **SW8 I2C PULL UP** 开关，靠 PCB 顶部的位置是启用。短线、只有两台设备的起步连接，使用一组已确认接到 3.3V 的合适上拉；先检查 TXi/转接板/总线板是否已经有上拉，再决定 SW8。多组并联会降低等效电阻，不能盲目全开。[官方用户手册，第 12、14、15 页](https://www.expert-sleepers.co.uk/downloads/manuals/disting_NT_user_manual_1.18.pdf)
4. **软件不能检查你实物上的电阻与焊接。** 若上拉来源不明，先断开两机间 SDA/SCL，分别检查电路，并测量供电后的空闲 SDA/SCL 电压，确认不超过 3.3V 后再断电互接。若有示波器，检查上升沿、低电平及总线速率。这里未核实 NT 上拉阻值、TXi 实装阻值及电源；不把它们当作已知。
5. 起步时只有 NT 和 TXi；断开 Teletype、crow 等其他可能发起通信的设备。NT 上也只加载本项目的一个轮询脚本，暂不运行其他 I²C 发送脚本/算法。NT 的“Address (as follower)”是 NT 被别人访问时的地址，不是 TXi 地址，也不是 Leader 模式开关。

## 第一步：50 Hz，先看第一个旋钮

1. 用一个新测试预设加入 **Lua Script**，选择 `txi_probe.lua`。不要同时加载 bridge。
2. 保持 `Source (1-8) = 1`，即 Knob 1；`TXi address = 104` 对应十六进制 `0x68`。这是固件的起始地址，实物跳线可能设成 104–111 中的其他地址。按实际配置修改，不做全总线盲扫。
3. `Poll = 1` 开始读取，`Poll = 0` 暂停。程序不输出 CV，不修改其他算法参数。
4. 来回转 Knob 1，观察 `raw` 是否跟随。`min/max` 记录这次运行看到的端点；`valid` 只表示返回数据格式符合要求，**不代表电气或 ACK 已确认**。真实测试必须看到旋钮与数值的因果对应。
5. 先运行一分钟，记录最小值、最大值、错误数、卡顿与 CPU。地址或 Source 改变时计数与端点会重新开始。
6. 将 Source 改为 2、3、4 检查其他旋钮，5、6、7、8 检查 CV1–4。对 CV 使用已知的安全测试电压，先记极性与端点，暂不推算伏特。每次切换都会重置端点。

**为什么不直接除以 16383？** 移植源码使用 12 位 ADC，但后续仍留有 13 位滤波设置与旧缩放常量，EEPROM 校准也会影响读数。因此本版保留原始值，并允许在 NT 中填实测端点；没有擅自改固件。[详见协议核对](docs/PROTOCOL.md)

## 第二步：四旋钮 + 四 CV

单通道测试通过后，移除 probe，再加载 `txi_bridge.lua`。默认每通道 50 Hz，共 **400 次 Getter/秒**，八通道错开发送，每次 `step` 最多发送一次。它们并非同时采样；不能用于音频速率调制或精确同步采样。`Hz per channel` 可降到 10，便于对比负载。

| 参数 | 含义 |
|---|---|
| Poll | 1 读取；0 暂停并保持最后输出 |
| TXi address | 十进制 104–111，即 `0x68`–`0x6F` |
| Hz per channel | 每个通道的目标读取频率；默认 50 |
| Smoothing ms | 一阶平滑时间常数；默认 30 ms；0 为关闭 |
| Outputs armed | 默认 0，八路输出均为 0V；设 1 才启用输出 |
| K1…CV4 raw low/high | 将实测端点映射为 0–10V，超出范围夹住；上下端点相同则冻结该路 |

默认端点只是旧协议范围的临时值：旋钮 0…16383，CV -16384…16383。**必须用 probe 实测值替换后再启用输出。** 如 CV 极性反向，可以让 low 大于 high。软件端点配置不会写入 TXi 校准或 EEPROM。

输出顺序为 K1、K2、K3、K4、CV1、CV2、CV3、CV4。把八路输出各设到一个**空闲的内部 Aux 总线**，输出模式选替换而非累加，并记录使用的总线号。不要占用预设已有信号，也不要把八路设到同一总线。本版起步只做内部控制，不路由到面板物理输出。

## 第三步：在 NT 菜单里映射一个参数

先只试 K1，选一个容易观察的非关键目标参数，保持扩音音量较低。

1. 将 bridge 放在目标算法之前。把 K1 输出路由到一条空闲 Aux 总线，例如你确认空闲的 Aux 1。
2. 保持 `Outputs armed = 0`，将目标参数基础值设为期望的起点。
3. 进入目标算法的 **Mappings → CV Mappings**，选目标 Parameter。Source 可选 bridge 的算法输出，Bus 选择上一步路由的总线；设为普通连续 CV（不是 Gate）。
4. 设 `Volts = 10`，`Delta = 希望增加的参数量`。例如参数单位为 0–100，基础值 0、Delta 100，则 0–10V 对应 0–100。
5. `Outputs armed = 1`，转 K1，检查端点、中点和平滑。通过后再配置剩余七路。
6. **Save preset**，然后重载与重启各测一次，确认参数、端点、路由及 Mapping 保存正确。

CV Mapping 是在基础参数上**加偏移**，不是绝对覆盖：`结果 = 基础值 + CV × Delta / Volts`。选择合适基础值与 Delta；不要再用其他控制器同时修改同一个参数，直到基础路径确认正常。[官方 CV Mapping 说明，第 44–46 页](https://www.expert-sleepers.co.uk/downloads/manuals/disting_NT_user_manual_1.18.pdf)

## 失败时的行为

返回类型/长度/字节异常或 Lua 错误会计入 errors，连续三次失败后等待一秒再试。`pcall` 只能捕捉 Lua 错误，不能中断固件内部阻塞。官方文档没有保证 NACK/超时如何返回；固定的两字节假数据也可能被视为格式有效，所以必须做硬件测试。

bridge 超过 250 ms 没有该通道的新数据，会冻结该路最后输出；Poll 暂停也保持输出。**这可能让被控参数停留在较高值。** 显式将 Outputs armed 设为 0 或更换 TXi 地址，会把输出置零；通过 CV Mapping 时目标返回基础值。重新加载也从零开始。切换这些状态可能造成参数跳变，先在测试预设中操作。

## 核实范围与开发

- 源码已核实：地址范围、单字节选择器、通道顺序、两字节有符号大端响应。
- 官方文档已核实：`sendI2CGetter` 的参数及返回数组；没有公开承诺的失败/超时/波形时序说明。
- 桌面已测试：Lua 5.4.6 下的解码、50/400 次每秒调度、异常退避、地址切换、输出启用与保持行为。
- 待实测：实刷固件版本、实物地址、接线与上拉、电压与校准、Getter 时序/ACK/超时、实际更新率、NT 负载/音频稳定性、Mapping 和预设重载。

详见 [协议证据](docs/PROTOCOL.md) 和 [硬件测试记录表](docs/HARDWARE_TEST.md)。Disting NT Helper 检索用于交叉参考；它未返回匹配本 TXi Getter 的实例，所以没有据此猜测协议。

开发者用 Lua 5.4 在仓库根目录运行：

```sh
lua tests/test.lua
```

后续以真实 Knob 1 测试结果为下一里程碑，再决定是否增加直接参数设置、软接管或原生 I²C Mapping 的替代路径。当前不创建后台自动化，不添加跨仓库依赖。
