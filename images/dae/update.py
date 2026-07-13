#!/usr/bin/env python3

import github
import pathlib
import sys

# Temporary workaround for the v2.0.0 UDP short-write regression (#1029, fixed
# upstream by the still-unmerged https://github.com/daeuniverse/dae/pull/1030).
# v1.0.0 predates the bug, so the fetcher ships the v1.0.0 binary. The image is
# tagged 2.0.2 (not 1.0.0) so flux's highest-semver ImagePolicy rolls forward off
# the buggy 2.0.0-testing tag already in the registry. Revert both to tracking
# get_latest_release / VERSION once #1030 ships upstream.
IMAGE_VERSION = '2.0.2'
BINARY_VERSION = '1.0.0'


def main():
  repo = 'daeuniverse/dae'
  ver_file = pathlib.Path(__file__).parent / 'VERSION'
  match sys.argv[1]:
    case 'version':
      with open(ver_file, 'w+') as f:
        f.write(IMAGE_VERSION)
    case 'url':
      print(github.get_release_url(repo, BINARY_VERSION,
            lambda s: 'linux-x86_64_v3_avx2.zip' in s))
    case _:
      raise (ValueError(f'invalid args {sys.argv}'))


if __name__ == '__main__':
  main()
