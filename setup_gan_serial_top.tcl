# -----------------------------------------------------------------------------
# setup_gan_serial_top.tcl
# -----------------------------------------------------------------------------
# Batch helper to build the legacy gan_serial_top (non-AXI) design.
# Uses absolute paths and a portable recursive file collector (no -recursive glob).
# -----------------------------------------------------------------------------

set project_name "gan_serial_top"
set project_dir  [file normalize "D:/GANMIND/GANMIND/vivado_pynq"]
set target_part  "xc7z020clg400-1"
set top_module   "gan_serial_top"

set repo_root [file normalize "D:/GANMIND/GANMIND/Willthon/GANMIND"]
set src_root  [file normalize "$repo_root/src"]

set include_dirs [list \
    "$src_root/top" \
    "$src_root/interfaces" \
    "$src_root/generator" \
    "$src_root/discriminator" \
    "$src_root/layers" \
    "$src_root/fifo" \
]

if {[file exists $project_dir]} {
    file delete -force $project_dir
}
file mkdir $project_dir

create_project $project_name $project_dir -part $target_part -force
set_property target_language Verilog [current_project]

proc collect_verilog {root} {
    set out {}
    foreach item [glob -nocomplain -directory $root *] {
        if {[file isdirectory $item]} {
            set out [concat $out [collect_verilog $item]]
        } elseif {[string match *.v [file tail $item]]} {
            lappend out $item
        }
    }
    return $out
}

set verilog_files [collect_verilog $src_root]
foreach abs_path $verilog_files {
    add_files -fileset sources_1 $abs_path
}
update_compile_order -fileset sources_1
set_property include_dirs $include_dirs [get_filesets sources_1]

set_property top $top_module [current_project]
launch_runs synth_1
wait_on_run synth_1

puts "[INFO] Synthesis complete for $top_module at $project_dir"
