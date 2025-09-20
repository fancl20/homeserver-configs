#!/usr/bin/env python3

import github
import pathlib
import sys


def main():
  repo = 'beancount/fava'
  ver_file = pathlib.Path(__file__).parent / 'VERSION'
  match sys.argv[1]:
    case 'version':
      with open(ver_file, 'w+') as f:
        ver = github.get_latest_tag(repo)
        f.write(ver)
    case 'url':
      with open(ver_file) as f:
        ver = f.read()
        print(f'fava=={ver}')
    case _:
      raise(ValueError(f'invalid args {sys.argv}'))


if __name__ == '__main__':
  main()
