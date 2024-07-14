#!/usr/bin/python3

import json
import os
import pathlib
import subprocess
import sys
import tarfile
import urllib.request
from typing import Any, Dict


def github_latest(repo: str) -> Dict[str, Any]:
  with urllib.request.urlopen(f'https://api.github.com/repos/{repo}/releases/latest') as r:
    return json.load(r)


def install_flux(dst: pathlib.Path):
  if dst.joinpath('flux').exists():
    return
  for a in github_latest('fluxcd/flux2')['assets']:
    if 'linux_amd64' in a['name']:
      u = a['browser_download_url']
  with urllib.request.urlopen(u) as r:
    with tarfile.open(fileobj=r, mode='r|*') as z:
      z.extractall(dst)


def get_url(dst: pathlib.Path, url: str):
  with dst.open('wb') as f:
    with urllib.request.urlopen(url) as r:
      for b in iter(lambda: r.read(1024), b''):
        f.write(b)


def main():
  root = pathlib.Path('.build')
  root.mkdir(exist_ok=True)
  os.environ['PATH'] += os.pathsep + str(root)

  # Flux
  install_flux(root)
  with pathlib.Path('00-stage', 'flux', 'gotk-components.yaml').open('w') as f:
    subprocess.check_call([
        'flux',
        'install',
        '--export',
        '--components-extra=image-reflector-controller,image-automation-controller',
    ], stdout=f)

  # Multus-cni
  get_url(
      pathlib.Path('00-stage', 'multus-cni', 'multus-daemonset.yaml'),
      'https://raw.githubusercontent.com/k8snetworkplumbingwg/multus-cni/master/deployments/multus-daemonset.yml',
  )

  # Argo Workflows
  get_url(
      pathlib.Path('00-stage', 'argo', 'workflows.yaml'),
      {
          a['name']: a['browser_download_url']
          for a in github_latest('argoproj/argo-workflows')['assets']
      }['install.yaml']
  )

  # 99-default
  subprocess.check_call([
      sys.executable,
      'generate.py',
  ], cwd=pathlib.Path('99-default'))


if __name__ == '__main__':
  main()
