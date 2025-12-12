# -----------------------------------------------------------------------------
# analyze_timing.tcl
# -----------------------------------------------------------------------------
# Usage (from repo root):
#   vivado -mode batch -source vivado_all/analyze_timing.tcl \
#          -tclargs -clock_period 10.0             # default 100 MHz check
#   vivado -mode batch -source vivado_all/analyze_timing.tcl \
#          -tclargs -clock_period 12.5             # relaxed 80 MHz check
#   vivado -mode batch -source vivado_all/analyze_timing.tcl -tclargs -reuse_runs
#
# The script re-opens ganmind_all.xpr, optionally re-launches synth/impl,
# applies a clock-period override for reporting, and emits:
#   * report_timing  (max 20 paths, path_type summary)
#   * report_qor_suggestions (Vivado auto pipeline hints)
#   * report_timing_summary for quick WNS/TNS snapshot
# Reports are dropped into vivado_all/reports/<timestamp>.
# -----------------------------------------------------------------------------

# Basic argument parsing ------------------------------------------------------
set clock_period_ns 10.0      ;# default requirement
set rerun true                ;# relaunch synth/impl unless -reuse_runs set

set idx 0
while {$idx < [llength $argv]} {
    set flag [lindex $argv $idx]
    switch -- $flag {
        -clock_period {
            incr idx
            if {$idx >= [llength $argv]} {
                error "-clock_period expects a numeric argument"
            }
            set clock_period_ns [lindex $argv $idx]
        }
        -reuse_runs {
            set rerun false
        }
        default {
            error "Unknown argument: $flag"
        }
    }
    incr idx
}

# Resolve paths ---------------------------------------------------------------
set script_dir    [file dirname [file normalize [info script]]]
set project_file  [file join $script_dir ganmind_all.xpr]
set report_root   [file join $script_dir reports]
file mkdir $report_root

if {![file exists $project_file]} {
    error "Cannot find project file: $project_file"
}

puts "INFO: Opening project $project_file"
open_project $project_file

# Ensure Vivado sees the weight/bias hex files and knows where HEX_DATA_ROOT lives
set repo_root   [file normalize [file join $script_dir ..]]
set gan_src_dir [file join $repo_root Willthon GANMIND]
set hex_dir     [file join $gan_src_dir src layers hex_data]
set src_fs      [get_filesets sources_1]

if {![file isdirectory $hex_dir]} {
    puts "WARN: Hex data directory not found at $hex_dir; $readmemh will likely fail"
} else {
    set hex_files [glob -nocomplain -directory $hex_dir *.hex]
    if {[llength $hex_files] == 0} {
        puts "WARN: No .hex files found under $hex_dir; $readmemh will likely fail"
    } else {
        set added_hex false
        foreach hex_file $hex_files {
            set norm_hex [file normalize $hex_file]
            set proj_hex [string map {\\ /} $norm_hex]
            if {[llength [get_files -quiet $proj_hex]] == 0} {
                puts "INFO: Adding hex init file $proj_hex to sources_1"
                add_files -fileset $src_fs $proj_hex
                set added_hex true
            }
        }
        if {$added_hex} {
            update_compile_order -fileset $src_fs
        }
    }

    set hex_define_path [string map {\\ /} [file normalize $hex_dir]]
    set hex_define [format {HEX_DATA_ROOT="%s"} $hex_define_path]
    set current_defines [get_property verilog_define $src_fs]
    if {$current_defines eq ""} {
        set current_defines {}
    }
    if {[lsearch -exact $current_defines $hex_define] < 0} {
        puts "INFO: Injecting HEX_DATA_ROOT define => $hex_define_path"
        lappend current_defines $hex_define
        set_property verilog_define $current_defines $src_fs
    }
}

# Optionally re-run synth/impl ------------------------------------------------
if {$rerun} {
    puts "INFO: Resetting runs"
    catch {reset_run impl_1}
    catch {reset_run synth_1}

    puts "INFO: Launching synth_1"
    launch_runs synth_1
    wait_on_run synth_1

    puts "INFO: Launching impl_1 (route_design)"
    launch_runs impl_1 -to_step route_design
    wait_on_run impl_1
} else {
    puts "INFO: -reuse_runs set; skipping new synth/impl"
}

set impl_run [get_runs impl_1]
if {[string equal $impl_run ""]} {
    error "impl_1 run not present in project"
}

puts "INFO: Opening impl_1 results"
open_run $impl_run

# Override clock period for reporting if requested ---------------------------
if {$clock_period_ns > 0} {
    set clk_obj [get_clocks axi_clk -quiet]
    if {[llength $clk_obj] == 0} {
        puts "WARN: Clock 'axi_clk' not found; skipping period override"
    } else {
        set current_period [get_property PERIOD [lindex $clk_obj 0]]
        if {[expr {abs($current_period - $clock_period_ns)}] > 0.0001} {
            puts "INFO: Re-creating axi_clk with period $clock_period_ns ns for reports"
            remove_clocks $clk_obj
            set clk_ports [get_ports axi_aclk -quiet]
            if {[llength $clk_ports] == 0} {
                puts "WARN: Port axi_aclk not found; cannot recreate clock"
            } else {
                create_clock -name axi_clk -period $clock_period_ns $clk_ports
            }
        } else {
            puts "INFO: axi_clk already at $clock_period_ns ns"
        }
    }
}

# Report generation -----------------------------------------------------------
set timestamp   [clock format [clock seconds] -gmt 0 -format "%Y%m%d_%H%M%SZ"]
set tag         [format "period%.2f" $clock_period_ns]
set run_folder  [file join $report_root ${timestamp}_$tag]
file mkdir $run_folder

set timing_file   [file join $run_folder timing_paths.rpt]
set summary_file  [file join $run_folder timing_summary.rpt]
set qor_file      [file join $run_folder qor_suggestions.rpt]

puts "INFO: Writing $timing_file"
report_timing -max_paths 20 -path_type summary -sort_by group -file $timing_file

puts "INFO: Writing $summary_file"
report_timing_summary -file $summary_file

puts "INFO: Writing $qor_file"
report_qor_suggestions -name ganmind_qor -file $qor_file

puts "INFO: Reports available under $run_folder"
close_project -quiet
puts "INFO: Done"
