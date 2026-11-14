import importlib.util
import tempfile
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('renderer', Path(__file__).parents[1] / 'system/modules/nixos/services/openclaw/render-environment.py')
assert spec is not None and spec.loader is not None
renderer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(renderer)


class EnvironmentTests(unittest.TestCase):
    def test_private_atomic_output_and_invalid_input(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            sources = [root / str(i) for i in range(3)]
            for path in sources:
                path.write_text('test-value')
            target = root / 'environment'
            renderer.render(sources, target)
            self.assertEqual(target.stat().st_mode & 0o777, 0o600)
            self.assertIn('OPENCLAW_GATEWAY_TOKEN="test-value"', target.read_text())
            previous = target.read_text()
            sources[0].write_text('bad\nvalue')
            with self.assertRaises(ValueError):
                renderer.render(sources, target)
            self.assertEqual(target.read_text(), previous)


if __name__ == '__main__':
    unittest.main()
