# 复扫雷 Complexweeper

简体中文 | [English](README.en.md)

扫雷，但雷是复数；格子上的数字是它周围所有雷之和的模长。

翻开所有非雷格子就胜利。

无论胜利还是失败，游戏都会在结局告诉玩家标错和标对了哪些雷。

本作基于 Microsoft 扫雷（原版作者 Robert Donner、Curt Johnson）的玩法重写，
使用 Zig + SDL3 实现，可原生运行于 Windows 与 Linux（Wayland / X11）。

## 游戏模式

目前有 2 种模式（未来可能还会增加）：圆复数模式、闵可夫斯基模式。

### 圆复数模式

棋盘上有四种雷，分别是正实雷、负实雷、正虚雷和负虚雷，也就是 +1、-1、+i 和 -i。

一个格子显示的数是周围所有雷之和的模长。

因为周围最多 8 格，所以只可能出现 24 种数字：

```text
0, 1, 2, 3, 4, 5, 6, 7, 8,
√2, √5, √10, √13, √17, √26, √29, √34, √37,
2√2, 2√5, 3√2, 4√2, 5√2, 2√10
```

正负雷数量相等时会互相抵消，这种 1 正 1 负的正负对我们称为“抵消对”；

0 和空白不是一回事。空白格子表示周围完全没有雷；0 表示周围完全为抵消对。

规则：当数字格子周围插上的旗帜数量等于真实雷数，且实虚比例符合真实比例或其倒数时，
则允许展开；可以利用这一点试探周围是否有抵消对。谨记扫雷的胜利判定是翻开所有的格子，
而不是插对全部的旗帜。

### 双曲复数模式（闵可夫斯基模式）

定义双曲虚数单位（类时单位）j² = 1，形式模长（时空间隔）为 S = √(a² − b²)。
本模式只是从闵可夫斯基时空度规得来的灵感，跟广义相对论没有多大关系。

棋盘上有四种雷，分别是正实雷（正类空雷）、负实雷（负类空雷）、
正双曲虚雷（正类时雷）和负双曲虚雷（负类时雷），也就是 +1、-1、+j 和 -j。

这种情况下会出现：

```text
0, 1, √3, 2, √5, √7, 2√2, 3, 2√3, √15, 4, √21, 2√6, 5, 4√2, √35, 6, 4√3, 7, 8,
i, √3i, 2i, √5i, √7i, 2√2i, 3i, 2√3i, √15i, 4i, √21i, 2√6i, 5i, 4√2i, √35i, 6i, 4√3i, 7i, 8i
```

由于出现了虚数，可以直接判断雷的实、j 部，所以展开判定更加严格，
要求实部（类空部）、j 部（类时部）的旗帜数量完全正确，不过正负仍然不做要求。

其他规则不变。

## 操作

- 鼠标左键：翻开格子
- 鼠标右键：插旗
- 鼠标中键，或左右键同时点击：展开格子
- 点击人脸，或按 `F2`：重新开局

菜单栏提供两种模式各自的初级（9×9 · 10 雷）、中级（16×16 · 40 雷）、
高级（30×16 · 99 雷）与自定义雷区，以及最高分纪录、颜色/声音开关和
100% / 200% / 300% 缩放。

最高分、声音与颜色开关保存在用户配置目录：

- Linux：`${XDG_DATA_HOME:-~/.local/share}/Complexweeper/Complexweeper/settings.ini`
- Windows：`%APPDATA%\Complexweeper\Complexweeper\settings.ini`

## 下载与运行

Windows 版可在 [Releases](../../releases) 下载。压缩包内包含 `complexweeper.exe` 与
SDL3 运行库（`SDL3.dll`、`SDL3_ttf.dll`），解压后直接运行即可，无需安装。

Linux 版可从 CI 构建产物获取，或按下文自行构建。

## 从源码构建

构建依赖：

- [Zig](https://ziglang.org/download/) 0.14.1
- SDL3 3.4.18 与 SDL3_ttf 3.2.2 开发包
- Node.js（可选，仅用于从 `assets/` 重新生成图集；仓库已附带生成结果）
- 一款中文字体（Linux 推荐安装 Noto Sans CJK 或文泉驿；Windows 自带字体即可）

### Linux

```bash
# Arch Linux
sudo pacman -S --needed base-devel sdl3 sdl3_ttf nodejs noto-fonts-cjk

# Debian / Ubuntu
sudo apt install build-essential libsdl3-dev libsdl3-ttf-dev nodejs fonts-noto-cjk

./scripts/build-linux.sh          # 构建并运行两套自检
./build/complexweeper
```

也可以直接使用 Zig：

```bash
zig build -Doptimize=ReleaseSmall
./zig-out/bin/complexweeper
```

SDL 默认会选择可用的视频驱动；在 Wayland 桌面上如需强制原生 Wayland，可设置：

```bash
SDL_VIDEODRIVER=wayland ./build/complexweeper
```

### Windows

在 PowerShell 中运行：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/build-windows.ps1
```

脚本会下载并缓存 SDL3 / SDL3_ttf 的 MinGW 开发包，用 Zig 交叉编译 64 位 Windows 程序，
把 exe 与运行库放进 `build/dist/`，注入程序图标，并运行两套自检。

下载默认走 `https://ghfast.top/` 镜像；可用 `-SdlMirror <前缀>` 或环境变量 `SDL_MIRROR`
换镜像，传 `-SdlMirror ''` 则直连 GitHub。已下载的 zip 也可以手动放进 `build/sdl-deps/` 复用。

## 自检

程序内置两套无窗口自检，覆盖规则判定与界面层的输入 → 状态 → 布局：

```bash
./build/complexweeper --selftest build/selftest.txt
./build/complexweeper --uitest build/uitest.txt
```

两份报告均会打印通过数与失败项；构建脚本与 CI 会在失败时退出。

## 目录结构

```text
src/           Zig 源码（界面与平台层、规则、音效、字体、偏好）
assets/        图集原图（彩色/黑白）与槽位表
tools/         图集、音效、图标等资源工具（Node.js）
scripts/       Linux / Windows 构建脚本
.github/       CI 构建与发布流程
build.zig      Zig 构建入口
```

## 素材与授权

扫雷原始图像素材：Microsoft（原版扫雷作者 Robert Donner、Curt Johnson）。

新增图像素材（新增的显示值、四种旗帜、伪数码管的 i、j 单位、人脸按钮等）：青月晓。

程序图标：青月晓。

本程序与 Microsoft 公司无隶属关系。

代码按 GPL-3.0 授权（见 `LICENSE`）。上文中“扫雷原始图像素材”的权利属于 Microsoft，
不在 GPL-3.0 的授权范围内。素材的详细授权状态见 [`ASSET-NOTICE.md`](ASSET-NOTICE.md)。

程序动态链接 SDL3 与 SDL3_ttf（均为 zlib 许可），运行时所需的库随 Windows 发行包一同提供。
