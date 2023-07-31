#!/usr/bin/python3

import glob
import pathlib
import subprocess


def main():
  for app in glob.glob('*.jsonnet'):
    out = pathlib.Path('generated', app).with_suffix('')
    subprocess.check_call(args=['jsonnet', '-c', '-m', out, app])


if __name__ == "__main__":
  main()
