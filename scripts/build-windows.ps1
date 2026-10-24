# 复扫雷 Complexweeper · Windows 构建脚本（SDL3 版）
#   1) 用 Node 把 assets/ 打包成图集
#   2) 下载/复用 SDL3 与 SDL3_ttf 的 MinGW 开发包
#   3) 用 Zig 交叉编译出 x86_64 Windows exe，并拷贝运行所需的 DLL
#   4) 注入图标，跑规则自检与界面自检
#
# 用法： powershell -ExecutionPolicy Bypass -File scripts/build-windows.ps1 [-NoTest]
param(
    [switch]$NoTest
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$SdlVer = '3.4.18'
$TtfVer = '3.2.2'
$cmakeOut = Join-Path $root 'build\dist'

function Find-Zig {
    $c = Get-Command zig -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    foreach ($v in @('0.14.1')) {
        $p = Join-Path $env:LOCALAPPDATA "zig-$v\zig.exe"
        if (Test-Path $p) { return $p }
    }
    $found = Get-ChildItem -Path $env:LOCALAPPDATA -Filter zig.exe -Recurse -ErrorAction SilentlyContinue |
             Select-Object -First 1
    if ($found) { return $found.FullName }
    throw "找不到 zig.exe。下载 https://ziglang.org/download/ 的 windows-x86_64 包，解压到 %LOCALAPPDATA%\zig-0.14.1\ 即可。"
}

$zig = Find-Zig
Write-Host "zig = $zig"
$ver = & $zig version
if ($ver -ne '0.14.1') { throw "Zig 版本不对：$ver，本工程按 0.14.1 写" }

New-Item -ItemType Directory -Force -Path (Join-Path $root 'build') | Out-Null
New-Item -ItemType Directory -Force -Path $cmakeOut | Out-Null

Write-Host "`n[1/5] 生成图集…"
if (Get-Command node -ErrorAction SilentlyContinue) {
    node (Join-Path $root 'tools\gen_atlas.js')
    if ($LASTEXITCODE -ne 0) { throw "生成图集失败" }
} elseif (-not (Test-Path 'src\atlas.bin') -or -not (Test-Path 'src\assets.zig')) {
    throw "缺少 src\atlas.bin 或 src\assets.zig，且没有 Node.js 可以重新生成图集。"
}

Write-Host "`n[2/5] 准备 SDL3 开发包…"
$deps = Join-Path $root 'build\sdl-deps'
New-Item -ItemType Directory -Force -Path $deps | Out-Null
function Get-Dep([string]$name, [string]$url) {
    $zip = Join-Path $deps "$name.zip"
    $dir = Join-Path $deps $name
    if (-not (Test-Path $dir)) {
        if (-not (Test-Path $zip)) {
            Write-Host "  下载 $name …"
            $ProgressPreference = 'SilentlyContinue'
            Invoke-WebRequest -Uri $url -OutFile $zip
        }
        Expand-Archive $zip -DestinationPath $dir -Force
    }
    return $dir
}
$sdlDir = Get-Dep 'SDL3-devel' "https://github.com/libsdl-org/SDL/releases/download/release-$SdlVer/SDL3-devel-$SdlVer-mingw.zip"
$ttfDir = Get-Dep 'SDL3_ttf-devel' "https://github.com/libsdl-org/SDL_ttf/releases/download/release-$TtfVer/SDL3_ttf-devel-$TtfVer-mingw.zip"

function Find-Sdl3Include([string]$dir) {
    $hit = Get-ChildItem -Path $dir -Recurse -Filter 'SDL.h' |
           Where-Object { $_.Directory.Name -eq 'SDL3' } |
           Select-Object -First 1
    if (-not $hit) { throw "在 $dir 里找不到 SDL3/SDL.h" }
    return Split-Path -Parent $hit.DirectoryName
}
function Find-TtfInclude([string]$dir) {
    $hit = Get-ChildItem -Path $dir -Recurse -Filter 'SDL_ttf.h' |
           Where-Object { $_.Directory.Name -eq 'SDL3_ttf' } |
           Select-Object -First 1
    if (-not $hit) { throw "在 $dir 里找不到 SDL3_ttf/SDL_ttf.h" }
    return Split-Path -Parent $hit.DirectoryName
}
function Find-Lib([string]$dir) {
    $hit = Get-ChildItem -Path $dir -Recurse -Filter 'libSDL3*.dll.a' | Select-Object -First 1
    if ($hit) { return $hit.DirectoryName }
    $hit = Get-ChildItem -Path $dir -Recurse -Filter 'SDL3.lib' | Select-Object -First 1
    if (-not $hit) { throw "在 $dir 里找不到 SDL3 库" }
    return $hit.DirectoryName
}

$sdlInc = Find-Sdl3Include $sdlDir
$sdlLib = Find-Lib $sdlDir
$ttfInc = Find-TtfInclude $ttfDir
$ttfLib = Find-Lib $ttfDir
# 两个开发包的 include 目录通常指向各自包根；统一找共同的父目录会错过，
# 这里把两个 include 都交给编译，库目录同理。
$incs = @($sdlInc, $ttfInc) | Select-Object -Unique
$libs = @($sdlLib, $ttfLib) | Select-Object -Unique

Write-Host "  include: $($incs -join '; ')"
Write-Host "  lib:     $($libs -join '; ')"

Write-Host "`n[3/5] 编译…"
# Zig 目前只接受一个 include 目录；SDL3_ttf 的头在它自己的包里。
# 开发包解压后通常已经包含 SDL3 头，若没有则把 ttf 的头目录复制进去。
$sdlHeaderDir = Join-Path $incs[0] 'SDL3'
$ttfHeaderDir = Join-Path $incs[-1] 'SDL3_ttf'
if (-not (Test-Path $sdlHeaderDir) -or -not (Test-Path $ttfHeaderDir)) {
    throw "SDL3 或 SDL3_ttf 头文件目录不完整"
}
# 统一 include 根：把两个包都放到同一个临时根下，避免改 Zig。
$incRoot = Join-Path $root 'build\sdl-include'
New-Item -ItemType Directory -Force -Path $incRoot | Out-Null
foreach ($d in @($sdlHeaderDir, $ttfHeaderDir)) {
    $leaf = Split-Path -Leaf $d
    $dest = Join-Path $incRoot $leaf
    if (-not (Test-Path $dest)) { Copy-Item $d $dest -Recurse -Force }
}
$libRoot = Join-Path $root 'build\sdl-lib'
New-Item -ItemType Directory -Force -Path $libRoot | Out-Null
Get-ChildItem -Path $libs -Filter '*.a' -Recurse | ForEach-Object {
    Copy-Item $_.FullName (Join-Path $libRoot $_.Name) -Force
}
Get-ChildItem -Path $libs -Filter '*.lib' -Recurse | ForEach-Object {
    Copy-Item $_.FullName (Join-Path $libRoot $_.Name) -Force
}
$argsList = @(
    'build', '-Dtarget=x86_64-windows-gnu', '-Doptimize=ReleaseSmall',
    "-Dsdl-include=$incRoot", "-Dsdl-lib=$libRoot"
)
& $zig @argsList
if ($LASTEXITCODE -ne 0) { throw "编译失败" }

Write-Host "`n[4/5] 拷贝 DLL 并注入图标…"
$exe = Join-Path $root 'zig-out\bin\complexweeper.exe'
if (-not (Test-Path $exe)) { throw "找不到 $exe" }
Copy-Item $exe (Join-Path $cmakeOut 'complexweeper.exe') -Force
# 运行期 DLL：从两个开发包中收集；同名只留一份。
foreach ($d in @($sdlDir, $ttfDir)) {
    Get-ChildItem -Path $d -Recurse -Filter '*.dll' | ForEach-Object {
        Copy-Item $_.FullName (Join-Path $cmakeOut $_.Name) -Force
    }
}
$final = Join-Path $cmakeOut 'complexweeper.exe'
$iconed = Join-Path $cmakeOut 'complexweeper-icon.exe'
node (Join-Path $root 'tools\set_icon.js') $final $iconed
if ($LASTEXITCODE -ne 0) { throw "注入图标失败" }
Move-Item $iconed $final -Force
node (Join-Path $root 'tools\inspect_exe.js') $final
if ($LASTEXITCODE -ne 0) { throw "PE 检查失败" }

$verMatch = [regex]::Match((Get-Content (Join-Path $root 'src\main.zig') -Encoding UTF8 -Raw), 'const APP_VERSION = "([0-9]+\.[0-9]+\.[0-9]+)";')
if (-not $verMatch.Success) { throw '读不到 src\main.zig 里的 APP_VERSION' }
$version = $verMatch.Groups[1].Value
$versioned = Join-Path $cmakeOut "complexweeper-$version-win64.exe"
Copy-Item $final $versioned -Force

if (-not $NoTest) {
    Write-Host "`n[5/5] 自检…"
    $rep = Join-Path $root 'build\selftest.txt'
    $p = Start-Process -FilePath $final -ArgumentList '--selftest', $rep -Wait -PassThru -NoNewWindow
    Get-Content $rep -Encoding UTF8
    if ($p.ExitCode -ne 0) { throw "规则自检失败" }

    $rep2 = Join-Path $root 'build\uitest.txt'
    $p2 = Start-Process -FilePath $final -ArgumentList '--uitest', $rep2 -Wait -PassThru -NoNewWindow
    Get-Content $rep2 -Encoding UTF8
    if ($p2.ExitCode -ne 0) { throw "界面自检失败" }
}

Write-Host "`n完成：$cmakeOut"
Get-ChildItem $cmakeOut | Select-Object Name, Length
