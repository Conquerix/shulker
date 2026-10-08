"""Seed secret-free native profiles once; preserve operator provider changes."""
import json
import os
from pathlib import Path
import sys
import tempfile
from uuid import UUID


def seed(state: Path, source: Path) -> None:
    data = json.loads(source.read_text())
    destinations = {
        state/'agent-profiles': data['agent_profile'],
        state/'profiles': data['llm'],
    }
    # Reject links before writing either profile; private state is never shared.
    for directory in destinations:
        if directory.is_symlink() or (directory/'overseer-coding.json').is_symlink():
            raise ValueError('Invalid native profile destination')
    profiles = state/'agent-profiles'
    expected = UUID(data['agent_profile']['id'])
    matches = []
    if profiles.exists():
        for path in profiles.glob('*.json'):
            if path.is_symlink():
                raise ValueError('Invalid native profile destination')
            saved = json.loads(path.read_text())
            identity = UUID(saved['id'])
            if path.name == 'overseer-coding.json' and identity != expected:
                raise ValueError('Conflicting native profile identity')
            if identity == expected:
                if saved.get('agent_kind') != 'openhands':
                    raise ValueError('Native profile has a different agent kind')
                matches.append(path)
    if len(matches) > 1:
        raise ValueError('Duplicate native profile identity')
    if matches:
        # Names and LLM references may have been changed through Canvas.
        return
    for directory, payload in destinations.items():
        directory.mkdir(mode=0o700, parents=True, exist_ok=True)
        destination = directory/'overseer-coding.json'
        fd, pending = tempfile.mkstemp(prefix='.native-', dir=directory)
        try:
            with os.fdopen(fd, 'w') as handle:
                json.dump(payload, handle); handle.flush(); os.fsync(handle.fileno())
            try:
                # Atomic create-if-absent leaves any saved profile untouched.
                os.link(pending, destination)
            except FileExistsError:
                pass
        finally:
            os.unlink(pending)


if __name__ == '__main__':
    seed(Path(sys.argv[1]), Path(sys.argv[2]))
