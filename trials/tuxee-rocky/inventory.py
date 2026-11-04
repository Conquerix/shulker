#!/usr/bin/env python3
"""Read-only local repository/worktree inventory; no fetch, hooks or file contents."""
import argparse
import json
import os
import pathlib
import subprocess
import urllib.parse


def git(repo, *args):
    env = dict(os.environ, GIT_OPTIONAL_LOCKS='0', GIT_TERMINAL_PROMPT='0')
    return subprocess.run(
        ['git', '-c', 'core.fsmonitor=false', '-c', 'core.hooksPath=/dev/null',
         '-C', str(repo), *args], env=env, check=True, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10).stdout.strip()


def remote_label(value):
    # Report only host/path; never credentials, query, fragment or local paths.
    if '://' in value:
        parsed = urllib.parse.urlsplit(value)
        if parsed.scheme not in ('http', 'https', 'ssh', 'git'):
            return '[local or unsupported]'
        return (parsed.hostname or '[unknown]') + parsed.path
    if ':' in value and not value.startswith('/'):
        host, path = value.split(':', 1)
        return host.rsplit('@', 1)[-1] + '/' + path.split('?', 1)[0].split('#', 1)[0]
    return '[local or unsupported]'


def scan(root):
    root = pathlib.Path(root).resolve(strict=True)
    rows = []
    for directory, dirs, files in os.walk(root, followlinks=False):
        dirs[:] = sorted(d for d in dirs if d not in ('.git', 'node_modules', '.cache')
                         and not pathlib.Path(directory, d).is_symlink())
        repo = pathlib.Path(directory)
        if '.git' not in dirs and '.git' not in files and not (repo / '.git').is_dir():
            continue
        try:
            top = pathlib.Path(git(repo, 'rev-parse', '--show-toplevel')).resolve()
            if top != repo:
                continue
            remotes = []
            for name in git(repo, 'remote').splitlines():
                remotes.append({'name': name, 'location': remote_label(git(repo, 'remote', 'get-url', name))})
            worktrees = []
            for line in git(repo, 'worktree', 'list', '--porcelain').splitlines():
                if line.startswith('worktree '):
                    path = pathlib.Path(line[9:]).resolve()
                    worktrees.append(str(path.relative_to(root)) if path.is_relative_to(root) else '[outside root]')
            rows.append({'path': str(repo.relative_to(root)), 'head': git(repo, 'rev-parse', 'HEAD'),
                         'branch': git(repo, 'branch', '--show-current'),
                         'dirty': bool(git(repo, 'status', '--porcelain', '--untracked-files=normal')),
                         'remotes': remotes, 'worktrees': worktrees})
        except (subprocess.SubprocessError, OSError, ValueError):
            rows.append({'path': str(repo.relative_to(root)), 'error': 'repository inspection failed'})
    return sorted(rows, key=lambda row: row['path'])


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('root', type=pathlib.Path)
    args = parser.parse_args()
    print(json.dumps({'repositories': scan(args.root)}, indent=2))
