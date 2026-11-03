from pathlib import Path
import re,hashlib,json,xml.etree.ElementTree as ET
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'output/board'
def read_native_options():
 base=ROOT/'fpga/sin12_hdmi/impl'
 paths={'synthesis_project':base/'gwsynthesis/sin12_hdmi_system.prj','pnr_command':base/'pnr/cmd.do','device_cfg':base/'pnr/device.cfg'}
 opts={x.get('type'):x.get('value') for x in ET.parse(paths['synthesis_project']).getroot().iter('Option')}
 args={m[1]:m[2].strip() for m in re.finditer(r'^-(\S+)([^\n]*)$',paths['pnr_command'].read_text(),re.M)}
 dev=dict(re.findall(r'^set (.+?) = (.+)$',paths['device_cfg'].read_text(),re.M))
 config={'Optimization_Goal':opts['opt_goal'].title(),'Max_Fanout':int(opts['max_fanout']),'Place_Option':args['place_option'],'Route_Option':args['route_option'],'Replicate_Resources':'replicate' in args,'Run_Timing_Driven':'timing' in args,'SSPI':dev['SSPI regular_io']=='true','JTAG':dev['JTAG regular_io']=='true','MSPI':dev['MSPI regular_io']=='true','USERCODE':dev['user_code'].replace('0x','')}
 report={'evidence':'Derived from actual Gowin generated synthesis project and PnR command, not requested Tcl labels; CLI clean build does not emit GUI process_config.json','config':config,'files':{k:{'path':str(p),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for k,p in paths.items()}}
 (OUT/'R20_NATIVE_OPTIONS.json').write_text(json.dumps(report,indent=2)+'\n')
 return config
if __name__=='__main__':print(json.dumps(read_native_options(),indent=2))
