#!/usr/bin/env python3

import json
import re
import urllib.request
from collections.abc import Callable


def parse_semver(ver: str):
  # https://semver.org/#is-there-a-suggested-regular-expression-regex-to-check-a-semver-string
  semver_regex = re.compile(
      r"^(?P<major>0|[1-9]\d*)\."
      r"(?P<minor>0|[1-9]\d*)\."
      r"(?P<patch>0|[1-9]\d*)"
      r"(?:-(?P<prerelease>(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)"
      r"(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?"
      r"(?:\+(?P<buildmetadata>[0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?$"
  )

  if match := semver_regex.match(ver):
    g = match.groupdict()
    return (
      int(g.get('major', '0')),
      int(g.get('minor', '0')),
      int(g.get('patch', '0'))
    )
  return (0, 0, 0)


def get_latest_tag(repo: str):
  req = urllib.request.Request(f'https://api.github.com/repos/{repo}/tags')
  with urllib.request.urlopen(req) as r:
    latest = (0, 0, 0)
    for t in json.loads(r.read().decode()):
      latest = max(latest, parse_semver(t['name'].lstrip('v')))
    return '.'.join(map(str, latest))


def get_tag_url(repo: str, ver: str):
  ver = parse_semver(ver)
  req = urllib.request.Request(f'https://api.github.com/repos/{repo}/tags')
  with urllib.request.urlopen(req) as r:
    for t in json.loads(r.read().decode()):
      if parse_semver(t['name'].lstrip('v')) == ver: 
        return t['tarball_url']


def get_latest_release(repo: str):
  req = urllib.request.Request(f'https://api.github.com/repos/{repo}/releases/latest')
  with urllib.request.urlopen(req) as r:
    d = json.loads(r.read().decode())
    return d['tag_name'].lstrip('v')


def get_release_url(repo: str, ver: str, select: Callable[[str], bool]):
  req = urllib.request.Request(f'https://api.github.com/repos/{repo}/releases')
  with urllib.request.urlopen(req) as r:
    d = json.loads(r.read().decode())
    for r in d:
      if r['tag_name'].lstrip('v') == ver:
        return next(a['browser_download_url'] for a in r['assets'] if select(a['name']))
