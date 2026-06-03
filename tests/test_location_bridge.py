import errno
import io
import os
import subprocess
import sys
import threading
import time
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from unittest.mock import patch


ROOT_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT_DIR / "Scripts"))

import location_bridge  # noqa: E402


class LocationBridgeStartupTests(unittest.TestCase):
    def test_xcode_automation_script_opens_debug_menu_before_simulate_location_submenu(self) -> None:
        script = location_bridge.xcode_location_automation_script()

        self.assertIn('click menu bar item "Debug"', script)
        self.assertIn("click simulateItem", script)

    def test_xcode_automation_script_uses_current_xcode_disabled_location_name(self) -> None:
        script = location_bridge.xcode_location_automation_script()

        self.assertIn('"Don’t Simulate Location"', script)

    def test_apply_to_xcode_times_out_hung_automation(self) -> None:
        run_calls: list[tuple[list[str], dict[str, object]]] = []

        def run_command(command: list[str], **kwargs: object) -> subprocess.CompletedProcess[str]:
            run_calls.append((command, kwargs))
            if command[0] == "pgrep":
                return subprocess.CompletedProcess(command, 0, stdout="123\n", stderr="")
            if command[0] == "osascript":
                self.assertIn("timeout", kwargs)
                raise subprocess.TimeoutExpired(command, timeout=kwargs["timeout"])
            self.fail(f"unexpected command: {command}")

        with (
            patch.object(location_bridge.shutil, "which", return_value="/usr/bin/osascript"),
            patch.object(location_bridge.subprocess, "run", side_effect=run_command),
        ):
            applied, warnings = location_bridge.apply_to_xcode("SelectedLocation")

        self.assertEqual(applied, [])
        self.assertTrue(any("timed out" in warning for warning in warnings))
        self.assertGreaterEqual(len(run_calls), 2)

    def test_select_menu_option_moves_with_arrow_keys(self) -> None:
        keys = iter([location_bridge.KEY_DOWN, "\n"])
        output = io.StringIO()

        selection = location_bridge.select_menu_option(
            ["stop current process", "use next port"],
            output=output,
            read_key=lambda: next(keys),
            is_interactive=True,
        )

        self.assertEqual(selection, 1)

    def test_render_menu_options_uses_color_to_distinguish_selection(self) -> None:
        output = io.StringIO()

        location_bridge.render_menu_options(["stop current process", "use next port"], 0, output)

        rendered = output.getvalue()
        self.assertIn(location_bridge.ANSI_SELECTED_OPTION, rendered)
        self.assertIn(location_bridge.ANSI_UNSELECTED_OPTION, rendered)
        self.assertIn(location_bridge.ANSI_RESET, rendered)

    def test_read_terminal_key_reads_full_arrow_sequence(self) -> None:
        master_fd, slave_fd = os.openpty()
        slave = os.fdopen(slave_fd, "r")

        def write_key() -> None:
            time.sleep(0.05)
            os.write(master_fd, location_bridge.KEY_DOWN.encode("utf-8"))

        writer = threading.Thread(target=write_key)
        try:
            writer.start()
            with patch.object(sys, "stdin", slave):
                self.assertEqual(location_bridge.read_terminal_key(), location_bridge.KEY_DOWN)
            writer.join(timeout=1)
        finally:
            slave.close()
            os.close(master_fd)

    def test_main_reports_port_conflict_without_traceback(self) -> None:
        bind_error = OSError(errno.EADDRINUSE, "Address already in use")
        stderr = io.StringIO()
        stdout = io.StringIO()

        with (
            patch.object(sys, "argv", ["location_bridge.py", "--host", "0.0.0.0", "--port", "8765"]),
            patch.object(location_bridge, "LocationBridgeServer", side_effect=bind_error),
            redirect_stderr(stderr),
            redirect_stdout(stdout),
        ):
            try:
                exit_code = location_bridge.main()
            except OSError as error:
                self.fail(f"main should handle port conflicts without raising: {error}")

        self.assertNotEqual(exit_code, 0)
        self.assertIn("port 8765 is already in use", stderr.getvalue())
        self.assertIn("--port", stderr.getvalue())

    def test_main_uses_next_port_after_interactive_selection(self) -> None:
        calls: list[tuple[str, int]] = []

        def create_server(address: tuple[str, int], config: location_bridge.BridgeConfig) -> "FakeServer":
            calls.append(address)
            if len(calls) == 1:
                raise OSError(errno.EADDRINUSE, "Address already in use")
            return FakeServer(address)

        with (
            patch.object(sys, "argv", ["location_bridge.py", "--host", "0.0.0.0", "--port", "8765"]),
            patch.object(location_bridge, "LocationBridgeServer", side_effect=create_server),
            patch.object(location_bridge, "find_port_owners", return_value=[location_bridge.PortOwner("123", "Python", "")]),
            patch.object(location_bridge, "prompt_port_conflict_action", return_value=location_bridge.PortConflictAction.USE_NEXT_PORT),
            patch.object(location_bridge, "find_next_available_port", return_value=8766) as find_next_available_port,
            patch.object(location_bridge, "start_bonjour_advertisement", return_value=None),
            redirect_stderr(io.StringIO()),
            redirect_stdout(io.StringIO()),
        ):
            exit_code = location_bridge.main()

        self.assertEqual(exit_code, 0)
        self.assertEqual(calls, [("0.0.0.0", 8765), ("0.0.0.0", 8766)])
        find_next_available_port.assert_called_once_with("0.0.0.0", 8766)

    def test_main_stops_owner_and_retries_original_port(self) -> None:
        owner = location_bridge.PortOwner("123", "Python", "")
        calls: list[tuple[str, int]] = []

        def create_server(address: tuple[str, int], config: location_bridge.BridgeConfig) -> "FakeServer":
            calls.append(address)
            if len(calls) == 1:
                raise OSError(errno.EADDRINUSE, "Address already in use")
            return FakeServer(address)

        with (
            patch.object(sys, "argv", ["location_bridge.py", "--host", "0.0.0.0", "--port", "8765"]),
            patch.object(location_bridge, "LocationBridgeServer", side_effect=create_server),
            patch.object(location_bridge, "find_port_owners", return_value=[owner]),
            patch.object(location_bridge, "prompt_port_conflict_action", return_value=location_bridge.PortConflictAction.STOP_CURRENT_PROCESS),
            patch.object(location_bridge, "stop_port_owners", return_value=True) as stop_port_owners,
            patch.object(location_bridge, "start_bonjour_advertisement", return_value=None),
            redirect_stderr(io.StringIO()),
            redirect_stdout(io.StringIO()),
        ):
            exit_code = location_bridge.main()

        self.assertEqual(exit_code, 0)
        self.assertEqual(calls, [("0.0.0.0", 8765), ("0.0.0.0", 8765)])
        stop_port_owners.assert_called_once_with([owner], 8765)

    def test_main_auto_stops_known_bridge_without_prompting(self) -> None:
        owner = location_bridge.PortOwner("123", "Python", "")
        calls: list[tuple[str, int]] = []

        def create_server(address: tuple[str, int], config: location_bridge.BridgeConfig) -> "FakeServer":
            calls.append(address)
            if len(calls) == 1:
                raise OSError(errno.EADDRINUSE, "Address already in use")
            return FakeServer(address)

        with (
            patch.object(sys, "argv", ["location_bridge.py", "--host", "0.0.0.0", "--port", "8765"]),
            patch.object(location_bridge, "LocationBridgeServer", side_effect=create_server),
            patch.object(location_bridge, "fetch_bridge_health", return_value={"ok": True, "service": location_bridge.SERVICE_NAME}),
            patch.object(location_bridge, "find_port_owners", return_value=[owner]),
            patch.object(location_bridge, "stop_port_owners", return_value=True) as stop_port_owners,
            patch.object(location_bridge, "prompt_port_conflict_action") as prompt_port_conflict_action,
            patch.object(location_bridge, "start_bonjour_advertisement", return_value=None),
            redirect_stderr(io.StringIO()),
            redirect_stdout(io.StringIO()),
        ):
            exit_code = location_bridge.main()

        self.assertEqual(exit_code, 0)
        self.assertEqual(calls, [("0.0.0.0", 8765), ("0.0.0.0", 8765)])
        stop_port_owners.assert_called_once_with([owner], 8765)
        prompt_port_conflict_action.assert_not_called()

    def test_find_next_available_port_skips_unknown_occupied_ports(self) -> None:
        unknown_owner = location_bridge.PortOwner("321", "OtherServer", "")

        def owners_for_port(port: int) -> list[location_bridge.PortOwner]:
            if port == 8766:
                return [unknown_owner]
            return []

        with patch.object(location_bridge, "find_port_owners", side_effect=owners_for_port):
            resolved_port = location_bridge.find_next_available_port("0.0.0.0", 8766, max_attempts=3)

        self.assertEqual(resolved_port, 8767)

    def test_find_next_available_port_reuses_known_bridge_after_stopping_it(self) -> None:
        bridge_owner = location_bridge.PortOwner("456", "Python", "")

        with (
            patch.object(location_bridge, "find_port_owners", return_value=[bridge_owner]),
            patch.object(location_bridge, "fetch_bridge_health", return_value={"ok": True, "service": location_bridge.SERVICE_NAME}),
            patch.object(location_bridge, "stop_port_owners", return_value=True) as stop_port_owners,
        ):
            resolved_port = location_bridge.find_next_available_port("0.0.0.0", 8766, max_attempts=3)

        self.assertEqual(resolved_port, 8766)
        stop_port_owners.assert_called_once_with([bridge_owner], 8766)

    def test_resolve_port_conflict_uses_next_available_port_after_selection(self) -> None:
        with (
            patch.object(location_bridge, "fetch_bridge_health", return_value=None),
            patch.object(location_bridge, "find_port_owners", return_value=[location_bridge.PortOwner("123", "OtherServer", "")]),
            patch.object(location_bridge, "prompt_port_conflict_action", return_value=location_bridge.PortConflictAction.USE_NEXT_PORT),
            patch.object(location_bridge, "find_next_available_port", return_value=8768) as find_next_available_port,
        ):
            resolved_port = location_bridge.resolve_port_conflict("0.0.0.0", 8765)

        self.assertEqual(resolved_port, 8768)
        find_next_available_port.assert_called_once_with("0.0.0.0", 8766)

    def test_stop_running_bridge_removes_launchd_job_before_checking_port(self) -> None:
        calls: list[str] = []

        def remove_launchd_job() -> bool:
            calls.append("remove_launchd_job")
            return True

        def wait_for_port_release(port: int) -> bool:
            calls.append(f"wait_for_port_release:{port}")
            return True

        with (
            patch.object(location_bridge, "remove_launchd_bridge_job", side_effect=remove_launchd_job),
            patch.object(location_bridge, "wait_for_port_release", side_effect=wait_for_port_release),
            patch.object(location_bridge, "find_port_owners") as find_port_owners,
            redirect_stdout(io.StringIO()) as stdout,
        ):
            exit_code = location_bridge.stop_running_bridge(8765)

        self.assertEqual(exit_code, 0)
        self.assertEqual(calls, ["remove_launchd_job", "wait_for_port_release:8765"])
        find_port_owners.assert_not_called()
        self.assertIn("Stopped", stdout.getvalue())

    def test_stop_running_bridge_stops_port_owner_when_not_launchd_managed(self) -> None:
        owner = location_bridge.PortOwner("123", "Python", "")

        with (
            patch.object(location_bridge, "remove_launchd_bridge_job", return_value=False),
            patch.object(location_bridge, "find_port_owners", return_value=[owner]),
            patch.object(location_bridge, "stop_port_owners", return_value=True) as stop_port_owners,
            redirect_stdout(io.StringIO()) as stdout,
        ):
            exit_code = location_bridge.stop_running_bridge(8765)

        self.assertEqual(exit_code, 0)
        stop_port_owners.assert_called_once_with([owner], 8765)
        self.assertIn("Stopped", stdout.getvalue())

    def test_main_stop_flag_stops_bridge_without_starting_server(self) -> None:
        with (
            patch.object(sys, "argv", ["location_bridge.py", "--stop", "--port", "8765"]),
            patch.object(location_bridge, "stop_running_bridge", return_value=0) as stop_running_bridge,
            patch.object(location_bridge, "LocationBridgeServer") as server,
        ):
            exit_code = location_bridge.main()

        self.assertEqual(exit_code, 0)
        stop_running_bridge.assert_called_once_with(8765)
        server.assert_not_called()


class FakeServer:
    def __init__(self, address: tuple[str, int]):
        self.server_address = address

    def serve_forever(self) -> None:
        raise KeyboardInterrupt

    def server_close(self) -> None:
        pass


if __name__ == "__main__":
    unittest.main()
