# RV32I APB Peripheral System

## 프로젝트 개요

FSM 기반 **multi-cycle RV32I CPU**에 APB peripheral bus를 연결하고, GPIO/FND/UART 같은 주변장치를 memory-mapped 방식으로 확장한 SoC형 HDL 프로젝트입니다.

## 목표 동작

- RV32I CPU가 fetch, decode, execute, memory access, write-back 단계를 FSM 상태별로 나누어 instruction을 실행합니다.
- APB master가 주소 영역에 따라 peripheral transaction을 생성합니다.
- APB slave들이 GPIO, FND, UART, data memory 기능을 담당합니다.
- UART 송수신 및 FND 표시를 CPU 프로그램 흐름과 연결합니다.

## 기술 스택

| 구분 | 내용 |
| --- | --- |
| 핵심 개념 | RV32I, multi-cycle FSM, APB bus, memory-mapped I/O, GPIO, FND, UART, SoC peripheral |
| 사용 장비 | Basys3 FPGA 대상 설계, UART/FND/GPIO peripheral |
| 사용 언어 | SystemVerilog |
| 개발 도구 | Vivado, HDL simulation testbench |

## 아키텍처 및 타이밍 분석

- 구조: 13-state FSM 기반 multi-cycle datapath
- 구현 조건: Basys3 `xc7a35tcpg236-1`, clock period `10.000 ns` (100 MHz)
- Worst Negative Slack: `+0.438 ns`
- Worst data path delay: `9.458 ns`
- 결과: 100 MHz timing requirement 충족

명령 실행 단계를 FSM 상태별로 분리하면서 cycle 수는 증가하지만 한 cycle에 통과하는 조합 경로가 짧아졌습니다. [Single-cycle RV32I CPU Core](https://github.com/qpalzm0209/RV32I_CPU_Core)의 `16.520 ns` 경로 및 `-6.571 ns` WNS와 비교해, multi-cycle 구현에서는 경로가 `9.458 ns`, WNS가 `+0.438 ns`로 개선됐습니다.

> 이 timing 결과는 CPU만 분리한 조건이 아니라 APB master와 peripheral이 포함된 `rv32i_top` 구현 결과입니다. 두 프로젝트 모두 동일한 Basys3 FPGA와 100 MHz clock constraint를 사용했습니다.

## 시스템 구조

```text
rv32i_top
├─ instruction_mem
├─ rv32i_cpu
│  ├─ control_unit
│  └─ rv32i_datapath
├─ apb_master
├─ apb_dmem_slave
├─ apb_gpio_slave
├─ apb_fnd_slave
├─ apb_uart_slave
├─ gpio_triode
├─ fnd_hex4_driver
└─ uart_rx_tx
   ├─ uart_tx
   ├─ uart_rx
   └─ uart_fifo
```

- `rv32i_top`: RV32I CPU와 APB peripheral 전체를 연결하는 탑 모듈입니다.
- `rv32i_cpu`: 13-state Control Unit FSM과 Datapath를 묶어 multi-cycle instruction 실행 흐름을 구성합니다.
- `apb_master`: CPU memory access를 APB transaction으로 변환합니다.
- `apb_dmem_slave`: data memory 영역을 APB slave로 제공합니다.
- `apb_gpio_slave`: GPIO 입출력 register를 제공합니다.
- `apb_fnd_slave`: CPU가 쓴 값을 FND 표시로 연결합니다.
- `apb_uart_slave`: UART 송수신 register interface를 제공합니다.
- `uart_rx_tx`: UART line과 내부 bus data를 변환합니다.

## 검증 방식

- `rv32i_top_sim`을 통해 CPU와 APB peripheral 사이의 주소 decode, read/write 흐름을 확인할 수 있습니다.
