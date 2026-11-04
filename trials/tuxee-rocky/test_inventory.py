import importlib.util
import pathlib
import subprocess
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('inventory', pathlib.Path(__file__).with_name('inventory.py'))
inventory = importlib.util.module_from_spec(spec) if spec else None
if spec and spec.loader and pathlib.Path(spec.origin).exists():
    spec.loader.exec_module(inventory)

class InventoryTests(unittest.TestCase):
    def test_real_repo_and_worktree_are_read_only_and_remote_sanitized(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            repo = root / 'repo'
            subprocess.run(['git', 'init', '-q', str(repo)], check=True)
            def git(*args):
                return subprocess.run(['git', '-C', str(repo), *args], check=True, capture_output=True)
            git('config', 'user.name', 'Fixture')
            git('config', 'user.email', 'fixture@example.invalid')
            (repo / 'file').write_text('same-file\n')
            git('add', 'file')
            git('commit', '-qm', 'fixture')
            git('remote', 'add', 'origin', 'https://user:SECRET@example.invalid/team/repo.git?token=PRIVATE')
            git('worktree', 'add', '-qb', 'task', str(root / 'task'))
            (repo / 'untracked').write_text('private contents not inventoried')
            before = (repo / '.git/index').read_bytes()
            result = inventory.scan(root)
            self.assertEqual(len(result), 2)
            self.assertEqual((repo / '.git/index').read_bytes(), before)
            self.assertNotIn('SECRET', str(result))
            self.assertNotIn('PRIVATE', str(result))
            self.assertNotIn('private contents', str(result))
            self.assertTrue(all(r['head'] and r['worktrees'] for r in result))
            self.assertTrue(next(r for r in result if r['path']=='repo')['dirty'])

if __name__ == '__main__':
    unittest.main()
