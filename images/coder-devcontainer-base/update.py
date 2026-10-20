#!/usr/bin/env python3

import pathlib
import sys


def main():
  ver_file = pathlib.Path(__file__).parent / 'VERSION'
  match sys.argv[1]:
    case 'version':
      with open(ver_file, 'w+') as f:
        f.write('1')
    case _:
      raise (ValueError(f'invalid args {sys.argv}'))


if __name__ == '__main__':
  main()
