if {[llength $argv] != 1} {
    error "usage: compare_timing.tcl <single_cycle|multi_cycle>"
}

set variant [lindex $argv 0]
if {$variant ni {single_cycle multi_cycle}} {
    error "unsupported variant: $variant"
}

set script_dir [file dirname [file normalize [info script]]]
set project_root [file dirname $script_dir]
set rtl_dir [file join $project_root $variant "rtl"]
set report_dir [file join $project_root ".reports" $variant]
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

set original_dir [pwd]
cd $rtl_dir
synth_design -rtl -top rv32i_top -part xc7a35tcpg236-1
puts "PASS: $variant production top RTL elaboration"
close_design

synth_design -top rv32i_cpu -part xc7a35tcpg236-1 -mode out_of_context
create_clock -name cpu_clk -period 10.000 [get_ports clk]
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
puts $summary_file "WNS_NS=[get_property SLACK $worst_path]"
puts $summary_file "DATAPATH_DELAY_NS=[get_property DATAPATH_DELAY $worst_path]"
puts $summary_file "STARTPOINT=[get_property STARTPOINT_PIN $worst_path]"
puts $summary_file "ENDPOINT=[get_property ENDPOINT_PIN $worst_path]"
close $summary_file

cd $original_dir
puts "PASS: $variant routed timing report generated"
