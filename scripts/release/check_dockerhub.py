#!/usr/bin/env python3
"""Check Docker Hub credentials and repository scope without uploading anything."""
import base64
import json
import os
import sys
import urllib.error
import urllib.request


def check():
    username = os.environ.get('DOCKERHUB_USERNAME', '')
    password = os.environ.get('DOCKERHUB_TOKEN', '')
    if not username or not password:
        raise ValueError('Docker Hub credentials are missing')
    request = urllib.request.Request(
        'https://auth.docker.io/token?service=registry.docker.io&scope=repository:hashev/ffido:pull,push',
        headers={'Authorization': 'Basic '+base64.b64encode((username+':'+password).encode()).decode()})
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            token = json.load(response)['token']
        claims = json.loads(base64.urlsafe_b64decode(token.split('.')[1]+'==='))
        access = next((entry for entry in claims.get('access', [])
                       if entry.get('type') == 'repository' and entry.get('name') == 'hashev/ffido'), {})
        if not {'pull', 'push'} <= set(access.get('actions', [])):
            raise ValueError('Docker Hub token does not grant pull and push to hashev/ffido')
    except (urllib.error.URLError, KeyError, IndexError, json.JSONDecodeError) as error:
        raise ValueError('Cannot verify Docker Hub authentication/scope') from None
    print('PASS: Docker Hub authentication and pull/push scope for hashev/ffido; nothing uploaded')


if __name__ == '__main__':
    try:
        check()
    except ValueError as error:
        sys.exit(str(error))
