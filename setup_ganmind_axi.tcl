# -----------------------------------------------------------------------------
# setup_ganmind_axi.tcl
# -----------------------------------------------------------------------------
# Batch helper that creates a Vivado project targeting the AXI-wrapped GAN top.
# It pulls in every RTL file under Willthon/GANMIND/src, applies include dirs,
# sets gan_serial_axi_wrapper as the top, and then runs synth/impl/bitstream.
# You can edit PART or board preset as needed.
# -----------------------------------------------------------------------------

# User knobs -------------------------------------------------------------------
set project_name        "gan_axi_overlay"
set project_dir         [file normalize "D:/GANMIND/GANMIND/vivado_axi"]
set top_module          "gan_serial_axi_wrapper"
set target_part         "xc7z020clg400-1" ;# PYNQ-Z2 default
set enable_bitstream    true

# RTL roots (adjust if you relocate files)
set repo_root   [file normalize "D:/GANMIND/GANMIND/Willthon/GANMIND"]
set src_root    [file normalize "$repo_root/src"]

set include_dirs [list \
    "$src_root/top" \
    "$src_root/interfaces" \
    "$src_root/generator" \
    "$src_root/discriminator" \
    "$src_root/layers" \
    "$src_root/fifo" \
]

# Fresh project ----------------------------------------------------------------
if {[file exists $project_dir]} {
    puts "[INFO] Removing existing project dir $project_dir"
    file delete -force $project_dir
}
file mkdir $project_dir

create_project $project_name $project_dir -part $target_part -force
set_property target_language Verilog [current_project]

# Add HDL sources --------------------------------------------------------------
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

# Apply include directories so `include "..."` statements resolve
set_property include_dirs $include_dirs [get_filesets sources_1]

# Optional: add constraints here if you have them
# add_files -fileset constrs_1 $repo_root/constraints/gan_axi.xdc

# Synthesis/implementation -----------------------------------------------------
set_property top $top_module [current_project]
launch_runs synth_1
wait_on_run synth_1

if {$enable_bitstream} {
    launch_runs impl_1 -to_step write_bitstream
    wait_on_run impl_1

    # Export products for PYNQ overlay packaging
    write_bitstream -force $project_dir/${top_module}.bit
    write_hw_platform -fixed -include_bit -force \
        $project_dir/${top_module}.xsa
}

puts "[INFO] Flow complete. Project at $project_dir"
