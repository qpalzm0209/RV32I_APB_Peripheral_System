$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$vivado = 'C:\Xilinx\Vivado\2020.2\bin\vivado.bat'
$tclScript = Join-Path $PSScriptRoot 'compare_timing.tcl'
$reportRoot = Join-Path $projectRoot '.reports'
$logRoot = Join-Path $reportRoot 'fmax_logs'
$summaryPath = Join-Path $reportRoot 'fmax_summary.md'
$invariant = [System.Globalization.CultureInfo]::InvariantCulture

if (-not (Test-Path -LiteralPath $vivado)) {
    throw "Vivado not found: $vivado"
}

if (Test-Path -LiteralPath $logRoot) {
    $resolvedLogRoot = (Resolve-Path -LiteralPath $logRoot).Path
    $resolvedProjectRoot = (Resolve-Path -LiteralPath $projectRoot).Path
    if (-not $resolvedLogRoot.StartsWith($resolvedProjectRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to clean Fmax log directory outside project: $resolvedLogRoot"
    }
    Remove-Item -LiteralPath $logRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
$searchLog = Join-Path $logRoot 'find_fmax.log'
Set-Content -LiteralPath $searchLog -Value ''

function Format-Number {
    param(
        [double]$Value,
        [string]$Format
    )

    return $Value.ToString($Format, $invariant)
}

function Read-KeyValueSummary {
    param([string]$Path)

    $values = @{}
    foreach ($line in Get-Content -LiteralPath $Path) {
        $separator = $line.IndexOf('=')
        if ($separator -gt 0) {
            $values[$line.Substring(0, $separator)] = $line.Substring($separator + 1)
        }
    }
    return $values
}

function Invoke-TimingRun {
    param(
        [string]$Variant,
        [string]$Target,
        [double]$Period,
        [int]$Iteration
    )

    $periodText = Format-Number $Period '0.000'
    $label = if ($Target -eq 'cpu_ooc') { "${Variant}_ooc" } else { "${Variant}_top" }
    $vivadoLog = Join-Path $logRoot ("{0}_iter_{1:00}_vivado.log" -f $label, $Iteration)

    Write-Host ("[{0}] iteration {1}: PERIOD_NS={2}" -f $label, $Iteration, $periodText)
    Push-Location $projectRoot
    try {
        # Windows PowerShell converts native stderr to terminating ErrorRecords
        # when ErrorActionPreference is Stop. Keep stderr as captured log text
        # and validate Vivado's exit code/output explicitly below.
        $savedErrorActionPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $output = & $vivado -mode batch -nojournal -nolog -source $tclScript `
                -tclargs $Variant $periodText $Target 2>&1
            $exitCode = $LASTEXITCODE
        }
        finally {
            $ErrorActionPreference = $savedErrorActionPreference
        }
    }
    finally {
        Pop-Location
    }

    $output | Set-Content -LiteralPath $vivadoLog
    $text = $output -join "`n"
    if (($exitCode -ne 0) -or ($text -match '(?m)^ERROR:') -or
        ($text -notmatch "PASS: $Variant production top RTL elaboration") -or
        ($text -notmatch "PASS: $Variant routed timing report generated")) {
        $tail = ($output | Select-Object -Last 40) -join "`n"
        throw "Vivado implementation failed for $label at ${periodText}ns. See $vivadoLog`n$tail"
    }

    $summaryDir = if ($Target -eq 'cpu_ooc') { $Variant } else { "${Variant}_top" }
    $summary = Read-KeyValueSummary (Join-Path $reportRoot "$summaryDir\summary.txt")
    foreach ($requiredKey in @('PERIOD_NS', 'WNS_NS', 'DATAPATH_DELAY_NS', 'STARTPOINT', 'ENDPOINT')) {
        if (-not $summary.ContainsKey($requiredKey)) {
            throw "Missing $requiredKey in timing summary for $label"
        }
    }

    $entry = [pscustomobject]@{
        Variant = $Variant
        Target = $Target
        Label = $label
        Iteration = $Iteration
        Period = [double]::Parse($summary.PERIOD_NS, $invariant)
        Wns = [double]::Parse($summary.WNS_NS, $invariant)
        DatapathDelay = [double]::Parse($summary.DATAPATH_DELAY_NS, $invariant)
        Startpoint = $summary.STARTPOINT
        Endpoint = $summary.ENDPOINT
    }

    $logLine = ('{0} iteration={1} PERIOD_NS={2} WNS_NS={3} DATAPATH_DELAY_NS={4} STARTPOINT={5} ENDPOINT={6}' -f `
        $label, $Iteration, (Format-Number $entry.Period '0.000'),
        (Format-Number $entry.Wns '0.000'), (Format-Number $entry.DatapathDelay '0.000'),
        $entry.Startpoint, $entry.Endpoint)
    Add-Content -LiteralPath $searchLog -Value $logLine
    Write-Host $logLine
    return $entry
}

function Find-Fmax {
    param(
        [string]$Variant,
        [string]$Target
    )

    [double]$period = 10.0
    $lastPassing = $null
    $result = $null
    $stopReason = $null

    for ($iteration = 1; $iteration -le 8; $iteration++) {
        $entry = Invoke-TimingRun $Variant $Target $period $iteration

        if ($entry.Wns -lt 0.0) {
            if ($null -eq $lastPassing) {
                # A memory-inclusive top may already fail at the required
                # 10ns starting point. Use its negative slack to establish a
                # passing point, then resume the requested downward search.
                [double]$nextPeriod = [math]::Round($period - $entry.Wns + 0.05, 3)
                Add-Content -LiteralPath $searchLog -Value `
                    ("{0} initial failure; expanding PERIOD_NS to {1}" -f `
                    $entry.Label, (Format-Number $nextPeriod '0.000'))
                $period = $nextPeriod
                continue
            }
            $result = $lastPassing
            $stopReason = "first failing trial at $(Format-Number $entry.Period '0.000')ns"
            break
        }

        $lastPassing = $entry
        [double]$nextPeriod = [math]::Round($period - $entry.Wns - 0.05, 3)
        [double]$change = [math]::Abs($nextPeriod - $period)
        if ($change -lt 0.05) {
            $result = $lastPassing
            $stopReason = 'period change below 0.05ns'
            break
        }
        if ($nextPeriod -le 0.0) {
            throw "Computed a non-positive period for $($entry.Label): $nextPeriod"
        }
        $period = $nextPeriod
    }

    if ($null -eq $result) {
        if ($null -eq $lastPassing) {
            throw "No passing timing result was found"
        }
        $result = $lastPassing
        $stopReason = 'maximum of 8 iterations reached'
    }

    $result | Add-Member -NotePropertyName StopReason -NotePropertyValue $stopReason
    $result | Add-Member -NotePropertyName FmaxMHz -NotePropertyValue (1000.0 / $result.Period)
    return $result
}

function ConvertTo-MarkdownCell {
    param([string]$Value)
    return $Value.Replace('|', '\|')
}

$results = @(
    Find-Fmax 'single_cycle' 'cpu_ooc'
    Find-Fmax 'multi_cycle' 'cpu_ooc'
    Find-Fmax 'single_cycle' 'top'
    Find-Fmax 'multi_cycle' 'top'
)

$displayNames = @{
    'single_cycle_ooc' = 'rv32i_cpu single_cycle (OOC)'
    'multi_cycle_ooc' = 'rv32i_cpu multi_cycle (OOC)'
    'single_cycle_top' = 'rv32i_top single_cycle'
    'multi_cycle_top' = 'rv32i_top multi_cycle'
}

$lines = @(
    '# RV32I Fmax 측정 결과',
    '',
    '부품: `xc7a35tcpg236-1`  ',
    '도구: Vivado 2020.2  ',
    '탐색법: 10.000ns에서 시작해 통과 시 `period - WNS - 0.05ns`로 제약을 낮추고, 첫 실패 직전의 통과 결과를 채택했다.',
    '10.000ns에서 바로 실패한 대상은 최초 통과점을 만들기 위해 `period - WNS + 0.05ns`로 한 번 이상 주기를 늘린 뒤 같은 하향 수렴법을 적용했다.  ',
    '`rv32i_top`은 출력 포트가 없는 폐쇄형 시스템이므로 일반 합성에서 전체 제거되지 않도록 세 기능 블록에 `DONT_TOUCH` 합성 제약을 적용했다.',
    '',
    '| 대상 | 최소 통과 주기 | Fmax | 크리티컬 패스 시작 | 끝 |',
    '|---|---:|---:|---|---|'
)

foreach ($result in $results) {
    $lines += ('| {0} | {1} ns | {2} MHz | `{3}` | `{4}` |' -f `
        $displayNames[$result.Label], (Format-Number $result.Period '0.000'),
        (Format-Number $result.FmaxMHz '0.00'), (ConvertTo-MarkdownCell $result.Startpoint),
        (ConvertTo-MarkdownCell $result.Endpoint))
}

$singleOoc = $results | Where-Object Label -eq 'single_cycle_ooc'
$multiOoc = $results | Where-Object Label -eq 'multi_cycle_ooc'
$singleTop = $results | Where-Object Label -eq 'single_cycle_top'
$multiTop = $results | Where-Object Label -eq 'multi_cycle_top'

$singleOocInstruction = $singleOoc.Period
$multiOocInstruction = $multiOoc.Period * 4.0
$singleTopInstruction = $singleTop.Period
$multiTopInstruction = $multiTop.Period * 4.0
$oocSpeedup = $multiOocInstruction / $singleOocInstruction
$topSpeedup = $multiTopInstruction / $singleTopInstruction

$lines += @(
    '',
    '## 명령어당 실행시간과 상대 성능',
    '',
    'CPI는 single-cycle 1, multi-cycle 4로 가정했다. 명령어당 실행시간은 `주기 × CPI`이며, 아래 상대 성능은 single-cycle이 multi-cycle보다 몇 배 빠른지를 뜻한다.',
    '',
    '| 구현 범위 | single-cycle | multi-cycle | 상대 성능 (single / multi) |',
    '|---|---:|---:|---:|',
    ('| CPU OOC | {0} ns/명령어 | {1} ns/명령어 | {2}x |' -f `
        (Format-Number $singleOocInstruction '0.000'), (Format-Number $multiOocInstruction '0.000'),
        (Format-Number $oocSpeedup '0.00')),
    ('| 메모리 포함 top | {0} ns/명령어 | {1} ns/명령어 | {2}x |' -f `
        (Format-Number $singleTopInstruction '0.000'), (Format-Number $multiTopInstruction '0.000'),
        (Format-Number $topSpeedup '0.00')),
    '',
    '## 탐색 종료 상태',
    ''
)

foreach ($result in $results) {
    $lines += ('- {0}: {1}' -f $displayNames[$result.Label], $result.StopReason)
}

$lines += @(
    '',
    '각 반복의 주기, WNS, datapath delay, startpoint, endpoint는 `fmax_logs/find_fmax.log`에 기록되어 있다.'
)

$lines | Set-Content -LiteralPath $summaryPath -Encoding UTF8
Write-Host "PASS: Fmax summary generated at $summaryPath"
