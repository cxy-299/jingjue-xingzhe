"""Configure the existing Pi USB link for SIN9 without changing camera/model."""
import argparse
from pathlib import Path
import shutil
import yaml


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--config',default='config/config-pi.yaml')
    args=parser.parse_args()
    path=Path(args.config)
    cfg=yaml.safe_load(path.read_text(encoding='utf-8'))
    if not isinstance(cfg,dict) or not isinstance(cfg.get('serial',{}),dict):
        raise SystemExit('Invalid config mapping; no changes written')
    backup=path.with_name(path.name+'.before-sin9')
    if not backup.exists():
        shutil.copy2(path,backup)
    serial=cfg.setdefault('serial',{})
    serial.update(enabled=True,baudrate=115200,protocol='locked_target_v1',motion_commands_enabled=False)
    serial.setdefault('port','auto_usb_ch340')
    cfg.setdefault('navigation',{})['goal_tx_enabled']=False
    path.write_text(yaml.safe_dump(cfg,allow_unicode=True,sort_keys=False),encoding='utf-8')
    print('SIN9 configured: USB 115200, locked-target frames only; legacy ASCII disabled.')
    print('Backup:',backup)


if __name__=='__main__':
    main()
