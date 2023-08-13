#!/usr/bin/python3

import glob
import pathlib
import shutil
import subprocess


def main():
  for app in glob.glob('*.jsonnet'):
    out = pathlib.Path('generated', app).with_suffix('')
    shutil.rmtree(out, ignore_errors=True)
    subprocess.check_call(args=['jsonnet', '-c', '-m', out, app])


if __name__ == "__main__":
  main()
