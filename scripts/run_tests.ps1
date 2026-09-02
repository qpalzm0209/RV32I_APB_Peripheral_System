$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$vivadoBin = 'C:\Xilinx\Vivado\2020.2\bin'
$xvlog = Join-Path $vivadoBin 'xvlog.bat'
$xelab = Join-Path $vivadoBin 'xelab.bat'
$xsim = Join-Path $vivadoBin 'xsim.bat'

foreach ($tool in @($xvlog, $xelab, $xsim)) {
    if (-not (Test-Path -LiteralPath $tool)) {
        throw "Vivado simulator tool not found: $tool"
    }
}

$variants = @(
    @{
        Name = 'single_cycle'
        Tests = @(
            'common\tb_rv32i_isa.sv',
            'common\tb_control_flow_edges.sv'
        )
    },
    @{
        Name = 'multi_cycle'
        Tests = @(
            'common\tb_rv32i_isa.sv',
            'common\tb_control_flow_edges.sv',
            'multi_cycle\tb_multicycle_timing.sv',
            'multi_cycle\tb_illegal_instruction.sv',
            'multi_cycle\tb_register_file_reset.sv',
            'multi_cycle\tb_data_mem_reset.sv'
        )
    }
)

foreach ($variant in $variants) {
    $variantName = $variant.Name
    $rtlDir = Join-Path $projectRoot "$variantName\rtl"

    foreach ($testRelative in $variant.Tests) {
        $testName = [System.IO.Path]::GetFileNameWithoutExtension($testRelative)
        $runName = "${variantName}_${testName}"
        $buildDir = Join-Path $projectRoot ".sim\$runName"

        if (Test-Path -LiteralPath $buildDir) {
            $resolvedBuild = (Resolve-Path -LiteralPath $buildDir).Path
            $resolvedRoot = (Resolve-Path -LiteralPath $projectRoot).Path
            if (-not $resolvedBuild.StartsWith($resolvedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
                throw "Refusing to clean simulation directory outside project: $resolvedBuild"
            }
            Remove-Item -LiteralPath $buildDir -Recurse -Force
        }
        New-Item -ItemType Directory -Path $buildDir -Force | Out-Null

        Push-Location $buildDir
        try {
            & $xvlog -sv -i $rtlDir `
                (Join-Path $rtlDir 'rv32i_cpu.sv') `
                (Join-Path $rtlDir 'rv32i_datapath.sv') `
                (Join-Path $rtlDir 'data_mem.sv') `
                (Join-Path $projectRoot "tests\$testRelative")
            if ($LASTEXITCODE -ne 0) { throw "xvlog failed for $runName" }

            & $xelab $testName -s "${runName}_snapshot"
            if ($LASTEXITCODE -ne 0) { throw "xelab failed for $runName" }

            $simOutput = & $xsim "${runName}_snapshot" -runall 2>&1
            $simExit = $LASTEXITCODE
            $simOutput | ForEach-Object { Write-Host $_ }
            $simText = $simOutput -join "`n"
            if (($simExit -ne 0) -or ($simText -match '(?m)^Fatal:') -or
                ($simText -notmatch "PASS:.*$testName")) {
                throw "simulation assertions failed for $runName"
            }
            Write-Host "PASS: $runName"
        }
        finally {
            Pop-Location
        }
    }
}

Write-Host 'PASS: all single-cycle and multi-cycle simulations'
