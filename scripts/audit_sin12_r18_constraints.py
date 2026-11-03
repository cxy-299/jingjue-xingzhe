"""Reproducible R18 narrow-exception audit; no external-IO signoff claim."""
from pathlib import Path
import hashlib,json,re
from verify_sin12_r18_mapped_tof import verify_current_netlist
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/board'
def main():
    digest=verify_current_netlist()
    paths={n:ROOT/'fpga/sin12_hdmi'/n for n in ('sin12_hdmi_system.sdc','sin12_hdmi_system.cst','impl/pnr/sin12_hdmi_system.tr','impl/pnr/device.cfg','impl/pnr/process_config.json','impl/gwsynthesis/sin12_hdmi_system.vg')}
    text=paths['impl/pnr/sin12_hdmi_system.tr'].read_text()
    section=text[text.rindex('3.8 Timing Constraints Report'):]
    rows=[dict(kind=m[1],state=m[2],command=m[3].strip()) for m in re.finditer(r'^\s*(TC_\w+)\s+(\w+)\s+(.+)$',section,re.M)]
    assert len(rows)==16 and all(r['state']=='Actived' for r in rows)
    sdc=paths['sin12_hdmi_system.sdc'].read_text()
    commands=[l.strip() for l in sdc.splitlines() if l.strip() and not l.lstrip().startswith('#')]
    assert sorted(commands)==sorted(r['command'] for r in rows)
    false_paths=[r['command'] for r in rows if r['kind']=='TC_FALSE_PATH']
    assert set(false_paths)=={
      'set_false_path -to [get_pins {u_camera/u_startup/u_serial_gate/CEN}]',
      'set_false_path -to [get_pins {u_camera/pixel_release_meta*/CLEAR u_camera/pixel_release_sync*/CLEAR}]'}
    endpoints=[f'u_camera/u_dvi/g_channel[{i}].u_serial/u_serializer/RESET' for i in range(4)]
    multi=[r['command'] for r in rows if r['kind']=='TC_MULTICYCLE']
    expected_prefix='set_multicycle_path -through [get_pins {'+' '.join(endpoints)+'}] -to [get_clocks {camera_serial}] '
    assert set(multi)=={expected_prefix+'-setup -end 16',expected_prefix+'-hold -end 15'}
    vg=paths['impl/gwsynthesis/sin12_hdmi_system.vg'].read_text()
    blocks=list(re.finditer(r'\bDFFCE\s+(pixel_release_(?:meta|sync)\S*)\s*\(([\s\S]*?)\);',vg))
    assert len(blocks)==2
    cells={m[1]:dict(re.findall(r'\.(\w+)\(([^)]*)\)',m[2])) for m in blocks}
    assert set(cells)=={'pixel_release_meta_s1','pixel_release_sync_s1'}
    assert cells['pixel_release_meta_s1']==dict(Q='pixel_release_meta',D='VCC',CLK='pixel_clk',CLEAR='reset_hold',CE='VCC')
    assert cells['pixel_release_sync_s1']==dict(Q='pixel_release_sync',D='pixel_release_meta',CLK='pixel_clk',CLEAR='reset_hold',CE='VCC')
    # A downstream timed CLEAR and BSRAM RESET must remain present in reports.
    assert 'u_camera/pixel_release_sync_s1/Q' in text
    assert re.search(r'u_camera/pixel_release_sync_s1/Q[^\n]+u_camera/[^\n]+/CLEAR',text)
    assert re.search(r'u_camera/pixel_release_sync_s1/Q[^\n]+u_camera/[^\n]+/RESET\[0\]',text)
    io_delays=[c for c in commands if c.startswith(('set_input_delay','set_output_delay'))]
    assert not io_delays  # Explicit limitation, NOT proof that IO timing is met.
    config_path=ROOT/'fpga/sin12_hdmi/impl/sin12_hdmi_system_process_config.json'
    paths.pop('impl/pnr/process_config.json')
    paths['impl/sin12_hdmi_system_process_config.json']=config_path
    config=json.loads(config_path.read_text(encoding='utf-8-sig'))
    assert config['Replicate_Resources'] is True and config['Route_Option']=='2' and config['Run_Timing_Driven'] is True
    assert config['Optimization_Goal'].lower()=='timing' and config['Place_Option']=='1'
    # The previous legacy-maxfan request was not reflected by native config;
    # withdrawn, not silently counted as effective fanout replication.
    assert int(config['Max_Fanout'])==1000
    assert config['SSPI'] is True and config['JTAG'] is False and config['MSPI'] is False
    assert '0x534E3252' in paths['impl/pnr/device.cfg'].read_text()
    inspection=json.loads((OUT/'SIN12_R18_TIMING_INSPECTION_2026-11-01.json').read_text())
    assert inspection['internal_sta_checks_pass'] and all(inspection['checks'].values())
    report=dict(passed=True,netlist_sha256=digest,hardware_access=False,active_constraints=rows,
      pixel_async_false_path_endpoints=['u_camera/'+n+'/CLEAR' for n in sorted(cells)],pixel_register_connections=cells,
      serializer_multicycle_endpoints=endpoints,serializer_setup_cycles=16,serializer_hold_cycles=15,
      downstream_pixel_clear_and_bsram_reset_still_reported=True,external_io_delay_constraints=io_delays,
      external_io_timing_signed_off=False,unconstrained_io_note='SDC provides no board input/output delay budgets; absence of an unconstrained-IO table is not coverage. External DVP/other board IO timing remains unsigned.',
      process_config={k:config[k] for k in ('Replicate_Resources','Place_Option','Route_Option','Run_Timing_Driven','Optimization_Goal','Max_Fanout','SSPI','JTAG','MSPI','USERCODE')},
      source_hashes={n:hashlib.sha256(p.read_bytes()).hexdigest() for n,p in paths.items()},
      limitations=inspection['limitations'])
    (OUT/'SIN12_R18_CONSTRAINT_AUDIT.json').write_text(json.dumps(report,indent=2))
    print('R18 narrow exception audit PASS:16 active constraints,2 synchronizer CLEAR endpoints; external IO NOT signed off')
if __name__=='__main__':main()
