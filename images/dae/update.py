#!/usr/bin/env python3

import github
import pathlib
import sys


def main():
  repo = 'daeuniverse/dae'
  ver_file = pathlib.Path(__file__).parent / 'VERSION'
  match sys.argv[1]:
    case 'version':
      with open(ver_file, 'w+') as f:
        ver = github.get_latest_release(repo)
        f.write(ver)
    case 'url':
      with open(ver_file) as f:
        ver = f.read()
        print(github.get_download_url(repo, ver, lambda s: 'linux-x86_64_v3_avx2.zip' in s))
    case _:
      raise(ValueError(f'invalid args {sys.argv}'))


if __name__ == '__main__':
  main()
