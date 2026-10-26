#!/usr/bin/env python3
"""Verify the frozen keychain component without reading any keychain item."""
from pathlib import Path
import json,hashlib,subprocess
root=Path(__file__).resolve().parents[1];p=root/'Resources/FinTrackKeychainHelper';lock=json.loads(p.with_suffix('.lock.json').read_text());h=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
assert h(p)==lock['sha256'],'Keychain component binary changed'
assert p.stat().st_mode & 0o111,'Keychain component must be executable'
for name,digest in lock['source_sha256'].items():assert h(root/name)==digest,'Helper source changed: component migration review required'
subprocess.run(['codesign','--verify','--strict','-R','='+lock['designated_requirement'],str(p)],check=True,capture_output=True)
for arch,expected in lock['cdhashes'].items():
 c=subprocess.run(['codesign','--display','--verbose=4','--arch',arch,str(p)],check=True,capture_output=True,text=True);actual=next(l.split('=',1)[1] for l in (c.stdout+c.stderr).splitlines() if l.startswith('CDHash='));assert actual==expected,'Helper identity changed: '+arch
print('PASS frozen keychain helper: signature, two architecture identities and source/binary pins')
