#!/usr/bin/python3

import io
import json
import os
import zipfile
from urllib.request import urlopen

URL_TERRAFORM_CHECK = 'https://checkpoint-api.hashicorp.com/v1/check/terraform'

def get_download_url():
    with urlopen(URL_TERRAFORM_CHECK) as resp:
        version = json.load(resp)['current_version']
        return (
            'https://releases.hashicorp.com/terraform'
            f'/{version}/terraform_{version}_linux_amd64.zip'
        )

def download_terraform(path):
    with urlopen(get_download_url()) as resp:
        data = io.BytesIO(resp.read())
        z = zipfile.ZipFile(data)
        z.extractall(path)

if __name__ == '__main__':
        download_terraform('/usr/local/bin')
        os.chmod('/usr/local/bin/terraform', 0o755)
