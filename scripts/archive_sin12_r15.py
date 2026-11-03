"""Verify and independently archive the R15 offline candidate; no hardware I/O."""
from pathlib import Path
from datetime import datetime
import hashlib
import json
import shutil
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "output/board"

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def load(name):
    return json.loads((OUT / name).read_text(encoding="utf-8-sig"))

def verify_manifest(manifest):
    bad = [p for p, h in manifest.items() if sha(ROOT / p) != h]
    assert not bad, bad

def main():
    hardware = load("sin12_hdmi_r15_build_sources.json")
    software = load("sin12_hdmi_r15_software_sources.json")
    assert len(hardware) == 57 and len(software) == 45
    verify_manifest(hardware)
    verify_manifest(software)
    assert (OUT / "sin12_hdmi_r15_build_exit.txt").read_text().strip() == "0"
    timing = load("SIN12_R15_TIMING_INSPECTION_2026-10-31.json")
    assert timing["internal_sta_checks_pass"] and all(timing["checks"].values())
    impl = ROOT / "fpga/sin12_hdmi/impl"
    pnr = impl / "pnr"
    for name, record in timing["files"].items():
        assert sha(pnr / name) == record["sha256"], name
    net = impl / "gwsynthesis/sin12_hdmi_system.vg"
    net_hash = sha(net)
    assert net_hash == "66d6c2b9b5f62ec57a61332d4712347133397933720a96067d9de06f93fcb5f3"
    maps = {k: load(f"SIN12_R15_MAPPED_{suffix}_VALIDATION.json") for k, suffix in
            (("tof", "TOF"), ("target", "TARGET"), ("recovery_search", "RECOVERY_SEARCH"))}
    assert all(r["passed"] and r["netlist_sha256"] == net_hash and not r["internal_forces"] for r in maps.values())
    assert maps["tof"]["checks"] == 91 and maps["target"]["vectors"] == 2172
    recovery = maps["recovery_search"]
    assert recovery["primitive_count"] == 3164 and not recovery["altered_mapped_constants"]
    assert len(recovery["scenario_markers"]) == 6
    log = (OUT / "r15_full_system_mapped_recovery_second_vg_retry.log").read_text()
    assert all(marker in log for marker in recovery["scenario_markers"])
    assert "Errors: 0, Warnings: 0" in log and "Fatal:" not in log
    wrapper = ROOT / "tmp/sin12_r15_mapped_recovery/mapped.v"
    assert sha(wrapper) == recovery["mapped_wrapper_sha256"]
    assert sha(ROOT / "fpga/motor_bt_drive/tb_sin12_r15_mapped_recovery.sv") == recovery["testbench_sha256"]
    xml = ET.parse(OUT / "r15_600ms_software_20261031.xml").getroot()
    suite = xml if xml.tag == "testsuite" else xml.find("testsuite")
    assert suite is not None and int(suite.attrib["tests"]) == 88
    assert all(int(suite.attrib[k]) == 0 for k in ("errors", "failures", "skipped"))
    tk = load("r15_console_validation.json")["tests"]
    assert len(tk) == 98 and all(t["passed"] and not t["skipped"] for t in tk)
    rtl_logs = ["r15_reacquire_600ms_20261031.log", "r15_nav_evidence_corrected_20261031.log",
                "r15_route_pipeline_boundary_20261031.log", "r15_full_route_pipe_20261031.log",
                "r15_uart_search_20261031.log"]
    for name in rtl_logs:
        text = (OUT / name).read_text()
        assert "PASS" in text and "Errors: 0, Warnings: 0" in text and "Fatal:" not in text, name
    stamp = datetime.fromtimestamp((pnr / "sin12_hdmi_system.fs").stat().st_mtime).strftime("%Y%m%d_%H%M%S")
    archive = OUT / f"sin12_hdmi_r15_{stamp}"
    if archive.exists():
        raise FileExistsError(f"Preserve existing archive: {archive}")
    report = dict(candidate="SIN12 R15", usercode="534E324F", firmware="K0F", map_id="2613",
                  archive=str(archive), verified_at_local=datetime.now().isoformat(),
                  hardware_source_count=57, software_source_count=45, source_mismatches=[],
                  netlist_sha256=net_hash, fs_sha256=sha(pnr / "sin12_hdmi_system.fs"),
                  internal_sta_checks_pass=True, setup_violations=0, hold_violations=0,
                  tables=timing["tables"], clocks=timing["clocks"], tns=timing["tns"],
                  fmax_mhz=timing["fmax_mhz"], resources=timing["resources"], files=timing["files"],
                  minimum_setup_slack_ns=0.065, margin_note="Positive but only 65ps; not a large-margin or vehicle validation claim.",
                  manual_audit=dict(active_constraints=16, pixel_clear_exception_endpoints=2,
                      final_pixel_sync_q_paths_still_timed=True, serializer_reset_mcp_setup_hold=[16,15],
                      replicate_resources=True, route_option=2, timing_driven=True,
                      sspi_as_gpio=True, jtag_as_gpio=False, mspi_as_gpio=False,
                      external_io_timing_signed=False),
                  full_external_timing_signoff=False, limitations=timing["limitations"],
                  mapped={k: {key:r.get(key) for key in ("passed", "netlist_sha256", "checks", "vectors",
                      "primitive_count", "internal_forces", "altered_mapped_constants", "scenario_markers", "scope",
                      "search_timing_scope")} for k,r in maps.items()},
                  software_tests=dict(passed=88, failed=0, skipped=0), isolated_tk=dict(passed=98, failed=0, skipped=0),
                  hardware_actions=dict(accessed=False, sram_downloaded=False, flash_written=False,
                      serial_controlled=False, motors_or_power_controlled=False), pi_modified_or_restarted=False,
                  historical_baseline="Recorded Flash R12/K0C; SRAM R14/K0E. Historical record only, not current readback.",
                  build_history=["First new VG: 477 setup violations, independent failed archive retained",
                      "Second fresh synthesis: R15-only five-stage route progress pipeline",
                      "Second PnR interrupted; stale first-round reports independently archived and not accepted",
                      "PowerShell5/WMI launcher failures retained; actual PowerShell7 PnrOnly resumed unchanged second VG",
                      "Resumed PnR ended 2026-10-31 22:26:59; current reports accepted"],
                  preserved_failures=["two stale version software assertions before correction",
                      "first Tk run 35 pass / 2 Tcl initialization skips", "first mapped search 1-second bench timeout",
                      "second-VG mapped attestation FileNotFoundError during exit-file move; independent retry passed"],
                  note="Offline candidate only; no vehicle pass, world obstacle calibration, whole-system routed SDF, or Pi deployment. Search external sample/range/frame strobes accelerated, not true 100/600ms mapped timing. Ordinary watchdogs remain 300ms; smart mission lease alone is 600ms with 100ms host renewal. Old MAPPED_RECOVERY_VALIDATION.json is first-VG historical evidence, not authoritative for this candidate.")
    archive.mkdir()
    shutil.copytree(impl, archive / "impl")
    selected = set(hardware) | set(software) | {"scripts/archive_sin12_r15.py"}
    for folder in ("fpga/motor_bt_drive", "fpga/nav", "scripts"):
        for path in (ROOT / folder).glob("*r15*"):
            if path.is_file():
                selected.add(path.relative_to(ROOT).as_posix())
    report["validation_and_source_hashes"] = {}
    for name in sorted(selected):
        source = ROOT / name
        dest = archive / "sources" / name
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, dest)
        assert sha(source) == sha(dest)
        report["validation_and_source_hashes"][name] = sha(source)
    for pattern in ("*R15*.json", "*R15*.md", "r15_*.log", "r15_*.json", "r15_*.xml", "sin12_hdmi_r15_*", "sin12_r15_pnr_resume_launcher_2221_*.log"):
        for source in OUT.glob(pattern):
            if source.is_file():
                shutil.copy2(source, archive / source.name)
    for folder in ("sin12_r15_system_tof", "sin12_r15_system_target", "sin12_r15_mapped_recovery"):
        shutil.copytree(ROOT / "tmp" / folder, archive / "mapped_wrappers" / folder,
                        ignore=shutil.ignore_patterns("sim", "*.wlf", "__pycache__"))
    serialized = json.dumps(report, ensure_ascii=False, indent=2)
    (archive / "BUILD_VERIFICATION.json").write_text(serialized, encoding="utf-8")
    (OUT / "SIN12_R15_BUILD_VERIFICATION_2026-10-31.json").write_text(serialized, encoding="utf-8")
    inventory = {p.relative_to(archive).as_posix():sha(p) for p in archive.rglob("*") if p.is_file()}
    (archive / "ARCHIVE_SHA256.json").write_text(json.dumps(inventory, indent=2), encoding="utf-8")
    assert all(sha(archive / p) == h for p,h in inventory.items())
    verify_manifest(hardware)
    verify_manifest(software)
    assert sha(net) == net_hash and sha(pnr / "sin12_hdmi_system.fs") == report["fs_sha256"]
    print(json.dumps(dict(archive=str(archive), files=len(inventory), source_mismatches=[],
                         internal_sta_checks_pass=True, hardware_access=False), indent=2))

if __name__ == "__main__":
    main()
