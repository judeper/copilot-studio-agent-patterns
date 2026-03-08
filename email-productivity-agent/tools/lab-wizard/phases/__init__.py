"""EPA Lab Wizard - phase modules."""

import shutil
import subprocess
from typing import Any


def resolve_cli(cmd: list[str], **kwargs: Any) -> subprocess.CompletedProcess:
    """Run a subprocess command, resolving .CMD wrappers on Windows.

    On Windows, CLI tools like ``pac`` and ``az`` are often installed as
    ``.CMD`` batch files that ``subprocess.run`` cannot locate without
    ``shell=True``.  This helper uses ``shutil.which`` to resolve the full
    path before execution.
    """
    resolved = shutil.which(cmd[0])
    run_cmd = [resolved] + cmd[1:] if resolved else cmd
    return subprocess.run(run_cmd, **kwargs)