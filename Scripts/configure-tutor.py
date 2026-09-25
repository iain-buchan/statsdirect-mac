#!/usr/bin/env python3
"""Embed only the public service address in the signed app. No provider credential is accepted."""
import os
import plistlib
import sys
from pathlib import Path
from urllib.parse import urlsplit

path = Path(sys.argv[1])
profile = plistlib.loads(path.read_bytes())
address = os.environ.get('STATSDIRECT_TUTOR_SERVICE_URL', '').strip()
if address:
    url = urlsplit(address)
    if url.scheme != 'https' or not url.hostname or url.username or url.password or url.query or url.fragment:
        raise SystemExit('STATSDIRECT_TUTOR_SERVICE_URL must be a public HTTPS service URL without credentials, query or fragment.')
    profile['StatsDirectTutorServiceURL'] = address.rstrip('/')
else:
    profile.pop('StatsDirectTutorServiceURL', None)
profile.pop('StatsDirectTutorAllowLocalTesting', None)
path.write_bytes(plistlib.dumps(profile))
