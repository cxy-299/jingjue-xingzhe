// ACG720 板载 50 MHz 时钟；此工程仅用于通信/规划验收。
create_clock -name clk_50m -period 20 [get_ports {clk_50m_i}]
