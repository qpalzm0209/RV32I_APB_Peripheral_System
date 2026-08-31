# RV32I Single-Cycle vs Multi-Cycle CPU

## 프로젝트 개요
발표영상(싱글) : https://drive.google.com/file/d/1Dd8-uVmVCR4iDrL1-sjQq4NRWUTZ-mOQ/view?usp=drive_link  
발표자료(싱글) : https://drive.google.com/file/d/1lJpqC5rr4aY5bQ42WpIgWDJ5MNwCTp14/view?usp=drive_link  
발표자료(멀티) : https://drive.google.com/file/d/19TSYeDSoE6Xd23otR7XnSdfvnUUCIZsA/view?usp=drive_link  

동일한 RV32I 명령어 집합을 실행하는 CPU를 **single-cycle**과 **multi-cycle** 구조로 각각 구현하고, 명령 실행 방식과 FPGA 구현 결과를 비교한 SystemVerilog 프로젝트입니다.

두 구현은 같은 register file, ALU 연산, immediate 형식, branch/jump 조건과 byte-addressed data memory 규격을 사용합니다. 공통 self-checking testbench를 각 코어에 실행해 기능적 동등성을 확인하고, 동일한 FPGA 및 clock constraint에서 합성·배치·배선 결과를 비교합니다.

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

PC에서 instruction을 읽은 뒤 register file, immediate extender, ALU, data memory, write-back mux를 하나의 조합 경로로 통과합니다. 모든 명령의 CPI는 1이지만, load나 branch처럼 긴 경로가 전체 clock period를 제한합니다.

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

## FPGA 구현 결과

두 CPU를 동일한 조건에서 각각 out-of-context 합성한 뒤 placement와 routing까지 수행했습니다.

- FPGA: Xilinx Artix-7 `xc7a35tcpg236-1` (Basys3)
- Clock constraint: `10.000 ns` (100 MHz)
- Tool: Vivado 2020.2
- 비교 대상: `rv32i_cpu` core

| 항목 | Single-cycle | Multi-cycle | 변화 |
| --- | ---: | ---: | ---: |
| Worst Negative Slack | `+0.126 ns` | `+0.749 ns` | `+0.623 ns` |
| Worst datapath delay | `9.743 ns` | `9.100 ns` | `-0.643 ns` (`-6.6%`) |
| Slice LUTs | `1,556` | `1,332` | `-224` (`-14.4%`) |
| Slice Registers | `1,024` | `1,230` | `+206` (`+20.1%`) |
| 100 MHz timing | 충족 | 충족 | Multi-cycle 여유 증가 |

멀티사이클 구조는 한 명령을 여러 cycle에 나누면서 CPI는 증가하지만, 한 cycle에 통과하는 조합논리를 줄여 timing margin을 확보했습니다. 또한 단계별로 ALU를 재사용하면서 LUT 사용량이 감소했고, 중간값을 보존하는 stage register 때문에 flip-flop 사용량은 증가했습니다.

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
   └─ run_timing_comparison.ps1
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
