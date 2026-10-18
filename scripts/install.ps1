# OrzMC `orzmc` CLI 一键安装器（Windows）——PowerShell 5.1+。
#
# 用法：
#   irm https://raw.githubusercontent.com/OrzMC/OrzMCKit/main/scripts/install.ps1 | iex
# 指定版本（绕过 GitHub API 限流）：
#   $code = (irm https://raw.githubusercontent.com/OrzMC/OrzMCKit/main/scripts/install.ps1)
#   & ([scriptblock]::Create($code)) -version vX.Y.Z
# 或下载后执行：
#   powershell -ExecutionPolicy Bypass -File install.ps1 -version vX.Y.Z
#
# 选项：-version <tag> / -dir <path> / -no-modify-rc / -no-completion / -file <path> / -uninstall / -help
#
# 约定（与 Unix 安装器 / 规范 install-update.md 一致）：
#   * 资产名 `orzmc-windows-<arch>.exe`；用 Release 的 `SHA256SUMS` 校验；
#   * 二进制落在 `%LOCALAPPDATA%\Programs\orzmc\orzmc.exe`，用户 PATH 幂等添加；
#   * 安装记录 `%LOCALAPPDATA%\orzmc\install.conf`（platform=windows-<arch>、surface、version）；
#   * 补全按 frontends.md **F6**：PowerShell 只生成脚本、不落盘（这里只打印提示）。
#
# 实现约束：不用 `param()` 块（兼容 `irm | iex`），参数从 `$args` 手工解析；
# 错误一律 `throw`（不 `exit`，否则 iex 场景会把宿主窗口一起关掉）。

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$script:Repo = 'OrzMC/OrzMCKit'
$script:Name = 'orzmc'

function Write-Step([string]$message) { Write-Host "==> $message" }

function Get-Arch {
    $arch = $env:PROCESSOR_ARCHITECTURE
    switch ($arch) {
        'AMD64' { return 'x86_64' }
        'ARM64' { return 'arm64' }
        'x86' {
            if ($env:PROCESSOR_ARCHITEW6432 -eq 'AMD64') { return 'x86_64' }
            return 'x86'
        }
        default { throw "不支持的架构: $arch" }
    }
}

function Get-InstalledVersion([string]$binary) {
    if (-not (Test-Path $binary)) { return $null }
    try {
        $first = (& $binary --version | Select-Object -First 1)
        return ($first -split '\s+')[1]
    } catch { return $null }
}

function Set-UserPath([string]$dir) {
    $current = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (-not $current) { $current = '' }
    $parts = $current -split ';' | Where-Object { $_ -ne '' }
    if ($parts -contains $dir) {
        Write-Step "PATH 已包含 $dir（未改动）"
        return $null
    }
    $updated = (@($parts) + $dir) -join ';'
    [Environment]::SetEnvironmentVariable('Path', $updated, 'User')
    $env:Path = "$dir;$env:Path"
    Write-Step "已把 $dir 加入用户 PATH（新开终端生效）"
    return 'user'
}

function Remove-UserPath([string]$dir) {
    $current = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (-not $current) { return }
    $parts = $current -split ';' | Where-Object { $_ -ne '' -and $_ -ne $dir }
    [Environment]::SetEnvironmentVariable('Path', ($parts -join ';'), 'User')
}

function Invoke-Uninstall {
    $programs = Join-Path $env:LOCALAPPDATA 'Programs\orzmc'
    $binary = Join-Path $programs "$script:Name.exe"
    $stateDir = Join-Path $env:LOCALAPPDATA 'orzmc'

    if (Test-Path $programs -PathType Container) {
        Remove-Item -Recurse -Force $programs
        Write-Step "已删除 $programs（含运行时 DLL）"
    } else {
        Write-Step "未找到 $programs（可能已卸载）"
    }
    Remove-UserPath $programs
    if (Test-Path $programs -PathType Container) {
        Remove-Item -Recurse -Force $programs
    }
    $manifest = Join-Path $stateDir 'install.conf'
    if (Test-Path $manifest) {
        Remove-Item -Force $manifest
        Write-Step "已删除安装记录 $manifest"
    }
    Write-Step '完成（游戏数据默认保留）'
}

$arguments = @{}
$index = 0
while ($index -lt $args.Count) {
    $token = [string]$args[$index]
    switch -Regex ($token) {
        '^-(version|dir|file)$' {
            if ($index + 1 -ge $args.Count) { throw "$token 需要一个值" }
            $arguments[$Matches[1]] = [string]$args[$index + 1]
            $index += 2
            continue
        }
        '^-no-modify-rc$' { $arguments['noModifyRc'] = $true; $index++; continue }
        '^-no-completion$' { $arguments['noCompletion'] = $true; $index++; continue }
        '^-uninstall$' { $arguments['uninstall'] = $true; $index++; continue }
        '^(-help|-h|--help)$' {
            Write-Host '用法: install.ps1 [-version <tag>] [-dir <path>] [-no-modify-rc] [-no-completion] [-file <path>] [-uninstall]'
            return
        }
        default { throw "未知参数: $token" }
    }
}

if ($arguments['uninstall']) { Invoke-Uninstall; return }

$arch = Get-Arch
if ($arch -eq 'x86') { throw '暂不支持 32 位 Windows（请用 x64 或 arm64）' }

$installDir = if ($arguments['dir']) { $arguments['dir'] } else { Join-Path $env:LOCALAPPDATA 'Programs\orzmc' }
$binary = Join-Path $installDir "$script:Name.exe"
# Windows 资产是 zip：Swift 运行时 DLL（swiftCore/Foundation/swiftCRT/…）必须随包分发，
# 单 exe 在没有装 Swift 的机器上会直接 0xC0000135（DLL not found）。
$asset = "orzmc-windows-$arch.zip"

$version = $arguments['version']
if ($version) {
    if (-not $version.StartsWith('v')) { $version = "v$version" }
    $base = "https://github.com/$script:Repo/releases/download/$version"
} else {
    $base = "https://github.com/$script:Repo/releases/latest/download"
}

$temp = Join-Path ([IO.Path]::GetTempPath()) ("orzmc-install-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp | Out-Null
try {
    $payload = Join-Path $temp $asset
    $local = $arguments['file']
    if ($local) {
        if (-not (Test-Path $local)) { throw "本地文件不存在: $local" }
        Copy-Item -Force $local $payload
        Write-Step "使用本地二进制 $local"
    } else {
        Write-Step "下载 $base/$asset"
        Invoke-WebRequest -UseBasicParsing -Uri "$base/$asset" -OutFile $payload
        try {
            $sums = Join-Path $temp 'SHA256SUMS'
            Invoke-WebRequest -UseBasicParsing -Uri "$base/SHA256SUMS" -OutFile $sums
            $line = Select-String -Path $sums -Pattern " $([regex]::Escape($asset))$" | Select-Object -First 1
            if (-not $line) { throw "SHA256SUMS 里没有 $asset" }
            $expected = ($line.Line -split '\s+')[0].ToLower()
            $actual = (Get-FileHash -Algorithm SHA256 -Path $payload).Hash.ToLower()
            if ($expected -ne $actual) { throw "SHA256 校验失败: 期望 $expected,实际 $actual" }
            Write-Step 'SHA256 校验通过'
        } catch {
            # 校验文件缺失不阻断（老版本 Release 可能没有），但要明确告知。
            Write-Step "⚠️ 跳过校验: $($_.Exception.Message)"
        }
    }

    # 拒绝 HTML/JSON 错误页：zip 的魔数必须以 `PK` 开头。
    $magic = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($payload)[0..1])
    if ($magic -ne 'PK') {
        throw '下载内容不是有效的 zip（可能命中错误页）'
    }

    $expandDir = Join-Path $temp 'expand'
    Expand-Archive -Path $payload -DestinationPath $expandDir -Force
    $expandedExe = Join-Path $expandDir "$script:Name.exe"
    if (-not (Test-Path $expandedExe)) { throw '压缩包里没有 orzmc.exe' }
    # 再确认一次：解出来的真身是 PE 可执行文件（MZ）。
    $head = [IO.File]::ReadAllBytes($expandedExe)[0..1]
    if ($head[0] -ne 0x4D -or $head[1] -ne 0x5A) {
        throw '压缩包里的 orzmc.exe 不是有效的 Windows 可执行文件'
    }

    New-Item -ItemType Directory -Force -Path $installDir | Out-Null
    Copy-Item -Force -Recurse (Join-Path $expandDir '*') $installDir
    Write-Step "已安装到: $installDir（含运行时 DLL）"
} finally {
    Remove-Item -Recurse -Force $temp -ErrorAction SilentlyContinue
}

$pathScope = $null
if (-not $arguments['noModifyRc']) { $pathScope = Set-UserPath $installDir }

$installedVersion = Get-InstalledVersion $binary
if (-not $installedVersion) { $installedVersion = if ($version) { $version.TrimStart('v') } else { 'unknown' } }

$recordedPath = (-join (& $binary version | Select-Object -First 1))
if ($recordedPath -match 'orzmc\s+(\S+)') { $installedVersion = $Matches[1] }

$stateDir = Join-Path $env:LOCALAPPDATA 'orzmc'
New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
$manifest = Join-Path $stateDir 'install.conf'
$lines = @(
    'tool=orzmc',
    'schema=1',
    "version=$installedVersion",
    "platform=windows-$arch",
    "install_dir=$installDir",
    "binary=$binary",
    "source=$base",
    ''
)
if ($pathScope) { $lines += "path_scope=$pathScope" }
$lines += 'root_dir=' + (Join-Path $env:USERPROFILE 'minecraft')
$lines += 'surface=cli'
# F6：PowerShell 只生成脚本、不落盘 → 不写 completion_file。
[IO.File]::WriteAllLines($manifest, ($lines | Where-Object { $_ -ne '' }), [Text.UTF8Encoding]::new($false))
Write-Step "安装记录: $manifest"

if (-not $arguments['noCompletion']) {
    Write-Host ''
    Write-Host '提示：PowerShell 补全需手动加入 $PROFILE（规范 F6 不做磁盘安装）：'
    Write-Host '  orzmc completion powershell | Out-File -Append -Encoding utf8 $PROFILE'
}

Write-Host ''
Write-Host "完成。新开终端后运行: $script:Name --help"
