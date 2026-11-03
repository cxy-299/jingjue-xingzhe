create_clock -name clk_50m -period 20.000 [get_ports {clk_50m_i}]
create_clock -name camera_pclk -period 13.333 [get_ports {camera_pclk}]
create_generated_clock -name camera_serial_raw -source [get_ports {clk_50m_i}] -multiply_by 15 -divide_by 2 [get_pins {u_camera/u_pll/u_pll_0/PLLA_inst/CLKOUT0}]
# DHCE is a clock boundary in this tool. Explicitly propagate the 375 MHz
# clock to its output instead of leaving the OSER10 FCLK unclocked.
create_generated_clock -name camera_serial -source [get_pins {u_camera/u_pll/u_pll_0/PLLA_inst/CLKOUT0}] -divide_by 1 [get_pins {u_camera/u_startup/u_serial_gate/CLKOUT}]
create_generated_clock -name camera_pixel -source [get_pins {u_camera/u_startup/u_serial_gate/CLKOUT}] -divide_by 5 [get_pins {u_camera/u_pixel_div/CLKOUT}]
create_generated_clock -name camera_xclk -source [get_ports {clk_50m_i}] -divide_by 2 [get_pins {u_camera/u_pll/u_pll_0/PLLA_inst/CLKOUT1}]
set_clock_groups -asynchronous -group [get_clocks {camera_pclk}] -group [get_clocks {clk_50m camera_serial_raw camera_serial camera_pixel camera_xclk}]
# DHCE holds FCLK/PCLK stopped for >=160 ns after RESET release. Budget only
# 16 FCLK cycles (~42 ns) for the startup-only RESET route, well inside the
# proven quiet window. These endpoints remain timed (no false path). No
# pixel data path, running clock period, or car-control path is relaxed.
set_multicycle_path -through [get_pins {u_camera/u_dvi/g_channel[0].u_serial/u_serializer/RESET u_camera/u_dvi/g_channel[1].u_serial/u_serializer/RESET u_camera/u_dvi/g_channel[2].u_serial/u_serializer/RESET u_camera/u_dvi/g_channel[3].u_serial/u_serializer/RESET}] -to [get_clocks {camera_serial}] -setup -end 16
set_multicycle_path -through [get_pins {u_camera/u_dvi/g_channel[0].u_serial/u_serializer/RESET u_camera/u_dvi/g_channel[1].u_serial/u_serializer/RESET u_camera/u_dvi/g_channel[2].u_serial/u_serializer/RESET u_camera/u_dvi/g_channel[3].u_serial/u_serializer/RESET}] -to [get_clocks {camera_serial}] -hold -end 15
# DHCE's active-low CEN is an asynchronous control input, with four falling-
# edge synchronization stages in the official primitive. Exempt that first
# asynchronous sampling endpoint only, not any data/RESET/clock path.
set_false_path -to [get_pins {u_camera/u_startup/u_serial_gate/CEN}]
report_timing -recovery -to [get_pins {u_camera/u_dvi/g_channel[0].u_serial/u_serializer/RESET u_camera/u_dvi/g_channel[1].u_serial/u_serializer/RESET u_camera/u_dvi/g_channel[2].u_serial/u_serializer/RESET u_camera/u_dvi/g_channel[3].u_serial/u_serializer/RESET}] -max_paths 24 -max_common_paths 3
report_timing -removal -to [get_pins {u_camera/u_dvi/g_channel[0].u_serial/u_serializer/RESET u_camera/u_dvi/g_channel[1].u_serial/u_serializer/RESET u_camera/u_dvi/g_channel[2].u_serial/u_serializer/RESET u_camera/u_dvi/g_channel[3].u_serial/u_serializer/RESET}] -max_paths 24 -max_common_paths 3
report_min_pulse_width -nworst 100 -detail

# Global recovery/removal audit: summary counts may include async endpoints
# outside the four explicitly audited serializers. Do not hide those paths.
report_timing -recovery -max_paths 200 -max_common_paths 3
report_timing -removal -max_paths 200 -max_common_paths 3

# Only asynchronous inputs of the pixel reset synchronizer are exempt.
# Meta D -> sync D and sync Q -> all pixel/encoder CLEAR/RESET remain timed.
set_false_path -to [get_pins {u_camera/pixel_release_meta*/CLEAR u_camera/pixel_release_sync*/CLEAR}]
