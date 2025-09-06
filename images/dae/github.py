#!/usr/bin/env python3

import json
import urllib.request
from collections.abc import Callable

def get_latest_release(repo: str):
  req = urllib.request.Request(f'https://api.github.com/repos/{repo}/releases/latest')
  with urllib.request.urlopen(req) as r:
    d = json.loads(r.read().decode())
    return d['tag_name'].lstrip('v')

def get_download_url(repo: str, ver: str, select: Callable[[str], bool]):
  req = urllib.request.Request(f'https://api.github.com/repos/{repo}/releases')
  with urllib.request.urlopen(req) as r:
    d = json.loads(r.read().decode())
    for r in d:
      if r['tag_name'].lstrip('v') == ver:
        return next(a['browser_download_url'] for a in r['assets'] if select(a['name']))
