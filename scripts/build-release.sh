#!/usr/bin/env bash
# 本地发行构建：Linux x86_64 原生 + Windows x86_64 交叉编译，不经过 CI。
# 依赖：Zig 0.14.1、Node.js、curl、unzip、zip、tar、sha256sum；
#       Linux 构建另需 pkg-config 能找到 sdl3 与 sdl3-ttf。
# 可选：wine（用于运行 Windows 版自检）。
# 用法： ./scripts/build-release.sh [--no-test]
# 环境： ZIG=/path/to/zig  SDL_MIRROR=https://mirror/  （SDL_MIRROR 置空则直连 GitHub）
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

zig="${ZIG:-zig}"
mirror="${SDL_MIRROR-https://ghfast.top/}"
if [ -n "$mirror" ]; then mirror="${mirror%/}/"; fi

no_test=0
for arg in "$@"; do
    case "$arg" in
        --no-test) no_test=1 ;;
        *) echo "未知参数：$arg" >&2; exit 2 ;;
    esac
done

die() { echo "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "缺少命令：$1"; }

version="$(sed -n 's/.*const APP_VERSION = "\([^"]*\)".*/\1/p' src/main.zig | head -n1)"
[ -n "$version" ] || die "读不到 src/main.zig 里的 APP_VERSION"

need "$zig"
need node
need curl
need unzip
need zip
need tar
need sha256sum
got="$("$zig" version)"
[ "$got" = "0.14.1" ] || die "Zig 版本不对：$got，本工程按 0.14.1 写"
pkg-config --exists sdl3 sdl3-ttf 2>/dev/null ||
    die "缺少 SDL3 / SDL3_ttf 开发包（pkg-config 找不到 sdl3 或 sdl3-ttf）"

release="$root/build/release"
reports="$release/reports"
rm -rf "$release"
mkdir -p "$reports"

echo "[1/4] 生成图集…"
node tools/gen_atlas.js

echo
echo "[2/4] 构建 Linux 版…"
"$zig" build -Doptimize=ReleaseSmall
linux_stage="$release/complexweeper-$version-linux-x86_64"
mkdir -p "$linux_stage"
cp zig-out/bin/complexweeper "$linux_stage/complexweeper"
cp README.md README.en.md LICENSE ASSET-NOTICE.md "$linux_stage/"

if [ "$no_test" -eq 0 ]; then
    "$linux_stage/complexweeper" --selftest "$reports/selftest-linux.txt"
    tail -n 2 "$reports/selftest-linux.txt"
    "$linux_stage/complexweeper" --uitest "$reports/uitest-linux.txt"
    tail -n 2 "$reports/uitest-linux.txt"
fi

tar -C "$release" -czf "$release/complexweeper-$version-linux-x86_64.tar.gz" \
    "complexweeper-$version-linux-x86_64"

sdl_ver=3.4.18
ttf_ver=3.2.2
deps="$root/build/sdl-deps"
mkdir -p "$deps"

fetch_dep() {
    local name="$1" url="$2" zip="$deps/$1.zip" dir="$deps/$1"
    if [ -d "$dir" ]; then return; fi
    if [ ! -f "$zip" ]; then
        local urls=() tmp="$zip.part" u
        [ -n "$mirror" ] && urls+=("$mirror$url")
        urls+=("$url")
        rm -f "$tmp"
        for u in "${urls[@]}"; do
            echo "  下载 $name ← $u"
            if curl -fL --retry 3 --connect-timeout 30 --max-time 900 -o "$tmp" "$u"; then
                mv "$tmp" "$zip"
                break
            fi
            rm -f "$tmp"
        done
        [ -f "$zip" ] || die "下载 $name 失败；可用 SDL_MIRROR 换镜像，或手动把 $name.zip 放进 $deps"
    fi
    mkdir -p "$dir"
    unzip -q "$zip" -d "$dir"
}

echo
echo "[3/4] 构建 Windows 版…"
fetch_dep "SDL3-devel" \
    "https://github.com/libsdl-org/SDL/releases/download/release-$sdl_ver/SDL3-devel-$sdl_ver-mingw.zip"
fetch_dep "SDL3_ttf-devel" \
    "https://github.com/libsdl-org/SDL_ttf/releases/download/release-$ttf_ver/SDL3_ttf-devel-$ttf_ver-mingw.zip"

sdl_inc="$(find "$deps/SDL3-devel" -type d -path '*/x86_64-w64-mingw32/include/SDL3' -print -quit)"
ttf_inc="$(find "$deps/SDL3_ttf-devel" -type d -path '*/x86_64-w64-mingw32/include/SDL3_ttf' -print -quit)"
sdl_lib="$(find "$deps/SDL3-devel" -type f -path '*/x86_64-w64-mingw32/lib/libSDL3.dll.a' -print -quit)"
ttf_lib="$(find "$deps/SDL3_ttf-devel" -type f -path '*/x86_64-w64-mingw32/lib/libSDL3_ttf.dll.a' -print -quit)"
sdl_dll="$(find "$deps/SDL3-devel" -type f -path '*/x86_64-w64-mingw32/bin/SDL3.dll' -print -quit)"
ttf_dll="$(find "$deps/SDL3_ttf-devel" -type f -path '*/x86_64-w64-mingw32/bin/SDL3_ttf.dll' -print -quit)"
[ -n "$sdl_inc" ] && [ -n "$ttf_inc" ] && [ -n "$sdl_lib" ] && [ -n "$ttf_lib" ] &&
    [ -n "$sdl_dll" ] && [ -n "$ttf_dll" ] || die "SDL 开发包目录不完整"

inc_root="$root/build/sdl-include"
lib_root="$root/build/sdl-lib"
rm -rf "$inc_root" "$lib_root"
mkdir -p "$inc_root" "$lib_root"
cp -r "$(dirname "$sdl_inc")/SDL3" "$inc_root/"
cp -r "$(dirname "$ttf_inc")/SDL3_ttf" "$inc_root/"
# Zig 的 linkSystemLibrary 在 windows-gnu 下只认 libSDL3.a，不认 libSDL3.dll.a。
cp "$sdl_lib" "$lib_root/libSDL3.a"
cp "$ttf_lib" "$lib_root/libSDL3_ttf.a"

"$zig" build -Dtarget=x86_64-windows-gnu -Doptimize=ReleaseSmall \
    -Dsdl-include="$inc_root" -Dsdl-lib="$lib_root"

win_stage="$release/complexweeper-$version-win64"
mkdir -p "$win_stage"
cp zig-out/bin/complexweeper.exe "$win_stage/"
cp "$sdl_dll" "$ttf_dll" "$win_stage/"

node tools/set_icon.js "$win_stage/complexweeper.exe" "$win_stage/complexweeper-icon.exe"
mv "$win_stage/complexweeper-icon.exe" "$win_stage/complexweeper.exe"
node tools/inspect_exe.js "$win_stage/complexweeper.exe"

if [ "$no_test" -eq 0 ]; then
    if command -v wine >/dev/null 2>&1; then
        if ! (cd "$win_stage" && WINEDEBUG=-all wine complexweeper.exe --selftest selftest.txt \
                >/dev/null 2>"$reports/wine-selftest.log"); then
            cat "$reports/wine-selftest.log" >&2
            die "Windows 规则自检失败"
        fi
        tail -n 2 "$win_stage/selftest.txt"
        if ! (cd "$win_stage" && WINEDEBUG=-all wine complexweeper.exe --uitest uitest.txt \
                >/dev/null 2>"$reports/wine-uitest.log"); then
            cat "$reports/wine-uitest.log" >&2
            die "Windows 界面自检失败"
        fi
        tail -n 2 "$win_stage/uitest.txt"
        mv "$win_stage/selftest.txt" "$reports/selftest-windows.txt"
        mv "$win_stage/uitest.txt" "$reports/uitest-windows.txt"
    else
        echo "警告：未安装 wine，跳过 Windows 版自检。" >&2
    fi
fi

echo
echo "[4/4] 打包…"
zip -j "$release/complexweeper-$version-win64.zip" \
    "$win_stage/complexweeper.exe" "$win_stage/SDL3.dll" "$win_stage/SDL3_ttf.dll" \
    README.md README.en.md LICENSE ASSET-NOTICE.md >/dev/null

(
    cd "$release"
    shopt -s nullglob
    files=(*.zip *.tar.gz)
    [ "${#files[@]}" -gt 0 ] || die "没有生成发行包"
    sha256sum "${files[@]}" > SHA256SUMS
)

echo
echo "完成，发行包在 $release："
ls -lh "$release"/*.zip "$release"/*.tar.gz "$release/SHA256SUMS"
if [ "$no_test" -eq 0 ]; then
    echo "自检报告在 $reports"
fi
echo
echo "上传： ./scripts/upload-release.sh v$version"
