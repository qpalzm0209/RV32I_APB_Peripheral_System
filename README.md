# RV32I Single-Cycle vs Multi-Cycle CPU

## 프로젝트 개요

- **발표영상(Single-cycle)**:  
  https://drive.google.com/file/d/1Dd8-uVmVCR4iDrL1-sjQq4NRWUTZ-mOQ/view?usp=drive_link
- **발표자료(Single-cycle)**:  
  https://drive.google.com/file/d/1lJpqC5rr4aY5bQ42WpIgWDJ5MNwCTp14/view?usp=drive_link
- **발표자료(Multi-cycle)**:  
  https://drive.google.com/file/d/19TSYeDSoE6Xd23otR7XnSdfvnUUCIZsA/view?usp=drive_link

동일한 RV32I 명령어 집합을 실행하는 CPU를 **single-cycle**과 **multi-cycle** 구조로 각각 구현하고, 명령 실행 방식과 FPGA 구현 결과를 비교한 SystemVerilog 프로젝트입니다.

두 구현은 같은 register file, ALU 연산, immediate 형식, branch/jump 조건과 byte-addressed data memory 규격을 사용합니다.  
공통 self-checking testbench를 각 코어에 실행해 기능적 동등성을 확인하고, 동일한 FPGA 및 clock constraint에서 합성·배치·배선 결과를 비교합니다.


## 지원 명령어

총 37개의 RV32I 명령어를 지원합니다.

- R-Type: `ADD`, `SUB`, `SLL`, `SLT`, `SLTU`, `XOR`, `SRL`, `SRA`, `OR`, `AND`
- I-Type ALU: `ADDI`, `SLTI`, `SLTIU`, `XORI`, `ORI`, `ANDI`, `SLLI`, `SRLI`, `SRAI`
- Load: `LB`, `LH`, `LW`, `LBU`, `LHU`
- Store: `SB`, `SH`, `SW`
- Branch: `BEQ`, `BNE`, `BLT`, `BGE`, `BLTU`, `BGEU`
- Upper/Jump: `LUI`, `AUIPC`, `JAL`, `JALR`


## 아키텍처 비교

| 항목 | Single-cycle | Multi-cycle |
| --- | --- | --- |
| 명령 실행 | 모든 단계를 한 clock cycle에 처리 | 실행 단계를 FSM 상태로 분리 |
| 제어 방식 | opcode 기반 조합논리 | 12-state sequential FSM |
| 중간 레지스터 | 별도 단계 레지스터 없음 | `IR`, `OldPC`, `A`, `B`, `ALUOut`, `MDR` |
| 명령당 cycle | 모든 명령 1 cycle | 명령 종류에 따라 3~5 cycles |
| 주요 장점 | 낮은 CPI, 단순한 상태 흐름 | 짧은 조합 경로, 단계별 자원 재사용 |
| 주요 trade-off | 가장 긴 명령이 clock period 결정 | 명령 latency와 제어 상태 증가 |


### Single-cycle 실행 흐름

```text
Fetch → Decode → Execute → Memory → Write Back
              (한 clock cycle 안에서 수행)
```

PC에서 instruction을 읽은 뒤 register file, immediate extender, ALU, data memory, write-back mux를 하나의 조합 경로로 통과합니다.  
모든 명령의 CPI는 1이지만, load나 branch처럼 긴 경로가 전체 clock period를 제한합니다.


### Multi-cycle 실행 흐름

```text
FETCH → DECODE ┬→ ALU_EXEC → ALU_WB
               ├→ MEM_ADDR → MEM_READ → MEM_WB
               ├→ MEM_ADDR → MEM_WRITE
               ├→ BRANCH
               ├→ LUI_WB
               ├→ JUMP
               └→ JALR_EXEC
```

FSM은 다음 12개 상태로 구성됩니다.

| 상태 | 동작 |
| --- | --- |
| `FETCH` | instruction을 IR에 저장하고 `PC + 4` 계산 |
| `DECODE` | instruction 해석 및 `rs1`, `rs2` operand 저장 |
| `ALU_EXEC` | R/I-Type ALU 또는 AUIPC 연산 |
| `ALU_WB` | ALU 결과를 `rd`에 기록 |
| `MEM_ADDR` | load/store effective address 계산 |
| `MEM_READ` | data memory 출력값을 MDR에 저장 |
| `MEM_WB` | MDR 값을 `rd`에 기록 |
| `MEM_WRITE` | `rs2` 값을 data memory에 기록 |
| `BRANCH` | 조건 비교 후 branch target으로 PC 갱신 |
| `LUI_WB` | upper immediate를 `rd`에 기록 |
| `JUMP` | JAL link 저장 및 PC 갱신 |
| `JALR_EXEC` | JALR link 저장 및 정렬된 target으로 PC 갱신 |

명령 종류별 cycle 수는 다음과 같습니다.

| 명령 종류 | Cycles |
| --- | ---: |
| R-Type / I-Type ALU / AUIPC | 4 |
| Load | 5 |
| Store | 4 |
| Branch / LUI / JAL / JALR | 3 |


## FPGA 구현 및 Fmax 측정

두 구조는 instruction memory, CPU, data memory를 연결한 `rv32i_top` 전체를 동일한 조건으로 합성, placement, routing하여 비교했습니다.

- FPGA: Xilinx Artix-7 `xc7a35tcpg236-1` (Basys3)
- Tool: Vivado 2020.2
- 성능 비교 대상: memory-inclusive `rv32i_top`


### Fmax 탐색 결과

`scripts/find_fmax.ps1`은 10.000 ns에서 시작하여 각 구현의 routed WNS를 읽고 다음 식으로 clock period를 낮춥니다.

```text
next_period = period - WNS - 0.05 ns
```

WNS가 음수가 되면 직전 통과 period를 결과로 채택합니다. 10.000 ns에서 바로 실패하는 대상은 먼저 음수 WNS만큼 period를 늘려 최초 통과점을 확보한 뒤 같은 하향 탐색을 수행합니다.

| 대상 | 최소 통과 주기 | Fmax | 크리티컬 패스 |
| ---- | ----: | ----: | --- |
| single-cycle | `16.148 ns` | `61.93 MHz` | `U_RV32I_CPU/U_DATAPATH/U_PC/U_PC_REG/reg_q_reg[4]/C` → `U_RV32I_CPU/U_DATAPATH/U_REG_FILE/reg_file_reg[23][9]/D` |
| multi-cycle | `8.968 ns` | `111.51 MHz` | `U_RV32I_CPU/U_DATAPATH/ir_q_reg[1]/C` → `U_RV32I_CPU/U_DATAPATH/pc_q_reg[28]/D` |


### 명령어 처리 성능

명령어당 실행시간은 `clock period × CPI`로 계산합니다.  
아래 비교는 single-cycle CPI를 1, multi-cycle의 대표 CPI를 4로 가정한 값입니다.  
*실제 multi-cycle CPI는 명령 종류에 따라 3~5이므로 프로그램의 instruction mix에 따라 달라질 수 있습니다.*  

| 구조 | Clock period | 평균 CPI | 명령어당 실행시간 |
| --- | ---: | ---: | ---: |
| Single-cycle top | `16.148 ns` | 1 | `16.148 ns/instruction` |
| Multi-cycle top | `8.968 ns` | 4 | `35.872 ns/instruction` |

Multi-cycle은 더 높은 Fmax를 달성하지만, 많은 cycle에 걸쳐 명령을 실행합니다.
single-cycle은 Fmax가 61.93 MHz로 낮아지는 반면, multi-cycle은 111.51 MHz를 달성합니다.
그러나 CPI를 고려하면 명령어 처리시간은 single-cycle이 `2.22x` 짧습니다.
따라서 구조 비교에는 Fmax와 CPI를 함께 사용해야 합니다.


## 추가탐구) Multi-cycle 타이밍 개선

<img width="1405" height="600" alt="image" src="https://github.com/user-attachments/assets/dd0d7431-734c-4b31-acd4-1b3289b06f95" />  

초기 multi-cycle 구현의 timing report에서는 `register_input → alu_out` 구간이 주요 병목으로 나타났고, 단계별 조합논리를 다시 분배해봤습니다.   

1. `register_input` 처리 뒤 ALU 입력 신호를 준비하던 mux/operand 선택 논리를 execute 단계에서 decode 단계로 이동했습니다.
2. Decode 단계에서 `A`, `B`, immediate와 ALU source 선택을 미리 결정하여 execute 단계에는 실제 ALU 연산 중심의 경로만 남겼습니다.  

<img width="1364" height="613" alt="image" src="https://github.com/user-attachments/assets/ea0b62da-ee2b-45c8-949d-786bbdbfddbe" />  

해당 경로는 기존 7 logic levels와 185 high-fanout loads를 포함했고, timing margin은 `+0.654 ns`였습니다.  
변경 후 주요 경로는 6 logic levels와 119 high-fanout loads로 줄었고, timing margin은 `+0.771 ns`로 `0.117 ns` 증가했습니다.  

추가로 execute 단계를 mux 선택과 ALU 연산의 두 상태로 한 번 더 분리하는 방법도 검토했습니다.  
이 방식은 조합 경로를 더 줄여 Fmax를 높일 수 있지만, FSM 상태와 명령당 cycle 수가 증가합니다.  
해당 프로젝트에서는 학습용 제어 단계 구분과 명령어 처리 흐름을 명확히 유지하기 위해 해당 변경은 적용하지 않았습니다.


## 디렉터리 구조

```text
.
├─ single_cycle/
│  └─ rtl/
│     ├─ rv32i_cpu.sv
│     ├─ rv32i_datapath.sv
│     ├─ instruction_mem.sv
│     ├─ data_mem.sv
│     ├─ rv32i_top.sv
│     ├─ define.vh
│     └─ riscv_prg.mem
├─ multi_cycle/
│  └─ rtl/
│     ├─ rv32i_cpu.sv
│     ├─ rv32i_datapath.sv
│     ├─ instruction_mem.sv
│     ├─ data_mem.sv
│     ├─ rv32i_top.sv
│     ├─ define.vh
│     └─ riscv_prg.mem
├─ tests/
│  ├─ common/
│  │  ├─ tb_rv32i_isa.sv
│  │  └─ tb_control_flow_edges.sv
│  └─ multi_cycle/
│     ├─ tb_multicycle_timing.sv
│     └─ tb_illegal_instruction.sv
└─ scripts/
   ├─ run_tests.ps1
   ├─ compare_timing.tcl
   ├─ run_timing_comparison.ps1
   ├─ find_fmax.ps1
   └─ preserve_top.xdc
```

## 검증 실행

### 기능 시뮬레이션

```powershell
powershell -ExecutionPolicy Bypass -File scripts/run_tests.ps1
```

공통 ISA 및 control-flow testbench를 두 코어에 각각 실행합니다. 멀티사이클 코어에는 상태별 PC timing과 illegal instruction side-effect 억제 검증을 추가로 실행합니다.

### 타이밍 비교

```powershell
powershell -ExecutionPolicy Bypass -File scripts/run_timing_comparison.ps1
```

이 스크립트는 기존 호환성을 위한 CPU OOC 10 ns 회귀 검사입니다. 메모리 접근이 제외되므로 생성된 `.reports/single_cycle`, `.reports/multi_cycle` 결과는 시스템 성능 비교에 사용하지 않습니다.

### Fmax 탐색

```powershell
powershell -ExecutionPolicy Bypass -File scripts/find_fmax.ps1
```

스크립트는 진단용 CPU OOC와 memory-inclusive top을 모두 실행하지만, 시스템 성능 비교에는 `rv32i_top` 두 결과만 사용합니다. 각 반복의 period, WNS, datapath delay, startpoint, endpoint는 `.reports/fmax_logs/find_fmax.log`에 기록되고, 최종 결과는 `.reports/fmax_summary.md`에 생성됩니다.

`compare_timing.tcl`을 직접 호출할 때는 두 번째 Tcl 인자로 period(ns), 세 번째 인자로 구현 대상(`cpu_ooc` 또는 `top`)을 지정할 수 있습니다. 성능 측정에는 메모리를 포함하는 `top`을 지정합니다.

```powershell
C:\Xilinx\Vivado\2020.2\bin\vivado.bat -mode batch -nojournal -nolog `
  -source scripts/compare_timing.tcl -tclargs single_cycle 16.000 top
```
