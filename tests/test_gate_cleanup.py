"""Preview gates must release their own temporary frames, even on failure."""
import importlib.util
import os
from pathlib import Path
import unittest
from unittest.mock import patch


class GateCleanupTests(unittest.TestCase):
    def test_temporary_frames_are_removed_on_success_and_failure(self):
        root = Path(__file__).resolve().parent.parent
        for name in ("hueaudit", "roundtrip"):
            spec = importlib.util.spec_from_file_location(name, root / "scripts" / f"{name}.py")
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
            for failing in (False, True):
                paths = []

                def bounded_run(path):
                    paths.append(path)
                    self.assertTrue(os.path.isdir(path))
                    if failing:
                        raise SystemExit(1)

                with self.subTest(gate=name, failing=failing), patch.object(module, "run", bounded_run):
                    if failing:
                        with self.assertRaises(SystemExit):
                            module.main()
                    else:
                        module.main()
                    self.assertEqual(len(paths), 1)
                    self.assertFalse(os.path.exists(paths[0]))


if __name__ == "__main__":
    unittest.main()
