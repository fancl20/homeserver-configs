#!/usr/bin/env python3

import pathlib
import sys
import urllib.request


def get_latest_version_info():
  url = (
    'https://updates.roonlabs.net/update/?'
    'v=2&platform=linux&version=&product=RoonServer&branding=roon&'
    'branch=production&curbranch=production'
  )
  with urllib.request.urlopen(url) as response:
    content = response.read().decode()
    info = {}
    for line in content.splitlines():
      if "=" in line:
        key, value = line.split("=", 1)
        info[key] = value
    return info


def main():
  ver_file = pathlib.Path(__file__).parent / 'VERSION'
  match sys.argv[1]:
    case 'version':
      info = get_latest_version_info()
      with open(ver_file, 'w+') as f:
        ver = info['machineversion']
        f.write(ver)
    case 'url':
      with open(ver_file) as f:
        ver = f.read()
        print(f'https://download.roonlabs.net/updates/production/RoonServer_linuxx64_{ver}.tar.bz2')
    case _:
      raise(ValueError(f'invalid args {sys.argv}'))

if __name__ == '__main__':
  main()
