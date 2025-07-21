#!/usr/bin/env python3

import json
import pathlib
import shutil
import subprocess


def generate(base_dir):
  for app in base_dir.glob('**/*.jsonnet'):
    out = base_dir / 'generated' / app.with_suffix('').relative_to(base_dir)
    shutil.rmtree(out, ignore_errors=True)
    subprocess.check_call(args=['jsonnet', '-c', '-m', out, app])

    # jsonnet only allow outputting json objects. This is a workaround for
    # generating arbitrary files by re-evaluating any ".raw" files.
    for raw in out.glob('*.raw'):
      with raw.open() as raw_file:
        with raw.with_suffix('').open('w') as out_file:
          out_file.write(json.load(raw_file))
      raw.unlink()


if __name__ == '__main__':
  generate(pathlib.Path(__file__).parent)

