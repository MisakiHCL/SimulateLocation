#!/usr/bin/env python3
import argparse
import errno
import json
import math
import os
import select
import shutil
import signal
import socket
import subprocess
import sys
import termios
import time
import tty
import urllib.error
import urllib.request
from dataclasses import dataclass
from datetime import datetime
from enum import Enum
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any, Callable, Optional, TextIO
from xml.sax.saxutils import escape


SERVICE_NAME = "SimulateLocation"
SERVICE_TYPE = "_location-gpx._tcp"
LAUNCHD_LABEL = "com.local.SimulateLocation.bridge"
DEFAULT_PORT = 8765
HEALTH_PATH = "/health"
APPLY_PATH = "/apply"
LATEST_FILE_NAME = "SelectedLocation.gpx"
HISTORY_DIR_NAME = "History"
TIMESTAMP_FORMAT = "%m-%d_%H:%M"
COORDINATE_DIGITS = 6
DEFAULT_LOCATION_NAME = "Selected Location"
MAX_BODY_BYTES = 8192
HEALTH_CHECK_TIMEOUT_SECONDS = 0.5
STARTUP_FAILURE_EXIT_CODE = 1
PORT_OWNER_DISPLAY_LIMIT = 3
NEXT_PORT_INCREMENT = 1
NEXT_PORT_MAX_ATTEMPTS = 20
PORT_RELEASE_TIMEOUT_SECONDS = 3.0
PORT_RELEASE_POLL_INTERVAL_SECONDS = 0.1
KEY_SEQUENCE_TIMEOUT_SECONDS = 0.15
XCODE_AUTOMATION_APPLESCRIPT_TIMEOUT_SECONDS = 6
XCODE_AUTOMATION_PROCESS_TIMEOUT_SECONDS = 8
XCODE_MENU_DISMISS_TIMEOUT_SECONDS = 1
LOCAL_BIND_HOSTS = {"", "0.0.0.0", "::"}
BRIDGE_COMMAND = "./Scripts/location-bridge"
KEY_ESCAPE = "\x1b"
KEY_UP = "\x1b[A"
KEY_DOWN = "\x1b[B"
KEY_ENTER_VALUES = {"\r", "\n"}
TERMINAL_CLEAR_LINE = "\x1b[2K"
ANSI_RESET = "\x1b[0m"
ANSI_SELECTED_OPTION = "\x1b[1;7;32m"
ANSI_UNSELECTED_OPTION = "\x1b[2m"
ANSI_HINT = "\x1b[33m"
MENU_POINTER = ">"
MENU_EMPTY_POINTER = " "


class BridgeError(Exception):
    pass


class PortConflictAction(Enum):
    STOP_CURRENT_PROCESS = "stop_current_process"
    USE_NEXT_PORT = "use_next_port"
    ABORT = "abort"


@dataclass(frozen=True)
class WrittenGPX:
    latest_path: Path
    history_path: Path


@dataclass(frozen=True)
class BridgeConfig:
    output_dir: Path
    apply_simulators: bool
    apply_xcode: bool


@dataclass(frozen=True)
class PortOwner:
    pid: str
    command: str
    detail: str


def validate_coordinate(latitude: float, longitude: float) -> None:
    if not math.isfinite(latitude) or not -90 <= latitude <= 90:
        raise BridgeError("latitude must be between -90 and 90")
    if not math.isfinite(longitude) or not -180 <= longitude <= 180:
        raise BridgeError("longitude must be between -180 and 180")


def make_gpx_document(latitude: float, longitude: float, name: str) -> str:
    escaped_name = escape(name, {'"': "&quot;", "'": "&apos;"})
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="{SERVICE_NAME}">
  <wpt lat="{latitude:.{COORDINATE_DIGITS}f}" lon="{longitude:.{COORDINATE_DIGITS}f}">
    <name>{escaped_name}</name>
  </wpt>
</gpx>
"""


def write_gpx_files(
    output_dir: Path,
    latitude: float,
    longitude: float,
    name: str,
    now: Optional[datetime] = None,
) -> WrittenGPX:
    validate_coordinate(latitude=latitude, longitude=longitude)
    timestamp = (now or datetime.now()).strftime(TIMESTAMP_FORMAT)
    document = make_gpx_document(latitude=latitude, longitude=longitude, name=name)

    history_dir = output_dir / HISTORY_DIR_NAME
    output_dir.mkdir(parents=True, exist_ok=True)
    history_dir.mkdir(parents=True, exist_ok=True)

    latest_path = output_dir / LATEST_FILE_NAME
    history_path = history_dir / f"SelectedLocation_{timestamp}.gpx"
    write_text_atomically(latest_path, document)
    write_text_atomically(history_path, document)
    write_text_atomically(
        output_dir / "latest.json",
        json.dumps(
            {
                "latitude": latitude,
                "longitude": longitude,
                "name": name,
                "latestPath": str(latest_path),
                "historyPath": str(history_path),
                "createdAt": datetime.now().isoformat(timespec="seconds"),
            },
            ensure_ascii=False,
            indent=2,
        )
        + "\n",
    )
    return WrittenGPX(latest_path=latest_path, history_path=history_path)


def write_text_atomically(path: Path, text: str) -> None:
    temp_path = path.with_name(f".{path.name}.tmp")
    temp_path.write_text(text, encoding="utf-8")
    temp_path.replace(path)


def apply_to_booted_simulators(latitude: float, longitude: float) -> tuple[list[str], list[str]]:
    applied: list[str] = []
    warnings: list[str] = []
    if shutil.which("xcrun") is None:
        return applied, ["xcrun not found; skipped simulator location"]

    list_result = subprocess.run(
        ["xcrun", "simctl", "list", "devices", "booted", "--json"],
        capture_output=True,
        text=True,
        check=False,
    )
    if list_result.returncode != 0:
        return applied, [f"simctl list failed: {list_result.stderr.strip()}"]

    try:
        payload = json.loads(list_result.stdout)
    except json.JSONDecodeError as error:
        return applied, [f"simctl list returned invalid JSON: {error}"]

    devices = [
        device
        for runtime_devices in payload.get("devices", {}).values()
        for device in runtime_devices
        if device.get("state") == "Booted" and device.get("udid")
    ]
    if not devices:
        return applied, ["no booted simulator found"]

    coordinate = f"{latitude:.{COORDINATE_DIGITS}f},{longitude:.{COORDINATE_DIGITS}f}"
    for device in devices:
        udid = str(device["udid"])
        name = str(device.get("name", udid))
        set_result = subprocess.run(
            ["xcrun", "simctl", "location", udid, "set", coordinate],
            capture_output=True,
            text=True,
            check=False,
        )
        if set_result.returncode == 0:
            applied.append(f"simulator {name}")
        else:
            warnings.append(f"simulator {name}: {set_result.stderr.strip()}")

    return applied, warnings


def xcode_location_automation_script() -> str:
    return f"""
on run argv
  try
    with timeout of {XCODE_AUTOMATION_APPLESCRIPT_TIMEOUT_SECONDS} seconds
      set targetName to item 1 of argv
      set targetNames to {{targetName, targetName & ".gpx"}}
      set reloadNames to {{"Don’t Simulate Location", "Don't Simulate Location", "不模拟位置", "None", "无"}}

      tell application "System Events"
        if not (exists process "Xcode") then error "Xcode process not found"
        tell process "Xcode"
          set frontmost to true
        end tell
      end tell

      set reloadResult to my selectLocationItem(reloadNames, false)
      if reloadResult is not "" then delay 0.3
      set selectedName to my selectLocationItem(targetNames, true)
      return "selected " & selectedName
    end timeout
  on error errorMessage number errorNumber
    my dismissOpenMenu()
    error errorMessage number errorNumber
  end try
end run

on selectLocationItem(candidateNames, shouldFail)
  tell application "System Events"
    tell process "Xcode"
      set frontmost to true
      delay 0.1
      click menu bar item "Debug" of menu bar 1
      delay 0.2
      set debugMenu to menu 1 of menu bar item "Debug" of menu bar 1
      set simulateItem to menu item "Simulate Location" of debugMenu
      click simulateItem
      delay 0.4
      set simulateMenu to menu 1 of simulateItem
      set availableNames to name of every menu item of simulateMenu
      repeat with candidateName in candidateNames
        if availableNames contains candidateName then
          click menu item candidateName of simulateMenu
          return candidateName as text
        end if
      end repeat
      key code 53
      if shouldFail then
        error "No matching GPX item in Debug > Simulate Location"
      end if
      return ""
    end tell
  end tell
end selectLocationItem

on dismissOpenMenu()
  try
    tell application "System Events"
      key code 53
    end tell
  end try
end dismissOpenMenu
"""


def dismiss_xcode_menu() -> None:
    try:
        subprocess.run(
            ["osascript", "-e", 'tell application "System Events" to key code 53'],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
            timeout=XCODE_MENU_DISMISS_TIMEOUT_SECONDS,
        )
    except (OSError, subprocess.TimeoutExpired):
        pass


def apply_to_xcode(gpx_name: str) -> tuple[list[str], list[str]]:
    if shutil.which("osascript") is None:
        return [], ["osascript not found; skipped Xcode automation"]

    xcode_check = subprocess.run(["pgrep", "-x", "Xcode"], capture_output=True, text=True, check=False)
    if xcode_check.returncode != 0:
        return [], ["Xcode is not running; skipped Xcode automation"]

    try:
        result = subprocess.run(
            ["osascript", "-e", xcode_location_automation_script(), gpx_name],
            capture_output=True,
            text=True,
            check=False,
            timeout=XCODE_AUTOMATION_PROCESS_TIMEOUT_SECONDS,
        )
    except subprocess.TimeoutExpired:
        dismiss_xcode_menu()
        return [], [
            f"Xcode automation timed out after {XCODE_AUTOMATION_PROCESS_TIMEOUT_SECONDS}s; "
            "skipped Xcode menu automation"
        ]
    if result.returncode == 0:
        return [f"Xcode {result.stdout.strip()}"], []
    return [], [f"Xcode automation failed: {result.stderr.strip()}"]


class BridgeRequestHandler(BaseHTTPRequestHandler):
    server: "LocationBridgeServer"

    def do_GET(self) -> None:
        if self.path != HEALTH_PATH:
            self.send_json(404, {"ok": False, "message": "not found"})
            return

        self.send_json(
            200,
            {
                "ok": True,
                "service": SERVICE_NAME,
                "outputDir": str(self.server.config.output_dir),
            },
        )

    def do_POST(self) -> None:
        if self.path != APPLY_PATH:
            self.send_json(404, {"ok": False, "message": "not found"})
            return

        try:
            payload = self.read_json_body()
            latitude = float(payload["latitude"])
            longitude = float(payload["longitude"])
            name = str(payload.get("name") or DEFAULT_LOCATION_NAME)
            written = write_gpx_files(
                output_dir=self.server.config.output_dir,
                latitude=latitude,
                longitude=longitude,
                name=name,
            )

            applied: list[str] = []
            warnings: list[str] = []
            if self.server.config.apply_simulators:
                simulator_applied, simulator_warnings = apply_to_booted_simulators(latitude, longitude)
                applied.extend(simulator_applied)
                warnings.extend(simulator_warnings)
            if self.server.config.apply_xcode:
                xcode_applied, xcode_warnings = apply_to_xcode(written.latest_path.stem)
                applied.extend(xcode_applied)
                warnings.extend(xcode_warnings)

            self.send_json(
                200,
                {
                    "ok": True,
                    "latestPath": str(written.latest_path),
                    "historyPath": str(written.history_path),
                    "applied": applied,
                    "warnings": warnings,
                },
            )
        except (BridgeError, KeyError, TypeError, ValueError) as error:
            self.send_json(400, {"ok": False, "message": str(error)})
        except OSError as error:
            self.send_json(500, {"ok": False, "message": str(error)})

    def read_json_body(self) -> dict[str, Any]:
        content_length = int(self.headers.get("Content-Length", "0"))
        if content_length <= 0 or content_length > MAX_BODY_BYTES:
            raise BridgeError("invalid request body length")

        try:
            payload = json.loads(self.rfile.read(content_length).decode("utf-8"))
        except json.JSONDecodeError as error:
            raise BridgeError(f"invalid JSON: {error}") from error

        if not isinstance(payload, dict):
            raise BridgeError("request body must be a JSON object")
        return payload

    def send_json(self, status: int, payload: dict[str, Any]) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format: str, *args: Any) -> None:
        sys.stderr.write(f"[bridge] {self.address_string()} - {format % args}\n")


class LocationBridgeServer(ThreadingHTTPServer):
    def __init__(self, server_address: tuple[str, int], config: BridgeConfig):
        super().__init__(server_address, BridgeRequestHandler)
        self.config = config


def start_bonjour_advertisement(port: int) -> Optional[subprocess.Popen]:
    if shutil.which("dns-sd") is None:
        print("dns-sd not found; Bonjour discovery is disabled", file=sys.stderr)
        return None

    return subprocess.Popen(
        ["dns-sd", "-R", SERVICE_NAME, SERVICE_TYPE, "local", str(port)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        text=True,
    )


def health_check_host(host: str) -> str:
    if host in LOCAL_BIND_HOSTS:
        return "127.0.0.1"
    return host


def format_url_host(host: str) -> str:
    if ":" in host and not host.startswith("["):
        return f"[{host}]"
    return host


def health_check_url(host: str, port: int) -> str:
    return f"http://{format_url_host(health_check_host(host))}:{port}{HEALTH_PATH}"


def fetch_bridge_health(host: str, port: int) -> Optional[dict[str, Any]]:
    try:
        with urllib.request.urlopen(
            health_check_url(host, port),
            timeout=HEALTH_CHECK_TIMEOUT_SECONDS,
        ) as response:
            if response.status != 200:
                return None
            payload = json.loads(response.read(MAX_BODY_BYTES).decode("utf-8"))
    except (OSError, urllib.error.URLError, json.JSONDecodeError, UnicodeDecodeError):
        return None

    if not isinstance(payload, dict):
        return None
    if payload.get("ok") is True and payload.get("service") == SERVICE_NAME:
        return payload
    return None


def find_port_owners(port: int) -> list[PortOwner]:
    if shutil.which("lsof") is None:
        return []

    try:
        result = subprocess.run(
            ["lsof", "-nP", f"-iTCP:{port}", "-sTCP:LISTEN", "-F", "pc"],
            capture_output=True,
            text=True,
            check=False,
        )
    except OSError:
        return []

    if result.returncode != 0:
        return []

    owners: list[PortOwner] = []
    current_pid: Optional[str] = None
    current_command = ""
    for line in result.stdout.splitlines():
        if line.startswith("p"):
            if current_pid is not None:
                owners.append(make_port_owner(current_pid, current_command))
            current_pid = line[1:]
            current_command = ""
        elif line.startswith("c"):
            current_command = line[1:]

    if current_pid is not None:
        owners.append(make_port_owner(current_pid, current_command))

    return owners


def owner_pid_list(owners: list[PortOwner]) -> str:
    return ", ".join(owner.pid for owner in owners)


def make_port_owner(pid: str, command: str) -> PortOwner:
    return PortOwner(pid=pid, command=command or "unknown", detail=process_detail(pid))


def process_detail(pid: str) -> str:
    try:
        result = subprocess.run(
            ["ps", "-p", pid, "-o", "command="],
            capture_output=True,
            text=True,
            check=False,
        )
    except OSError:
        return ""

    if result.returncode != 0:
        return ""
    return result.stdout.strip()


def handle_server_start_error(error: OSError, host: str, port: int) -> int:
    if error.errno == errno.EADDRINUSE:
        print(format_port_in_use_message(host, port), file=sys.stderr)
    else:
        print(f"Failed to start {SERVICE_NAME} bridge on {host}:{port}: {error}", file=sys.stderr)
    return STARTUP_FAILURE_EXIT_CODE


def format_port_in_use_message(host: str, port: int, owners: Optional[list[PortOwner]] = None) -> str:
    lines = [f"Cannot start {SERVICE_NAME} bridge: port {port} is already in use."]

    health = fetch_bridge_health(host, port)
    if health is not None:
        lines.append(f"An existing {SERVICE_NAME} bridge is already responding at {health_check_url(host, port)}.")
        output_dir = health.get("outputDir")
        if isinstance(output_dir, str) and output_dir:
            lines.append(f"Existing output directory: {output_dir}")

    owners = owners if owners is not None else find_port_owners(port)
    if owners:
        lines.append("Listening process:")
        for owner in owners[:PORT_OWNER_DISPLAY_LIMIT]:
            owner_text = f"  - PID {owner.pid} ({owner.command})"
            if owner.detail:
                owner_text = f"{owner_text}: {owner.detail}"
            lines.append(owner_text)

    lines.append(f"Stop the existing process, or start this bridge on another port: {BRIDGE_COMMAND} --port <free-port>")
    return "\n".join(lines)


def is_known_bridge_port(host: str, port: int) -> bool:
    return fetch_bridge_health(host, port) is not None


def stop_known_bridge_on_port(host: str, port: int, owners: Optional[list[PortOwner]] = None) -> bool:
    if not is_known_bridge_port(host, port):
        return False

    owners = owners if owners is not None else find_port_owners(port)
    if owners:
        return stop_port_owners(owners, port)

    if remove_launchd_bridge_job() and wait_for_port_release(port):
        return True

    return False


def find_next_available_port(
    host: str,
    start_port: int,
    max_attempts: int = NEXT_PORT_MAX_ATTEMPTS,
) -> Optional[int]:
    for offset in range(max_attempts):
        candidate_port = start_port + offset
        owners = find_port_owners(candidate_port)
        if not owners:
            return candidate_port
        if stop_known_bridge_on_port(host, candidate_port, owners):
            return candidate_port
    return None


def resolve_port_conflict(host: str, port: int) -> Optional[int]:
    owners = find_port_owners(port)
    if stop_known_bridge_on_port(host, port, owners):
        return port

    action = prompt_port_conflict_action(host, port, owners)
    if action == PortConflictAction.STOP_CURRENT_PROCESS:
        if not owners:
            print(format_port_in_use_message(host, port, owners), file=sys.stderr)
            return None
        if stop_port_owners(owners, port):
            return port
        return None
    if action == PortConflictAction.USE_NEXT_PORT:
        next_port = find_next_available_port(host, port + NEXT_PORT_INCREMENT)
        if next_port is not None:
            return next_port

        print(
            f"Cannot start {SERVICE_NAME} bridge: no free port found after "
            f"{NEXT_PORT_MAX_ATTEMPTS} attempts.",
            file=sys.stderr,
        )
        return None

    print(format_port_in_use_message(host, port, owners), file=sys.stderr)
    return None


def prompt_port_conflict_action(host: str, port: int, owners: list[PortOwner]) -> PortConflictAction:
    next_port = port + NEXT_PORT_INCREMENT
    options: list[tuple[PortConflictAction, str]] = []
    if owners:
        options.append(
            (
                PortConflictAction.STOP_CURRENT_PROCESS,
                f"Stop PID(s) {owner_pid_list(owners)} and use port {port}",
            )
        )
    options.append((PortConflictAction.USE_NEXT_PORT, f"Use port {next_port}"))

    if not sys.stdin.isatty() or not sys.stderr.isatty():
        return PortConflictAction.ABORT

    print(format_port_conflict_summary(host, port, owners), file=sys.stderr)
    selected_index = select_menu_option([option[1] for option in options])
    if selected_index is None:
        return PortConflictAction.ABORT
    return options[selected_index][0]


def format_port_conflict_summary(host: str, port: int, owners: list[PortOwner]) -> str:
    lines = [f"Cannot start {SERVICE_NAME} bridge: port {port} is already in use."]

    health = fetch_bridge_health(host, port)
    if health is not None:
        lines.append(f"Existing {SERVICE_NAME} bridge: {health_check_url(host, port)}")
        output_dir = health.get("outputDir")
        if isinstance(output_dir, str) and output_dir:
            lines.append(f"Existing output directory: {output_dir}")

    if owners:
        lines.append("Listening process:")
        for owner in owners[:PORT_OWNER_DISPLAY_LIMIT]:
            owner_text = f"  - PID {owner.pid} ({owner.command})"
            if owner.detail:
                owner_text = f"{owner_text}: {owner.detail}"
            lines.append(owner_text)

    lines.append(colorize("Use Up/Down arrows, Enter to confirm.", ANSI_HINT))
    return "\n".join(lines)


def select_menu_option(
    options: list[str],
    output: Optional[TextIO] = None,
    read_key: Optional[Callable[[], str]] = None,
    is_interactive: Optional[bool] = None,
) -> Optional[int]:
    if not options:
        return None

    output_stream = output or sys.stderr
    if is_interactive is None:
        is_interactive = sys.stdin.isatty() and output_stream.isatty()
    if not is_interactive:
        return None

    key_reader = read_key or read_terminal_key
    selected_index = 0
    render_menu_options(options, selected_index, output_stream)

    while True:
        key = key_reader()
        if key in KEY_ENTER_VALUES:
            output_stream.write("\n")
            output_stream.flush()
            return selected_index
        if key == KEY_UP:
            selected_index = (selected_index - 1) % len(options)
        elif key == KEY_DOWN:
            selected_index = (selected_index + 1) % len(options)
        elif key.isdigit() and 1 <= int(key) <= len(options):
            selected_index = int(key) - 1
            output_stream.write("\n")
            output_stream.flush()
            return selected_index
        else:
            continue

        render_menu_options(options, selected_index, output_stream, redraw=True)


def render_menu_options(
    options: list[str],
    selected_index: int,
    output: TextIO,
    redraw: bool = False,
) -> None:
    if redraw:
        output.write(f"\x1b[{len(options)}A")

    for index, option in enumerate(options):
        if index == selected_index:
            row = colorize(f"{MENU_POINTER} {option}", ANSI_SELECTED_OPTION)
        else:
            row = colorize(f"{MENU_EMPTY_POINTER} {option}", ANSI_UNSELECTED_OPTION)
        output.write(f"\r{TERMINAL_CLEAR_LINE}{row}\n")
    output.flush()


def colorize(text: str, color: str) -> str:
    return f"{color}{text}{ANSI_RESET}"


def read_terminal_key() -> str:
    file_descriptor = sys.stdin.fileno()
    original_settings = termios.tcgetattr(file_descriptor)
    try:
        tty.setraw(file_descriptor)
        key = os.read(file_descriptor, 1).decode("utf-8", errors="ignore")
        if key != KEY_ESCAPE:
            return key

        parts = [key]
        for _ in range(2):
            ready, _, _ = select.select([file_descriptor], [], [], KEY_SEQUENCE_TIMEOUT_SECONDS)
            if not ready:
                break
            parts.append(os.read(file_descriptor, 1).decode("utf-8", errors="ignore"))
        return "".join(parts)
    finally:
        termios.tcsetattr(file_descriptor, termios.TCSADRAIN, original_settings)


def stop_port_owners(owners: list[PortOwner], port: int) -> bool:
    pids = sorted({owner.pid for owner in owners})
    current_pid = os.getpid()
    stopped_pids: list[str] = []

    for pid_text in pids:
        try:
            pid = int(pid_text)
        except ValueError:
            print(f"Cannot stop invalid PID {pid_text}", file=sys.stderr)
            continue

        if pid == current_pid:
            print(f"Refusing to stop current process PID {pid}", file=sys.stderr)
            continue

        try:
            os.kill(pid, signal.SIGTERM)
            stopped_pids.append(pid_text)
        except OSError as error:
            print(f"Failed to stop PID {pid}: {error}", file=sys.stderr)

    if not stopped_pids:
        return False

    print(f"Sent SIGTERM to PID(s) {', '.join(stopped_pids)}; waiting for port {port}...", file=sys.stderr)
    if wait_for_port_release(port):
        return True

    print(f"Port {port} is still in use after waiting.", file=sys.stderr)
    return False


def wait_for_port_release(port: int) -> bool:
    deadline = time.monotonic() + PORT_RELEASE_TIMEOUT_SECONDS
    while time.monotonic() < deadline:
        if not find_port_owners(port):
            return True
        time.sleep(PORT_RELEASE_POLL_INTERVAL_SECONDS)
    return not find_port_owners(port)


def remove_launchd_bridge_job() -> bool:
    if shutil.which("launchctl") is None:
        return False

    try:
        result = subprocess.run(
            ["launchctl", "remove", LAUNCHD_LABEL],
            capture_output=True,
            text=True,
            check=False,
        )
    except OSError:
        return False
    return result.returncode == 0


def stop_running_bridge(port: int) -> int:
    if remove_launchd_bridge_job() and wait_for_port_release(port):
        print(f"Stopped {SERVICE_NAME} launchd job {LAUNCHD_LABEL}")
        return 0

    owners = find_port_owners(port)
    if owners:
        if stop_port_owners(owners, port):
            print(f"Stopped {SERVICE_NAME} bridge on port {port}")
            return 0
        return STARTUP_FAILURE_EXIT_CODE

    print(f"No running {SERVICE_NAME} bridge found on port {port}")
    return 0


def default_output_dir() -> Path:
    return Path(__file__).resolve().parents[1] / "Generated"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="SimulateLocation local bridge")
    parser.add_argument("--host", default="0.0.0.0", help="host interface to bind")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT, help="HTTP port")
    parser.add_argument("--output-dir", type=Path, default=default_output_dir(), help="GPX output directory")
    parser.add_argument("--no-simulator", action="store_true", help="skip simctl location updates")
    parser.add_argument("--no-xcode", action="store_true", help="skip Xcode UI automation")
    parser.add_argument("--stop", action="store_true", help="stop a running bridge on the selected port")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.stop:
        return stop_running_bridge(args.port)

    config = BridgeConfig(
        output_dir=args.output_dir.resolve(),
        apply_simulators=not args.no_simulator,
        apply_xcode=not args.no_xcode,
    )
    port = args.port
    while True:
        try:
            server = LocationBridgeServer((args.host, port), config)
            break
        except OSError as error:
            if error.errno != errno.EADDRINUSE:
                return handle_server_start_error(error, args.host, port)
            next_port = resolve_port_conflict(args.host, port)
            if next_port is None:
                return STARTUP_FAILURE_EXIT_CODE
            port = next_port

    actual_port = int(server.server_address[1])
    bonjour_process = start_bonjour_advertisement(actual_port)

    def stop_server(signum: int, frame: Any) -> None:
        raise KeyboardInterrupt

    signal.signal(signal.SIGINT, stop_server)
    signal.signal(signal.SIGTERM, stop_server)

    host_name = socket.gethostname()
    print(f"SimulateLocation bridge listening on {args.host}:{actual_port}")
    print(f"Bonjour service: {SERVICE_NAME}.{SERVICE_TYPE}.local")
    print(f"Output directory: {config.output_dir}")
    print(f"Mac host: {host_name}.local:{actual_port}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("Stopping SimulateLocation bridge")
    finally:
        if bonjour_process is not None:
            bonjour_process.terminate()
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
