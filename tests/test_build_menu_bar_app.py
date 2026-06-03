import os
import unittest
from pathlib import Path


ROOT_DIR = Path(__file__).resolve().parents[1]
BUILD_SCRIPT = ROOT_DIR / "Scripts" / "build-menu-bar-app"


class BuildMenuBarAppScriptTests(unittest.TestCase):
    def test_build_script_creates_clickable_menu_bar_app_artifact(self) -> None:
        self.assertTrue(BUILD_SCRIPT.exists(), "build script should exist")
        self.assertTrue(os.access(BUILD_SCRIPT, os.X_OK), "build script should be executable")

        script = BUILD_SCRIPT.read_text(encoding="utf-8")

        self.assertIn("SimulateLocationMenuBar", script)
        self.assertIn("xcodebuild", script)
        self.assertIn("Build/SimulateLocationMenuBar.app", script)
        self.assertIn("ditto", script)


if __name__ == "__main__":
    unittest.main()
