#!/usr/bin/env python3
"""Atheris fuzz harness for pyntcloud's point-cloud file readers (pyntcloud.io.FROM_FILE).

This is the pre-migration mayhemheroes harness (savantenvs/pyntcloud's archive/original-master,
matching ghcr.io/mayhemheroes/pyntcloud:archive-original-master — the image mayhemheroes run 7 was
actually built from, per its /target/parse-fuzz/run/7 record), reconstructed here rather than
copied from the current `mayhem` branch: that branch's harness was rewritten later with a much
broader except clause (also catching ValueError/KeyError/UnicodeDecodeError/EOFError/TypeError/...)
that swallows every one of run 7's defects as "expected", so it never reproduces them
(BACKPORT.md, Known problems — Input-interface caveat). Each defect here bottoms out inside
pyntcloud's own reader (pyntcloud/io/ply.py, bin.py, npz.py, obj.py) on a malformed file, not in
this driver.

Atheris is a libFuzzer engine: run with libFuzzer flags it iterates; run with a single file
argument it replays that input once (standalone reproducer). The ELF ``launcher`` (launcher.c)
exec's ``python3`` on this file, forwarding every argument unchanged.
"""
import sys
import tempfile

import atheris
import laspy

with atheris.instrument_imports(include=["pyntcloud", "pyntcloud.core_class"]):
    import pyntcloud.io as pio

from pandas.errors import EmptyDataError, ParserError

SUPPORTED_EXTS = list(pio.FROM_FILE.keys())


@atheris.instrument_func
def TestOneInput(data):
    fdp = atheris.FuzzedDataProvider(data)
    fuzz_ext = fdp.PickValueInList(SUPPORTED_EXTS)
    fuzz_func = pio.FROM_FILE[fuzz_ext]
    fuzz_data = fdp.ConsumeBytes(fdp.remaining_bytes()).decode("utf-8", "ignore").encode()

    try:
        with tempfile.NamedTemporaryFile(suffix=fuzz_ext) as tempf:
            tempf.write(fuzz_data)
            tempf.seek(0)
            tempf.flush()
            fuzz_func(tempf.name)
    except (EmptyDataError, laspy.LaspyException, IndexError, ParserError):
        return -1
    except ValueError as e:
        if "OFF" in str(e) or "pickle" in str(e) or "ply" in str(e):
            return -1
        raise


def main():
    atheris.Setup(sys.argv, TestOneInput)
    atheris.Fuzz()


if __name__ == "__main__":
    main()
