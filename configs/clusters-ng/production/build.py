#!/usr/bin/python3

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


def main():
  # Flux
  with pathlib.Path('00-stage', 'flux', 'gotk-components.yaml').open('w') as f:
    subprocess.check_call([
        'flux',
        'install',
        '--export',
        '--components-extra=image-reflector-controller,image-automation-controller',
    ], stdout=f)

  ## Multus-cni
  #get_url(
  #    pathlib.Path('00-stage', 'multus-cni', 'multus-daemonset.yaml'),
  #    'https://raw.githubusercontent.com/k8snetworkplumbingwg/multus-cni/master/deployments/multus-daemonset.yml',
  #)

  ## Tekton
  #get_url(
  #    pathlib.Path('00-stage', 'tekton-pipelines', 'pipelines.yaml'),
  #    'https://storage.googleapis.com/tekton-releases/pipeline/latest/release.yaml',
  #)
  #get_url(
  #    pathlib.Path('00-stage', 'tekton-pipelines', 'triggers.yaml'),
  #    'https://storage.googleapis.com/tekton-releases/triggers/latest/release.yaml',
  #)
  #get_url(
  #    pathlib.Path('00-stage', 'tekton-pipelines', 'interceptors.yaml'),
  #    'https://storage.googleapis.com/tekton-releases/triggers/latest/interceptors.yaml',
  #)
  #get_url(
  #    pathlib.Path('00-stage', 'tekton-pipelines', 'dashboard.yaml'),
  #    'https://storage.googleapis.com/tekton-releases/dashboard/latest/release.yaml',
  #)

  ## 99-default
  #subprocess.check_call([
  #    sys.executable,
  #    'generate.py',
  #], cwd=pathlib.Path('99-default'))


if __name__ == '__main__':
  main()
