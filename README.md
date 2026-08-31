# RV32I Single-Cycle vs Multi-Cycle CPU

## 프로젝트 개요

- **발표영상(Single-cycle)**: https://drive.google.com/file/d/1Dd8-uVmVCR4iDrL1-sjQq4NRWUTZ-mOQ/view?usp=drive_link
- **발표자료(Single-cycle)**: https://drive.google.com/file/d/1lJpqC5rr4aY5bQ42WpIgWDJ5MNwCTp14/view?usp=drive_link
- **발표자료(Multi-cycle)**: https://drive.google.com/file/d/19TSYeDSoE6Xd23otR7XnSdfvnUUCIZsA/view?usp=drive_link

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

두 구조는 다음과 같은 공통 조건으로 합성, placement, routing했습니다.

- FPGA: Xilinx Artix-7 `xc7a35tcpg236-1` (Basys3)
- Tool: Vivado 2020.2
- 구현 범위:
  - `rv32i_cpu` 단독 out-of-context(OOC)
  - instruction/data memory를 연결한 `rv32i_top`

### 100 MHz 고정 제약 비교

아래 결과는 두 CPU가 `10.000 ns` 제약을 만족하는지 비교한 기준 결과입니다.

| 항목 | Single-cycle | Multi-cycle | 변화 |
| --- | ---: | ---: | ---: |
| Worst Negative Slack | `+0.126 ns` | `+0.749 ns` | `+0.623 ns` |
| Worst datapath delay | `9.743 ns` | `9.100 ns` | `-0.643 ns` (`-6.6%`) |
| Slice LUTs | `1,556` | `1,332` | `-224` (`-14.4%`) |
| Slice Registers | `1,024` | `1,230` | `+206` (`+20.1%`) |
| 100 MHz timing | 충족 | 충족 | Multi-cycle 여유 증가 |

두 구조 모두 100 MHz를 통과습니다. 여기서 Vivado는 제약을 만족하면 추가적인 타이밍 최적화를 멈출 수 있습니다.  
따라서 Fmax 비교에는 더 낮은 clock period을 반복 구현하며 최댓값을 찾는 것이 정확합니다.


### 실제 Fmax 탐색 결과

`scripts/find_fmax.ps1`은 10.000 ns에서 시작하여 각 구현의 routed WNS를 읽고 다음 식으로 clock period를 낮춥니다.

```text
next_period = period - WNS - 0.05 ns
```

WNS가 음수가 되면 직전 통과 period를 결과로 채택합니다. 10.000 ns에서 바로 실패하는 대상은 먼저 음수 WNS만큼 period를 늘려 최초 통과점을 확보한 뒤 같은 하향 탐색을 수행합니다.  
아래는 8회 반복 결과입니다.

| 대상 | 최소 통과 주기 | Fmax | 크리티컬 패스 시작 | 끝 |
| --- | ---: | ---: | --- | --- |
| `rv32i_cpu` single-cycle (OOC) | `10.000 ns` | `100.00 MHz` | `U_DATAPATH/U_REG_FILE/reg_file_reg[18][4]/C` | `U_DATAPATH/U_REG_FILE/reg_file_reg[15][8]/D` |
| `rv32i_cpu` multi-cycle (OOC) | `8.850 ns` | `112.99 MHz` | `U_DATAPATH/ir_q_reg[0]/C` | `U_DATAPATH/alu_out_q_reg[17]/D` |
| `rv32i_top` single-cycle | `16.148 ns` | `61.93 MHz` | `U_RV32I_CPU/U_DATAPATH/U_PC/U_PC_REG/reg_q_reg[4]/C` | `U_RV32I_CPU/U_DATAPATH/U_REG_FILE/reg_file_reg[23][9]/D` |
| `rv32i_top` multi-cycle | `8.968 ns` | `111.51 MHz` | `U_RV32I_CPU/U_DATAPATH/ir_q_reg[1]/C` | `U_RV32I_CPU/U_DATAPATH/pc_q_reg[28]/D` |  


### 명령어 처리 성능

명령어당 실행시간은 `clock period × CPI`로 계산합니다.  
아래 비교는 single-cycle CPI를 1, multi-cycle의 대표 CPI를 4로 가정한 값입니다.  
*실제 multi-cycle CPI는 명령 종류에 따라 3~5이므로 프로그램의 instruction mix에 따라 달라질 수 있습니다.*  

| 구현 범위 | Single-cycle | Multi-cycle | 상대 성능 |
| --- | ---: | ---: | ---: |
| CPU OOC | `10.000 ns/instruction` | `35.400 ns/instruction` | Single-cycle `3.54x` |
| 메모리 포함 top | `16.148 ns/instruction` | `35.872 ns/instruction` | Single-cycle `2.22x` |

Multi-cycle은 더 높은 Fmax를 달성하지만, 많은 cycle에 걸쳐 명령을 실행합니다.  
single-cycle은 긴 memory/execute/write-back 경로 때문에 Fmax가 61.93 MHz로 크게 낮아지는 반면, multi-cycle은 111.51 MHz를 유지합니다.  
그러나 CPI까지 포함한 명령어 처리시간은 위 가정에서 single-cycle이 더 짧습니다.  
처리 속도 비교에는 **Fmax와 CPI를 함께 사용해야 하며**, 이 때 현재 구조에서 처리속도는 **single-cycle이 더 우세합니다**


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

스크립트는 두 구현을 같은 조건으로 합성·배치·배선하고 `.reports/single_cycle`, `.reports/multi_cycle`에 timing 및 utilization report를 생성합니다.

이 명령은 기존과 동일하게 `10.000 ns` 고정 제약에서 두 CPU의 100 MHz 통과 여부를 비교합니다.

### Fmax 탐색

```powershell
powershell -ExecutionPolicy Bypass -File scripts/find_fmax.ps1
```

CPU OOC와 memory-inclusive top을 각각 반복 구현하여 최소 통과 period를 찾습니다. 각 반복의 period, WNS, datapath delay, startpoint, endpoint는 `.reports/fmax_logs/find_fmax.log`에 기록되고, 최종 비교표와 CPI 기반 성능비는 `.reports/fmax_summary.md`에 생성됩니다.

`compare_timing.tcl`을 직접 호출할 때는 두 번째 Tcl 인자로 period(ns), 세 번째 인자로 구현 대상(`cpu_ooc` 또는 `top`)을 지정할 수 있습니다. period를 생략하면 기존과 동일하게 `10.000 ns`, 구현 대상을 생략하면 `cpu_ooc`가 사용됩니다.

```powershell
C:\Xilinx\Vivado\2020.2\bin\vivado.bat -mode batch -nojournal -nolog `
  -source scripts/compare_timing.tcl -tclargs single_cycle 8.000 cpu_ooc
```
