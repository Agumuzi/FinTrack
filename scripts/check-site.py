#!/usr/bin/env python3
"""Validate the product site's local resources and document links without dependencies."""
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlsplit, unquote
import re

ROOT = Path(__file__).resolve().parents[1]
SITE = ROOT / 'website'

class Document(HTMLParser):
    def __init__(self):
        super().__init__()
        self.ids, self.links = set(), []
    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if 'id' in attrs:
            assert attrs['id'] not in self.ids, f'Duplicate id: {attrs["id"]}'
            self.ids.add(attrs['id'])
        for key in ('src', 'href'):
            if key in attrs:
                self.links.append(attrs[key])

def check():
    document = Document()
    document.feed((SITE / 'index.html').read_text())
    count = 0
    for link in document.links:
        parsed = urlsplit(link)
        if parsed.scheme or parsed.netloc:
            prefix = 'https://github.com/Agumuzi/FinTrack/blob/main/'
            if link.startswith(prefix):
                assert (ROOT / unquote(link[len(prefix):].split('#')[0])).is_file(), link
            continue
        if not parsed.path:
            assert not parsed.fragment or parsed.fragment in document.ids, link
        else:
            path = (SITE / unquote(parsed.path)).resolve()
            assert path.is_relative_to(SITE), f'Outside website: {link}'
            assert path.is_file(), f'Missing site resource: {link}'
        count += 1
    for name in ('overview', 'records', 'finance', 'exchange', 'settings'):
        path = SITE / 'assets' / 'screenshots' / (name + '.png')
        assert path.read_bytes().startswith(b'\x89PNG\r\n\x1a\n'), f'Invalid screenshot: {path.name}'
    for link in re.findall(r'url\([\'\"]?([^\)\'\"]+)', (SITE / 'styles.css').read_text()):
        if not urlsplit(link).scheme and not link.startswith('data:'):
            assert (SITE / link).is_file(), link
    print(f'Validated {count} local links and five real screenshot resources.')

if __name__ == '__main__':
    check()
