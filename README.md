# RV32I APB Peripheral System

## 프로젝트 개요

RV32I CPU에 APB peripheral bus를 연결하고, GPIO/FND/UART 같은 주변장치를 memory-mapped 방식으로 확장한 SoC형 HDL 프로젝트입니다.

## 목표 동작

- RV32I CPU가 instruction을 실행하며 memory/peripheral 접근을 수행합니다.
- APB master가 주소 영역에 따라 peripheral transaction을 생성합니다.
- APB slave들이 GPIO, FND, UART, data memory 기능을 담당합니다.
- UART 송수신 및 FND 표시를 CPU 프로그램 흐름과 연결합니다.

## 기술 스택

| 구분 | 내용 |
| --- | --- |
| 핵심 개념 | RV32I, APB bus, memory-mapped I/O, GPIO, FND, UART, SoC peripheral |
| 사용 장비 | Basys3 FPGA 대상 설계, UART/FND/GPIO peripheral |
| 사용 언어 | SystemVerilog |
| 개발 도구 | Vivado, HDL simulation testbench |

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
- `apb_master`: CPU memory access를 APB transaction으로 변환합니다.
- `apb_dmem_slave`: data memory 영역을 APB slave로 제공합니다.
- `apb_gpio_slave`: GPIO 입출력 register를 제공합니다.
- `apb_fnd_slave`: CPU가 쓴 값을 FND 표시로 연결합니다.
- `apb_uart_slave`: UART 송수신 register interface를 제공합니다.
- `uart_rx_tx`: UART line과 내부 bus data를 변환합니다.

## 검증 방식

- `rv32i_top_sim`을 통해 CPU와 APB peripheral 사이의 주소 decode, read/write 흐름을 확인할 수 있습니다.
