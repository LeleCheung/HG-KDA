本文面向拿到预编译 XSAI RTL `emu`、但不需要构建完整 `xsai-env` 的用户。主要用途是运行 workload、采集 RTL 性能计数器、生成 ChiselDB，以及使用 PerfCCT 做指令和 uop 级性能分析。

## 1. 环境
当前提供 emu 二进制相关信息如下：

| 项目 | 值 |
| --- | --- |
| 架构 | x86-64 Linux ELF，可执行文件为 PIE，动态链接，未 strip |
| 大小 | 406,120,792 bytes |
| `emu` SHA-256 | `658f18cb7aadfc5d48ebe9dd0eeb33c63c64ef0189f382fa87a749c9eb1bfdd1` |
| NEMU ref SHA-256 | `177a9c0fd23f6b5d203b7d3576bf2eabce6d81baeb9979ebe4888d93e1d93011` |
| `emu` 内置编译时间 | `Jul 2 2026, 11:37:23` |
| 当前 XSAI checkout | `6690985ce47b8e003a1a533f0ec05f94050dc76f` |
| RTL 配置 | `DefaultMatrixConfig`，单核 |
| 构建特性 | Verilator、8 threads、FST、ChiselDB、DRAMSim3、difftest |


### 主机要求
建议使用 Ubuntu 22.04/24.04 或兼容的 x86-64 Linux。当前 `emu` 至少引用 `GLIBC_2.33`，随包提供的 NEMU reference `.so` 还引用 `GLIBCXX_3.4.29`；Ubuntu 20.04 的 glibc 2.31 不满足要求。

Ubuntu/Debian 运行时库：

```bash
sudo apt-get install libsqlite3-0 zlib1g libzstd1 libatomic1 libstdc++6 python3
```

`sqlite3` 命令行工具和 RISC-V `objdump` 只在手工查询 DB、反汇编指令时需要：

```bash
sudo apt-get install sqlite3 binutils-riscv64-linux-gnu
```

可以用以下命令检查动态库是否齐全；输出中不应出现 `not found`：

```bash
ldd bin/emu
ldd lib/riscv64-nemu-interpreter-so
```

### 目录组织
可直接使用：[xsai-emu.zip](https://www.yuque.com/attachments/yuque/0/2026/zip/50506702/1784260259818-c19725e8-7e90-46c0-a75b-7a9e8007afb7.zip)

```latex
xsai-emu/
├── bin/
│   └── emu
├── config/
│   └── XiangShan.ini
├── lib/
│   └── riscv64-nemu-interpreter-so
├── tools/
│   └── perfcct.py
├── licenses/
├── build/                 # 用户运行时创建，ChiselDB 默认写在这里
├── results/               # 用户运行时创建，日志、FST、DRAMSim3 输出
├── README.md
└── SHA256SUMS
```

对应关系：

| 文件 | 来源 |
| --- | --- |
| `bin/emu` | `XSAI/build/emu` |
| `config/XiangShan.ini` | `DRAMsim3/configs/XiangShan.ini`  |
| `lib/riscv64-nemu-interpreter-so` | `XSAI/ready-to-run/riscv64-nemu-interpreter-so` |
| `tools/perfcct.py` | `XSAI/scripts/perfcct.py` |


复制 `emu` 和 DRAMSim3 配置时需要解引用符号链接，例如使用 `cp -L`。生成交付包后运行：

```bash
sha256sum bin/emu lib/riscv64-nemu-interpreter-so config/XiangShan.ini tools/perfcct.py > SHA256SUMS
sha256sum -c SHA256SUMS
```

## 2. 编译 XSAI bare-metal 程序
`emu` 不能直接运行使用主机 `gcc` 编译的 x86-64 程序，也不能把普通 Linux 动态 ELF 当作启动镜像。传给 `emu -i` 的程序需要是面向 `riscv64-xs` 平台构建的 bare-metal image。

LLVM 负责将 C/C++ 编译成 RISC-V 对象，并完成链接、反汇编和 `.bin` 转换；AM 提供 XSAI 所需的启动代码、链接地址、设备访问、klib 和退出协议。

+ XSAI LLVM：`clang`、`ld.lld`、`llvm-ar`、`llvm-objdump`、`llvm-objcopy`；
+ `nexus-am`：`riscv64-xs` 平台运行时、头文件和 linker script。

### 获取 LLVM
请从下面的 release 自行获取：

+ [OurCompArchGroup LLVM release 20260528](https://github.com/OurCompArchGroup/llvm-release/releases/tag/20260528)

可按 release 页面说明自行 clone/download 并解压。下面统一假设解压目录中存在 `bin/clang`：

```bash
export LLVM_HOME=/absolute/path/to/llvm-release
```

### 获取 AM
使用与当前 `emu` 配套的 `nexus-am` 版本：

```bash
git clone https://github.com/OurCompArchGroup/nexus-am.git
git -C nexus-am checkout 925e69ddc3ee6e986cf52954d50819f555024d33

export AM_HOME="$(realpath nexus-am)"
```

固定 commit 是为了避免 AM 启动代码、ISA flags 或退出协议发生变化后，与本交付包中的 `emu` 不兼容。

### 创建普通 C 程序
建立一个单独的应用目录，例如 `my-xs-app/`：

```latex
my-xs-app/
├── Makefile
└── main.c
```

`main.c` 示例：

```c
#include <klib.h>

int main(void) {
  printf("Hello, XSAI!\n");
  return 0;
}
```

`Makefile` 示例：

```plain
NAME = my-xs-app
SRCS = main.c

override ARCH := riscv64-xs
override TOOLCHAIN := LLVM

include $(AM_HOME)/Makefile.app
```

编译：

```bash
cd my-xs-app
make
```

AM 会自动完成以下步骤：

1. 使用 `$LLVM_HOME/bin/clang` 编译程序；
2. 构建并链接 `am-riscv64-xs.a` 和 `klib-riscv64-xs.a`；
3. 使用 XSAI linker script 将入口链接到 `0x80000000`；
4. 生成 ELF、反汇编和可供 `emu` 加载的 raw binary。

输出文件：

```latex
build/my-xs-app-riscv64-xs.elf  # 保留符号，用于反汇编和地址定位
build/my-xs-app-riscv64-xs.txt  # 反汇编文本
build/my-xs-app-riscv64-xs.bin  # 传给 emu -i
```

检查 ELF 架构和入口地址：

```bash
"$LLVM_HOME/bin/llvm-readelf" -h build/my-xs-app-riscv64-xs.elf \
  | grep -E 'Machine|Entry point'
```

预期应看到 `Machine: RISC-V`，入口位于 `0x80000000`。如果显示 `Advanced Micro Devices X86-64`、`/lib64/ld-linux-x86-64.so.2`，或 load address 从 `0x0` 开始，说明编译方式错误，不能交给 `emu`。

### 编译 AME/Matrix 程序
使用 AME/Matrix 指令时，在应用 `Makefile` 中加入与当前 XSAI 软件栈一致的 ISA 和 LLVM feature：

```plain
NAME = my-ame-app
SRCS = main.c

override ARCH := riscv64-xs
override TOOLCHAIN := LLVM
override OBJDUMP_FLAGS := --mattr=+matrix-xuantie-0.6

MARCH := rv64gcv_zvl128b_zba_zbb_zbc_zbs_zbkb_zbkc_zbkx_zknd_zkne_zknh_zkr_zksed_zksh_zkt_zame
CFLAGS += --target=riscv64-unknown-linux-gnu
CFLAGS += -Xclang -target-feature -Xclang +matrix-xuantie-0.6

include $(AM_HOME)/Makefile.app
```

编译后使用定制 LLVM 检查 Matrix 指令：

```bash
"$LLVM_HOME/bin/llvm-objdump" \
  -d build/my-ame-app-riscv64-xs.elf \
  --mattr=+matrix-xuantie-0.6
```

### bare-metal 限制
+ 可以使用 AM API 和 klib 中提供的 `printf`、字符串、内存等基础功能；
+ 不能依赖 glibc 动态链接、Linux syscall、文件系统、进程、pthread 或 `/lib/ld-linux-*.so.*`；
+ 需要 Linux runtime 的应用应放入 rootfs，并通过 Linux checkpoint 在 `emu` 上运行；
+ `.elf` 用于检查和调试，实际传给本交付包 `emu -i` 的是生成的 `.bin`。

## 3. 在 emu 上运行程序
```bash
cd xsai-emu
export NOOP_HOME="$PWD"
mkdir -p build results/dramsim3
```

`NOOP_HOME` 必须设置，ChiselDB 的默认输出路径是 `$NOOP_HOME/build/<timestamp>.db`。当前二进制还带有构建机上的 DRAMSim3 绝对路径，因此外部运行时必须显式传入 `--dramsim3-ini` 和 `--dramsim3-outdir`。

### 最小运行
```bash
./bin/emu \
  -i /absolute/path/to/payload \
  --no-diff \
  --dramsim3-ini "$PWD/config/XiangShan.ini" \
  --dramsim3-outdir "$PWD/results/dramsim3"
```

### 启用 difftest
```bash
./bin/emu \
  -i /absolute/path/to/payload \
  --diff="$PWD/lib/riscv64-nemu-interpreter-so" \
  --dramsim3-ini "$PWD/config/XiangShan.ini" \
  --dramsim3-outdir "$PWD/results/dramsim3"
```

`--no-diff` 可以降低 host 运行时间，但不能替代正确性验证。

### 性能计数器窗口
常用参数：

| 参数 | 含义 |
| --- | --- |
| `-W N` | 执行到累计第 `N` 条 guest instruction 时 dump 并清零性能计数器 |
| `-I N` | 最多执行累计 `N` 条 guest instruction 后正常结束 |
| `-C N` | 最多执行 `N` 个 guest cycle 后正常结束 |
| `-D N` | 每 `N` 个 guest cycle 周期性 dump/清零性能计数器 |
| `--force-dump-result` | 结束时强制导出性能计数器结果 |


例如跳过前 20M 条指令的计数、在累计 40M 条指令时结束：

```bash
./bin/emu \
  -i /absolute/path/to/payload \
  --no-diff \
  -W 20000000 \
  -I 40000000 \
  --force-dump-result \
  --dramsim3-ini "$PWD/config/XiangShan.ini" \
  --dramsim3-outdir "$PWD/results/dramsim3" \
  2>results/emu.err.log | tee results/emu.log
```

注意：`-I` 是从仿真开始累计的上限，不是 warmup 之后再执行的指令数。`-W` 只控制 RTL performance counter 的清零时刻，不会让 ChiselDB 从该点才开始记录。

## 4. ChiselDB 采集
只采集 PerfCCT lifetime 表的推荐命令：

```bash
./bin/emu \
  -i /absolute/path/to/payload \
  --no-diff \
  -I 1000000 \
  --dump-db \
  --dump-select-db lifetime \
  --dramsim3-ini "$PWD/config/XiangShan.ini" \
  --dramsim3-outdir "$PWD/results/dramsim3" \
  2>results/emu.err.log | tee results/emu.log
```

正常结束时会看到类似输出：

```latex
Open database successfully
saving memdb to .../build/2026-07-16-12-00-00.db ...
```

`lifetime` 必须小写。只使用 `--dump-db` 而不限制表会启用更多 ChiselDB 表，运行内存和最终 DB 都可能显著增大。PerfCCT 数据先保存在内存 SQLite DB 中，仿真结束时才写入磁盘，因此应注意：

+ 用 `-I` 或 `-C` 让仿真正常结束；
+ 避免 `kill -9`、机器掉电或磁盘写满；
+ 0 字节 `.db` 不可用于分析；
+ 长 workload 应先用较小窗口验证，再逐步增大，注意 host 内存消耗。

检查 DB：

```bash
DB=$(find build -maxdepth 1 -type f -name '*.db' -size +0c -printf '%T@ %p\n' \
  | sort -nr | head -1 | cut -d' ' -f2-)
sqlite3 "$DB" '.tables'
sqlite3 "$DB" 'select count(*) from LifeTimeCommitTrace;'
```

PerfCCT 主要使用以下两个表：

| 表 | 内容 |
| --- | --- |
| `LifeTimeCommitTrace` | 每个动态指令/uop 的流水级时间戳、指令编码和 PC |
| `LoadLifeTimeCommitTrace` | load 的虚拟/物理地址和 replay 信息，通过 `ID` 关联主表 |


### 波形与 ChiselDB
需要波形时显式指定 FST 输出路径：

```bash
./bin/emu \
  -i /absolute/path/to/payload \
  --no-diff \
  --dump-wave \
  --wave-path "$PWD/results/run.fst" \
  -b 50000 \
  -e 180000 \
  --dump-db \
  --dump-select-db lifetime \
  --dramsim3-ini "$PWD/config/XiangShan.ini" \
  --dramsim3-outdir "$PWD/results/dramsim3"
```

`-b/-e` 在这里是 guest cycle 范围，不是 instruction count。`--enable-fork` 会禁用 waveform；纯性能分析通常不需要 LightSSS fork，直接省略 `--dump-wave` 即可得到 DB-only 运行。

## 5. PerfCCT 分析
`tools/perfcct.py` 只依赖 Python 标准库中的 `sqlite3`；如需显示反汇编，再额外提供 `objdump` 或 `spike-dasm`。

### 快速查看
打印前 20 个已提交 uop 及常用延迟：

```bash
python3 tools/perfcct.py "$DB" --limit 20 --latency
```

默认输出中的流水级缩写：

| 缩写 | 阶段 | 缩写 | 阶段 |
| --- | --- | --- | --- |
| `f` | Fetch | `d` | Decode |
| `r` | Rename | `D` | Dispatch Queue |
| `i` | Issue Queue | `a` | Issue Arbitration |
| `g` | Read Register | `e` | Functional Unit |
| `b` | Bypass Value | `w` | Write Value |
| `c` | Commit | `.` | 该周期没有阶段标记 |


### 分析某个 PC 的一次动态执行
`--index 1` 表示过滤结果中第一个不同的动态指令序号 `SN`，并保留这个动态指令的全部 uop：

```bash
python3 tools/perfcct.py "$DB" \
  --pc 0x80000e48 \
  --index 1 \
  --committed \
  --visual \
  --cycle \
  --latency
```

紧凑地将每个 uop 放在一行：

```bash
python3 tools/perfcct.py "$DB" \
  --pc 0x80000e48 \
  --index 1 \
  --visual \
  --singleline \
  --cycle
```

只看某个动态指令或 uop：

```bash
python3 tools/perfcct.py "$DB" --sn 12345 --uop-idx 3 --latency
```

显示指令反汇编：

```bash
python3 tools/perfcct.py "$DB" \
  --pc 0x80000e48 \
  --index 1 \
  --dasm riscv64-linux-gnu-objdump
```

常用选项：

| 选项 | 含义 |
| --- | --- |
| `--pc ADDR` | 按 PC 过滤，支持 `0x...` |
| `--sn N` | 按动态指令 sequence number 过滤 |
| `--uop-idx N` | 按拆分后的 uop 序号过滤 |
| `--index N` | 选取过滤结果中的第 N 个动态指令，1-based |
| `--limit N` | 限制输出行数 |
| `--latency` | 输出 issue-to-readreg、readreg-to-fu、issue-to-writeback、issue-to-commit |
| `-v`, `--visual` | 输出字符形式的流水时间线 |
| `-l`, `--singleline` | 每个 uop 只显示一行时间线 |
| `-c`, `--cycle` | 在 visual 模式显示周期行号 |
| `-z N`, `--zoom N` | 调整每行显示的周期数，默认一行 100 cycles |
| `-p N`, `--period N` | 将时间戳除以 N 后显示，原始 cycle 分析保持 `1` |
| `--spec` | 包含未提交的推测执行记录；默认只看已提交记录 |
| `--committed` | 与 `--spec` 一起使用时仍只保留已提交记录 |


## 6. 常见问题
| 现象 | 优先检查 |
| --- | --- |
| `emu: ... not found` | `ldd bin/emu` 和发行版/glibc 版本 |
| DRAMSim3 初始化后长期没有 guest 输出 | 先用 `file <payload>` 检查；不能使用 x86-64 或普通 Linux 动态 ELF，应使用 AM 生成的 `riscv64-xs.bin` |
| `The first address in the elf does not match...` | ELF load address 不符合 XSAI bare-metal 布局；检查是否使用 `ARCH=riscv64-xs` 和 AM linker script |
| `Cannot open DRAMSIM3 config file` | 是否传了交付包内配置的绝对路径 |
| 在 `$NOOP_HOME/build` 断言或无法保存 DB | 是否设置 `NOOP_HOME` 且提前创建 `build/` |
| DB 没有 `LifeTimeCommitTrace` | 是否使用 `--dump-db --dump-select-db lifetime`，二进制是否启用 ChiselDB/PerfCCT |
| DB 为 0 字节 | 是否异常终止、磁盘写满，或在 DB 落盘前杀死进程 |
| 找不到目标 PC | 地址是否为实际运行地址，记录是否被 `-I` 截断，必要时加 `--spec` |
| `--dasm` 没有汇编文本 | RISC-V objdump 是否安装、命令路径是否正确 |
| difftest mismatch | payload、restorer、reference `.so`、RTL/ISA 版本是否匹配 |

