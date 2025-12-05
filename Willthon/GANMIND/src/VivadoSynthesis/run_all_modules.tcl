#-----------------------------------------------------------------------------
# Vivado batch synthesis script for GANMIND modules
# Target device: xc7z020clg400-1 (PYNQ-Z2 class)
# Usage:
#   vivado -mode batch -source src/VivadoSynthesis/run_all_modules.tcl
# This will generate individual Vivado projects/checkpoints for each module
# under src/VivadoSynthesis/<module_name>/.
#-----------------------------------------------------------------------------

set part "xc7z020clg400-1"
set script_dir [file normalize [file dirname [info script]]]
set proj_root  [file normalize [file join $script_dir ".." ".."]]
set synth_root [file normalize $script_dir]

# Helper to normalize source paths relative to repo root
proc abs_sources {proj_root rel_list} {
    set result {}
    foreach rel $rel_list {
        lappend result [file normalize [file join $proj_root $rel]]
    }
    return $result
}

proc clean_and_create {path} {
    if {[file exists $path]} {
        file delete -force $path
    }
    file mkdir $path
}

proc stage_hex_data {proj_root proj_dir} {
    set src_hex [file normalize [file join $proj_root src layers hex_data]]
    if {![file isdirectory $src_hex]} {
        puts "[WARN] Hex data directory not found at $src_hex"
        return
    }

    set dst_layers [file join $proj_dir src layers]
    file mkdir $dst_layers

    set dst_hex [file join $dst_layers hex_data]
    if {[file exists $dst_hex]} {
        file delete -force $dst_hex
    }

    file copy -force $src_hex $dst_layers
    puts "[INFO] Mirrored hex data into $dst_hex"
}

proc synthesize_module {proj_root synth_root part module_spec} {
    array set spec $module_spec
    set name        $spec(name)
    set rel_sources $spec(sources)
    set abs_list    [abs_sources $proj_root $rel_sources]

    set out_dir  [file join $synth_root $name]
    set proj_dir [file join $out_dir "project"]

    puts "\n[INFO] ==== Synthesizing $name ===="
    puts "[INFO] Output directory : $out_dir"

    file mkdir $out_dir
    clean_and_create $proj_dir

    set proj_name "${name}_proj"
    create_project $proj_name $proj_dir -part $part -force > /dev/null

    # Ensure $readmemh("src/layers/hex_data/...") works even for per-module
    # out-of-context projects by mirroring the hex_data tree locally.
    stage_hex_data $proj_root $proj_dir

    # Also provide an absolute path override so $readmemh can locate data
    # regardless of Vivado's run directory.
    set fileset   [get_filesets sources_1]
    set hex_root  [string map {\\ /} [file normalize [file join $proj_root src layers hex_data]]]
    set hex_define "HEX_DATA_ROOT=\\\"$hex_root\\\""
    set existing_def [get_property verilog_define $fileset]
    if {$existing_def eq ""} {
        set_property verilog_define [list $hex_define] $fileset
    } else {
        lappend existing_def $hex_define
        set_property verilog_define $existing_def $fileset
    }

    foreach src $abs_list {
        if {![file exists $src]} {
            puts stderr "[ERROR] Missing source file $src"
            exit 1
        }
        puts "[INFO] Adding $src"
        add_files -fileset sources_1 $src
    }

    set_property top $name [get_filesets sources_1]
    update_compile_order -fileset sources_1

    launch_runs synth_1 -jobs 4
    wait_on_run synth_1

    open_run synth_1

    set dcp_path   [file join $out_dir "${name}_synth.dcp"]
    set util_rpt   [file join $out_dir "${name}_util.rpt"]
    set timing_rpt [file join $out_dir "${name}_timing.rpt"]

    write_checkpoint -force $dcp_path
    report_utilization    -file $util_rpt
    report_timing_summary -file $timing_rpt

    close_design
    close_project

    puts "[INFO] Completed $name"
}

# Ordered module plan (layers -> interfaces -> fifo -> pipelines -> top)
set module_plan {
    {name layer1_generator      sources {src/layers/layer1_generator.v src/layers/pipelined_mac.v}}
    {name layer2_generator      sources {src/layers/layer2_generator.v src/layers/pipelined_mac.v}}
    {name layer3_generator      sources {src/layers/layer3_generator.v src/layers/pipelined_mac.v}}
    {name layer1_discriminator  sources {src/layers/layer1_discriminator.v src/layers/pipelined_mac.v}}
    {name layer2_discriminator  sources {src/layers/layer2_discriminator.v src/layers/pipelined_mac.v}}
    {name layer3_discriminator  sources {src/layers/layer3_discriminator.v src/layers/pipelined_mac.v}}
    {name pipelined_mac         sources {src/layers/pipelined_mac.v}}
    {name pixel_serial_loader   sources {src/interfaces/pixel_serial_loader.v}}
    {name frame_sampler         sources {src/interfaces/frame_sampler.v src/fifo/sync_fifo.v}}
    {name vector_expander       sources {src/interfaces/vector_expander.v}}
    {name vector_sigmoid        sources {src/interfaces/vector_sigmoid.v src/interfaces/sigmoid_approx.v}}
    {name sigmoid_approx        sources {src/interfaces/sigmoid_approx.v}}
    {name vector_upsampler      sources {src/interfaces/vector_upsampler.v}}
    {name sync_fifo             sources {src/fifo/sync_fifo.v}}
    {name seed_lfsr_bank        sources {src/generator/seed_lfsr_bank.v}}
    {name generator_pipeline    sources {src/generator/generator_pipeline.v src/fifo/sync_fifo.v src/layers/pipelined_mac.v src/layers/layer1_generator.v src/layers/layer2_generator.v src/layers/layer3_generator.v}}
    {name discriminator_pipeline sources {src/discriminator/discriminator_pipeline.v src/fifo/sync_fifo.v src/layers/pipelined_mac.v src/layers/layer1_discriminator.v src/layers/layer2_discriminator.v src/layers/layer3_discriminator.v}}
    {name gan_serial_top        sources {src/top/gan_serial_top.v src/generator/generator_pipeline.v src/discriminator/discriminator_pipeline.v src/generator/seed_lfsr_bank.v src/interfaces/pixel_serial_loader.v src/interfaces/frame_sampler.v src/interfaces/vector_expander.v src/interfaces/vector_sigmoid.v src/interfaces/sigmoid_approx.v src/interfaces/vector_upsampler.v src/fifo/sync_fifo.v src/layers/pipelined_mac.v src/layers/layer1_generator.v src/layers/layer2_generator.v src/layers/layer3_generator.v src/layers/layer1_discriminator.v src/layers/layer2_discriminator.v src/layers/layer3_discriminator.v}}
}

foreach module $module_plan {
    synthesize_module $proj_root $synth_root $part $module
}

puts "\n[INFO] All module syntheses completed."
