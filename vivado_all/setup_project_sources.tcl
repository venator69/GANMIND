# -----------------------------------------------------------------------------
# setup_project_sources.tcl
# -----------------------------------------------------------------------------
# Usage:
#   vivado -mode batch -source vivado_all/setup_project_sources.tcl
#
# This helper script opens ganmind_all.xpr, verifies that critical RTL sources
# (such as pipelined_mac.v) are present, adds any missing weight/bias HEX files
# for $readmemh, and injects a HEX_DATA_ROOT define so RTL and Vivado agree on
# where the memories live. Run this once (or whenever new data files appear)
# before kicking off synthesis/implementation/analysis.
# -----------------------------------------------------------------------------

set script_dir   [file dirname [file normalize [info script]]]
set project_file [file join $script_dir ganmind_all.xpr]
set repo_root    [file normalize [file join $script_dir ..]]
set gan_dir      [file join $repo_root Willthon GANMIND]
set src_dir      [file join $gan_dir src]
set hex_dir      [file join $src_dir layers hex_data]

if {![file exists $project_file]} {
    error "Project file not found: $project_file"
}

if {![file isdirectory $src_dir]} {
    error "Cannot locate RTL directory: $src_dir"
}

open_project $project_file
set src_fs [get_filesets sources_1]

set added_any false
set defines_updated false

# Bring every hex file from src/layers/hex_data into the project so Vivado's
# out-of-context runs can satisfy $readmemh calls.
if {![file isdirectory $hex_dir]} {
    puts "WARN: Hex data directory not found at $hex_dir; skipping add_files"
} else {
    set hex_files [glob -nocomplain -directory $hex_dir *.hex]
    if {[llength $hex_files] == 0} {
        puts "WARN: No .hex files found under $hex_dir"
    } else {
        foreach hex_file $hex_files {
            set norm_hex [file normalize $hex_file]
            set proj_hex [string map {\\ /} $norm_hex]
            if {[llength [get_files -quiet $proj_hex]] == 0} {
                puts "INFO: Adding hex init file $proj_hex"
                add_files -fileset $src_fs $proj_hex
                set added_any true
            }
        }
    }

    # Keep RTL/Vivado aligned on the HEX_DATA_ROOT macro.
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
        set defines_updated true
    }
}

if {$added_any} {
    puts "INFO: Updating compile order"
    update_compile_order -fileset $src_fs
}

if {$added_any || $defines_updated} {
    puts "INFO: Saving project with updated sources/defines"
    save_project
} else {
    puts "INFO: Sources already up to date"
}

close_project -quiet
puts "INFO: setup_project_sources.tcl complete"
