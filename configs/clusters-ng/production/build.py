#!/usr/bin/env python3

import json
import os
import pathlib
import subprocess
import sys
import tarfile
import urllib.request


def get_url(dst: pathlib.Path, url: str):
  with dst.open('wb') as f:
    with urllib.request.urlopen(url) as r:
      for b in iter(lambda: r.read(1024), b''):
        f.write(b)


def get_github_latest_release(repo: str):
  req = urllib.request.Request(f"https://api.github.com/repos/{repo}/releases/latest")
  with urllib.request.urlopen(req) as r:
    d = json.loads(r.read().decode())
    return d["tag_name"].lstrip('v')


def main():
  # Flux
  with pathlib.Path('00-stage', 'flux', 'gotk-components.yaml').open('w') as f:
    subprocess.check_call([
        'flux',
        'install',
        '--export',
        '--components-extra=image-reflector-controller,image-automation-controller',
    ], stdout=f)

  # Multus-cni
  multus_ver = get_github_latest_release('k8snetworkplumbingwg/multus-cni')
  get_url(
      pathlib.Path('04-stage', 'multus-cni', 'multus-daemonset.yaml'),
      'https://raw.githubusercontent.com/'
      'k8snetworkplumbingwg/multus-cni/'
      f'refs/tags/v{multus_ver}/'
      'deployments/multus-daemonset.yml',
  )

  # 99-services
  subprocess.check_call([
      sys.executable,
      pathlib.Path('99-services') / 'generate.py',
  ])


if __name__ == '__main__':
  main()
