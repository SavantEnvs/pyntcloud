#!/usr/bin/env python3
"""Atheris fuzz harness for pyntcloud's point-cloud file readers (pyntcloud.io.FROM_FILE).

pyntcloud reads many point-cloud / mesh formats (PLY, OBJ, OFF, PCD, NPZ, BIN, LAS/LAZ and the
plain ASCII variants ASC/CSV/PTS/TXT/XYZ). Each reader in ``pyntcloud.io.FROM_FILE`` takes a
*file path*, so the harness picks one supported extension from the fuzzer-provided bytes, writes
the rest of the input to a temp file with that suffix, and calls the matching reader — exercising
the same parse path ``PyntCloud.from_file`` drives.

Only the malformed-input errors a reader is *expected* to raise on garbage are swallowed; an
unexpected exception (an uncaught crash inside pyntcloud) is reported as a finding.

Atheris is a libFuzzer engine: run with libFuzzer flags it iterates; run with a single file
argument it replays that input once (standalone reproducer). The ELF ``launcher`` (launcher.c)
exec's ``python3`` on this file, forwarding every argument unchanged.
"""
import logging
import os
import struct
import sys
import tempfile
import warnings
import zipfile

import atheris

# Instrument the whole pyntcloud package so Atheris gets edge coverage of the readers. Importing
# ``pyntcloud.io`` here (and nothing before this block) means every reader submodule — ascii, bin,
# las, npz, obj, off, pcd, ply, plus the open3d/pyvista shims — is imported for the first time
# INSIDE the block, so all of them are instrumented (verify with "INFO: Instrumenting pyntcloud.io.*").
with atheris.instrument_imports():
    import pyntcloud.io as pio

from pandas.errors import EmptyDataError, ParserError

try:
    from laspy import LaspyException
except ImportError:  # laspy is optional; .las/.laz simply error out without it.
    class LaspyException(Exception):
        pass

# Readers are noisy on garbage input — silence logging/warnings so the fuzzer runs fast.
logging.disable(logging.CRITICAL)
warnings.filterwarnings("ignore")

# Map the io registry keys (ASC/PLY/...) to a concrete file suffix the reader expects.
SUPPORTED_EXTS = ["." + ext.lower() for ext in pio.FROM_FILE.keys()]


@atheris.instrument_func
def TestOneInput(data):
    fdp = atheris.FuzzedDataProvider(data)
    ext = fdp.PickValueInList(SUPPORTED_EXTS)
    reader = pio.FROM_FILE[ext[1:].upper()]
    payload = fdp.ConsumeBytes(fdp.remaining_bytes())

    tmp_path = None
    try:
        with tempfile.NamedTemporaryFile(suffix=ext, delete=False) as tmp:
            tmp.write(payload)
            tmp_path = tmp.name
        reader(tmp_path)
    except (
        EmptyDataError,
        ParserError,
        ValueError,
        IndexError,
        KeyError,
        TypeError,
        OSError,
        UnicodeDecodeError,
        struct.error,
        StopIteration,
        NotImplementedError,
        EOFError,
        zipfile.BadZipFile,
        LaspyException,
    ):
        # Expected ways a malformed point-cloud stream is rejected — not defects.
        return -1
    finally:
        if tmp_path is not None:
            try:
                os.unlink(tmp_path)
            except OSError:
                pass


def main():
    atheris.Setup(sys.argv, TestOneInput)
    atheris.Fuzz()


if __name__ == "__main__":
    main()
