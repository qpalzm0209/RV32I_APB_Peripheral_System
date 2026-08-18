$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$vivado = 'C:\Xilinx\Vivado\2020.2\bin\vivado.bat'
$tclScript = Join-Path $PSScriptRoot 'compare_timing.tcl'
$reportRoot = Join-Path $projectRoot '.reports'

if (-not (Test-Path -LiteralPath $vivado)) {
    throw "Vivado not found: $vivado"
}

if (Test-Path -LiteralPath $reportRoot) {
    $resolvedReports = (Resolve-Path -LiteralPath $reportRoot).Path
    $resolvedRoot = (Resolve-Path -LiteralPath $projectRoot).Path
    if (-not $resolvedReports.StartsWith($resolvedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to clean report directory outside project: $resolvedReports"
    }
    Remove-Item -LiteralPath $reportRoot -Recurse -Force
}

foreach ($variant in @('single_cycle', 'multi_cycle')) {
    Push-Location $projectRoot
    try {
        $output = & $vivado -mode batch -nojournal -nolog -source $tclScript -tclargs $variant 2>&1
        $exitCode = $LASTEXITCODE
        $output | ForEach-Object { Write-Host $_ }
        $text = $output -join "`n"
        if (($exitCode -ne 0) -or ($text -match '(?m)^ERROR:') -or
            ($text -notmatch "PASS: $variant production top RTL elaboration") -or
            ($text -notmatch "PASS: $variant routed timing report generated")) {
            throw "Vivado implementation failed for $variant"
        }
    }
    finally {
        Pop-Location
    }

    Get-Content -LiteralPath (Join-Path $reportRoot "$variant\summary.txt")
}

Write-Host 'PASS: timing comparison reports generated'
