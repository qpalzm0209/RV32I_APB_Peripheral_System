if {[llength $argv] < 1 || [llength $argv] > 3} {
    error "usage: compare_timing.tcl <single_cycle|multi_cycle> ?period_ns? ?cpu_ooc|top?"
}

set variant [lindex $argv 0]
if {$variant ni {single_cycle multi_cycle}} {
    error "unsupported variant: $variant"
}

set period_ns 10.000
if {[llength $argv] >= 2} {
    set period_ns [lindex $argv 1]
}
if {![string is double -strict $period_ns] || $period_ns <= 0.0} {
    error "period_ns must be a positive number: $period_ns"
}

set implementation_target cpu_ooc
if {[llength $argv] == 3} {
    set implementation_target [lindex $argv 2]
}
if {$implementation_target ni {cpu_ooc top}} {
    error "unsupported implementation target: $implementation_target"
}

set script_dir [file dirname [file normalize [info script]]]
set project_root [file dirname $script_dir]
set rtl_dir [file join $project_root $variant "rtl"]
if {$implementation_target eq "cpu_ooc"} {
    # Keep the historical output path for run_timing_comparison.ps1.
    set report_dir [file join $project_root ".reports" $variant]
} else {
    set report_dir [file join $project_root ".reports" "${variant}_top"]
}
file mkdir $report_dir

create_project -in_memory -part xc7a35tcpg236-1
set_property target_language Verilog [current_project]
set_property include_dirs [list $rtl_dir] [current_fileset]
read_verilog -sv [list \
    [file join $rtl_dir "rv32i_cpu.sv"] \
    [file join $rtl_dir "rv32i_datapath.sv"] \
    [file join $rtl_dir "instruction_mem.sv"] \
    [file join $rtl_dir "data_mem.sv"] \
    [file join $rtl_dir "rv32i_top.sv"]]

if {$implementation_target eq "top"} {
    # rv32i_top intentionally has no functional outputs. Without a synthesis
    # preservation constraint, Vivado removes the entire closed system before
    # placement because none of its state is externally observable.
    read_xdc [file join $script_dir "preserve_top.xdc"]
}

set original_dir [pwd]
cd $rtl_dir
if {$implementation_target eq "cpu_ooc"} {
    synth_design -rtl -top rv32i_top -part xc7a35tcpg236-1
    puts "PASS: $variant production top RTL elaboration"
    close_design

    synth_design -top rv32i_cpu -part xc7a35tcpg236-1 -mode out_of_context
} else {
    # Stay in rtl_dir while synthesizing so instruction_mem's relative
    # $readmemh path continues to resolve to riscv_prg.mem.
    synth_design -top rv32i_top -part xc7a35tcpg236-1
    puts "PASS: $variant production top RTL elaboration"
}
create_clock -name cpu_clk -period $period_ns [get_ports clk]
set_false_path -from [get_ports rst]

opt_design
place_design
route_design

report_utilization -file [file join $report_dir "utilization.rpt"]
report_timing_summary -delay_type max -max_paths 10 -report_unconstrained \
    -file [file join $report_dir "timing_summary.rpt"]

set worst_path [get_timing_paths -delay_type max -max_paths 1 -nworst 1]
if {[llength $worst_path] == 0} {
    error "No constrained setup timing path was found for $variant"
}

set summary_file [open [file join $report_dir "summary.txt"] "w"]
puts $summary_file "VARIANT=$variant"
puts $summary_file "TARGET=$implementation_target"
puts $summary_file "PERIOD_NS=[format %.3f $period_ns]"
puts $summary_file "WNS_NS=[get_property SLACK $worst_path]"
puts $summary_file "DATAPATH_DELAY_NS=[get_property DATAPATH_DELAY $worst_path]"
puts $summary_file "STARTPOINT=[get_property STARTPOINT_PIN $worst_path]"
puts $summary_file "ENDPOINT=[get_property ENDPOINT_PIN $worst_path]"
close $summary_file

cd $original_dir
puts "PASS: $variant routed timing report generated"
