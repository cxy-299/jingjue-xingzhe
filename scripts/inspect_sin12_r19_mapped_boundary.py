"""Read actual parent reset producer and coordinate bits before cone simulation."""
import re,json
from pathlib import Path
from verify_sin12_r19_mapped_tof import verify_current_netlist
ROOT=Path(__file__).resolve().parents[1]
def inspect_boundary():
    digest=verify_current_netlist()
    vg=(ROOT/'fpga/sin12_hdmi/impl/gwsynthesis/sin12_hdmi_system.vg').read_text()
    parent=re.search(r'\bmodule\s+acg720_motor_bt_drive\b[\s\S]*?endmodule',vg)[0]
    invs=[]
    for m in re.finditer(r'\bINV\s+(\S+)\s*\(([\s\S]*?)\);',parent):
        ports=dict(re.findall(r'\.(\w+)\(([^)]*)\)',m[2]))
        if ports.get('I')=='key_s0_n_i_d':invs.append((m[1],ports['O']))
    assert len(invs)==1,invs
    raw_key_inverter,raw_key_inverse=invs[0]
    guard=re.search(r'\bautonomous_nav_guard\s+(\S+)\s*\(([\s\S]*?)\);',parent)
    assert guard
    ports=dict(re.findall(r'\.([^\s(]+)\(([^)]*)\)',guard[2]))
    child=re.search(r'\bmodule\s+autonomous_nav_guard\b[\s\S]*?endmodule',vg)[0]
    clear_signals=set(re.findall(r'\.CLEAR\(([^)]*)\)',child))
    # Identify the actual child CLEAR input, then follow its real parent
    # connection and producer. It need not equal a raw-key inverter output.
    reset_ports=[n for n in ports if n in clear_signals and re.search(r'input\s+'+re.escape(n)+r';',child)]
    assert len(reset_ports)==1,reset_ports
    reset=ports[reset_ports[0]]
    producer=re.search(r'\bmodule\s+sensor_task1_3_core\b[\s\S]*?endmodule',vg)[0]
    sensor_instance=re.search(r'\bsensor_task1_3_core\s+(\S+)\s*\(([\s\S]*?)\);',parent)
    sensor_ports=dict(re.findall(r'\.([^\s(]+)\(([^)]*)\)',sensor_instance[2]))
    output_ports=[n for n,v in sensor_ports.items() if v==reset and re.search(r'output\s+'+re.escape(n)+r';',producer)]
    assert len(output_ports)==1,output_ports
    lut=[m for m in re.finditer(r'\bLUT2\s+(\S+)\s*\(([\s\S]*?)\);',producer)
         if dict(re.findall(r'\.(\w+)\(([^)]*)\)',m[2])).get('F')==output_ports[0]]
    assert len(lut)==1
    lut_ports=dict(re.findall(r'\.(\w+)\(([^)]*)\)',lut[0][2]))
    init=re.search(r'defparam\s+'+re.escape(lut[0][1])+r"\.INIT=4'h([0-9A-Fa-f]);",producer)[1]
    assert init=='7' and lut_ports['I0']=='led_o_d[1]' and lut_ports['I1']=='key_s0_n_i_d'
    coords={n:sorted(set(int(b) for b in re.findall(r'\b'+n+r'\[(\d+)\]',parent))) for n in ('auto_x','auto_y','auto_ox','auto_oy')}
    assert all(v==[0,1,2,3,4,7] for v in coords.values()),coords
    return dict(netlist_sha256=digest,raw_key_inverter=raw_key_inverter,raw_key_inverse=raw_key_inverse,
        reset_producer_instance=sensor_instance[1],reset_lut=lut[0][1],reset_lut_init=init,
        reset_lut_inputs=lut_ports,reset_signal=reset,reset_includes_startup_ready=True,
        key_input='key_s0_n_i_d',active_high_clear=True,guard_instance=guard[1],guard_reset_port=reset_ports[0],
        coordinate_observed_bits=coords,unobserved_bits=[5,6],invented_inputs=False)
if __name__=='__main__':
    r=inspect_boundary();(ROOT/'output/board/R19_MAPPED_BOUNDARY_INSPECTION.json').write_text(json.dumps(r,indent=2))
    print(json.dumps(r,indent=2))
