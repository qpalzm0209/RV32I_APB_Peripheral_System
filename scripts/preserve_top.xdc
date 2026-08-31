# rv32i_top is a closed system with only clk/rst inputs. Preserve its three
# functional blocks so synthesis cannot discard the design as unobservable.
set_property DONT_TOUCH true [get_cells -hierarchical {U_INSTRUCTION_MEM U_RV32I_CPU U_DATA_MEM}]
