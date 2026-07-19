# Creates the Vivado project from scratch: run with
#   vivado -mode batch -source vivado/build.tcl
# from the repository root. Regenerates the project into vivado/project/,
# which is gitignored -- safe to delete and re-run any time.

set proj_name "kernel_filters_basys3"
set proj_dir  "./vivado/project"
set part      "xc7a35tcpg236-1"

create_project $proj_name $proj_dir -part $part -force

add_files -norecurse [glob ./src/*.sv]
add_files -norecurse ./sim/test_image.mem
set_property file_type {Memory Initialization Files} [get_files test_image.mem]

add_files -fileset sim_1 -norecurse [glob ./sim/tb_*.sv]
add_files -fileset sim_1 -norecurse [glob ./sim/*.mem]

add_files -fileset constrs_1 -norecurse ./constraints/basys3.xdc

set_property top top [current_fileset]
set_property top tb_top_smoke [get_filesets sim_1]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts "Project created at $proj_dir/$proj_name.xpr"
