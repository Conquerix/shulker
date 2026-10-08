"""Load the task broker without importing any live user credentials."""
import sys
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'system/modules/nixos/services/openhands'))
