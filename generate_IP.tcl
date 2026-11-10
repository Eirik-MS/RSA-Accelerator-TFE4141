cd [file dirname [file normalize [info script]]]

set origin_dir "."
#load procedures
source -notrace [file normalize "$origin_dir/procedures.tcl"]

safe_close_project

set IP_directory "${origin_dir}/RSA_accelerator/IP/"
set Project_directory "${origin_dir}/RSA_accelerator/RSA_accelerator/RSA_accelerator.xpr"
cd [file dirname [file normalize [info script]]]

#this was created by doing the steps and recording the necessarry tcl commands

open_project [file normalize $Project_directory]

# A primary clock on the packaged accelerator input must not redefine the
# processing-system clock when the IP is integrated into RSA_soc. Keep the
# standalone clock constraint for IP out-of-context runs only (UG1118).
set accelerator_clock_xdc [get_files -of_objects [get_filesets constrs_1] *PYNQ-Z1_C.xdc]
if {[llength $accelerator_clock_xdc] != 1} {
    error "Expected the accelerator's standalone clock XDC before packaging"
}
set_property USED_IN {synthesis implementation out_of_context} $accelerator_clock_xdc
ipx::package_project -root_dir [file normalize "${IP_directory}/"] -vendor xilinx.com -library user -taxonomy /UserIP -import_files -set_current false
ipx::unload_core [file normalize "${IP_directory}/component.xml"]
ipx::edit_ip_in_project -upgrade true -name tmp_edit_project -directory [file normalize "${IP_directory}/IP"] [file normalize "${IP_directory}/component.xml"]
update_compile_order -fileset sources_1
set_property core_revision 2 [ipx::current_core]
ipx::merge_project_changes hdl_parameters [ipx::current_core]
ipx::update_source_project_archive -component [ipx::current_core]
ipx::create_xgui_files [ipx::current_core]
ipx::update_checksums [ipx::current_core]
ipx::save_core [ipx::current_core]
ipx::move_temp_component_back -component [ipx::current_core]
close_project -delete

set ip_path_list [get_property ip_repo_paths [current_project]]
if {!([file normalize "${IP_directory}"] in $ip_path_list)} {
	lappend ip_path_list [file normalize "${IP_directory}"]
}
set_property ip_repo_paths $ip_path_list [current_project]
update_ip_catalog

safe_close_project