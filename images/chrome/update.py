#!/usr/bin/env python3

import json
import pathlib
import sys
import urllib.request


def get_latest_version():
  url = 'https://googlechromelabs.github.io/chrome-for-testing/last-known-good-versions.json'
  with urllib.request.urlopen(url) as response:
    d = json.loads(response.read().decode())
    return d['channels']['Stable']['version']


def get_download_url(version: str):
  url = 'https://googlechromelabs.github.io/chrome-for-testing/known-good-versions-with-downloads.json'
  with urllib.request.urlopen(url) as response:
    d = json.loads(response.read().decode())
    for v in d['versions']:
      if v['version'] == version:
        for download in v['downloads']['chrome']:
          if download['platform'] == 'linux64':
            return download['url']
  raise ValueError(f'Version {version} or linux64 download not found')


def main():
  ver_file = pathlib.Path(__file__).parent / 'VERSION'
  match sys.argv[1]:
    case 'version':
      with open(ver_file, 'w+') as f:
        f.write(get_latest_version())
    case 'url':
      with open(ver_file) as f:
        ver = f.read()
      print(get_download_url(ver))
    case _:
      raise ValueError(f'invalid args {sys.argv}')


if __name__ == '__main__':
  main()
