param([string]$OutputDirectory)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $root 'outputs' }
$git = (Get-Command git -ErrorAction Stop).Source
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('shiyi-source-' + [guid]::NewGuid().ToString('N'))
$archive = $null
$stream = $null
$destination = $null
try {
    & $git init --bare --quiet $scratch
    if ($LASTEXITCODE -ne 0) { throw 'Could not prepare the temporary file inventory.' }
    $files = @(& $git --git-dir=$scratch --work-tree=$root -c core.quotepath=false ls-files --others --exclude-standard)
    if ($LASTEXITCODE -ne 0) { throw 'Could not enumerate source files.' }
    if ('pubspec.yaml' -notin $files -or 'lib/main.dart' -notin $files) {
        throw 'The source inventory is incomplete.'
    }
    if (@($files | Where-Object { $_ -match '(^|/)(.git|.toolchain|build|deliverables|work|.shiyi-avatar)(/|$)|.(apk|aab|pem|key|keystore|jks|p12|pfx)$|(^|/)(.env(..*)?|env)$' -and $_ -notmatch '(^|/).env.example$' }).Count) {
        throw 'The source inventory contains private or generated files. Review .gitignore.'
    }
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
    $destination = Join-Path $OutputDirectory ('Shiyi-client-source-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.zip')
    $stream = [IO.File]::Open($destination, [IO.FileMode]::CreateNew)
    $archive = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Create)
    foreach ($file in $files) {
        $entry = 'CyberVerseApp/' + $file.Replace('\', '/')
        [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, (Join-Path $root $file), $entry, [IO.Compression.CompressionLevel]::Optimal) | Out-Null
    }
    $archive.Dispose(); $archive = $null
    $stream.Dispose(); $stream = $null
    Get-Item -LiteralPath $destination | Select-Object FullName, Length
} finally {
    if ($archive) { $archive.Dispose() }
    if ($stream) { $stream.Dispose() }
    # Remove only this invocation's generated temporary Git metadata.
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    $resolvedScratch = [IO.Path]::GetFullPath($scratch)
    if ($resolvedScratch.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolvedScratch -Leaf) -match '^shiyi-source-[0-9a-f]{32}$' -and (Test-Path -LiteralPath $resolvedScratch)) {
        Remove-Item -LiteralPath $resolvedScratch -Recurse -Force
    }
}
