#!/usr/bin/env python3
"""Native String Catalog interchange. Validate completely before atomic writes."""
import argparse,copy,hashlib,json,os,re,sys,tempfile
from pathlib import Path

class PackError(ValueError): pass

def unique(pairs):
    result={}
    for key,value in pairs:
        if key in result: raise PackError('duplicate JSON key: '+key)
        result[key]=value
    return result

def read(path):
    return json.loads(Path(path).read_text(encoding='utf-8'),object_pairs_hook=unique)

def encoded(value):
    return (json.dumps(value,ensure_ascii=False,indent=2,sort_keys=True)+'\n').encode()

def atomic(path,data):
    path=Path(path); path.parent.mkdir(parents=True,exist_ok=True)
    fd,name=tempfile.mkstemp(prefix='.'+path.name+'.',dir=path.parent)
    try:
        with os.fdopen(fd,'wb') as f: f.write(data); f.flush(); os.fsync(f.fileno())
        os.replace(name,path)
    finally:
        if os.path.exists(name): os.unlink(name)

# Normalize positions and integral width. Reordering requires explicit positions.
TOKEN=re.compile(r'%#@(?P<substitution>[A-Za-z_]\w*)@|%%|%(?:(?P<position>\d+)\$)?[-+#0 ]*(?P<width>\d+)?(?:\.(?P<precision>\d+))?(?P<length>hh|ll|h|l|q|z|t|j|L)?(?P<conversion>[@diuoxXfFeEgGaAcCsSp])')
def placeholders(text):
    result={}; next_index=1
    for m in TOKEN.finditer(text):
        if m.group(0)=='%%': continue
        if m['substitution']:
            key='substitution:'+m['substitution']; result[key]=result.get(key,0)+1; continue
        if m['width'] and int(m['width'])>10000: raise PackError('unsafe format width')
        if m['precision'] and int(m['precision'])>1000: raise PackError('unsafe precision')
        index=int(m['position']) if m['position'] else next_index
        if not m['position']: next_index+=1
        conv=m['conversion']; width=m['length'] or ''
        kind='object' if conv=='@' else ('integer:'+width if conv in 'diuoxXcC' else 'float:'+width if conv in 'fFeEgGaA' else 'unsafe')
        if kind=='unsafe': raise PackError('unsafe printf conversion')
        key=str(index)+':'+kind; result[key]=result.get(key,0)+1
    if re.search(r'%(?:\d+\$)?[-+#0 \d.*]*(?:hh|ll|h|l|q|z|t|j|L)?[np]',text): raise PackError('unsafe printf conversion')
    if re.search(r'%(?:\d+\$)?[-+#0 \d.]*\*',text): raise PackError('dynamic printf width is not supported')
    return result

def leaves(payload,path=''):
    if not isinstance(payload,dict) or not payload: raise PackError('empty or non-object payload: '+path)
    allowed={'stringUnit','variations','substitutions'}
    if set(payload)-allowed: raise PackError('unknown payload fields: '+path)
    output=[]
    if 'stringUnit' in payload:
        unit=payload['stringUnit']
        if not isinstance(unit,dict) or set(unit)-{'state','value'} or not isinstance(unit.get('value'),str) or not unit['value'].strip(): raise PackError('empty/invalid stringUnit: '+path)
        if unit.get('state')!='translated': raise PackError('unreviewed translation: '+path)
        if '\x00' in unit['value']: raise PackError('NUL in translation: '+path)
        output.append((path,unit['value']))
    if 'variations' in payload:
        variations=payload['variations']
        if not isinstance(variations,dict) or not variations or set(variations)-{'plural','device'}: raise PackError('unknown variation axis: '+path)
        for axis,items in variations.items():
            if not isinstance(items,dict) or not items: raise PackError('empty variation: '+path)
            if axis=='plural' and ('other' not in items or set(items)-{'zero','one','two','few','many','other'}): raise PackError('plural requires other and valid categories: '+path)
            for key,value in items.items(): output+=leaves(value,path+'/'+axis+'/'+key)
    if 'substitutions' in payload:
        subs=payload['substitutions']
        if not isinstance(subs,dict) or not subs: raise PackError('empty substitutions: '+path)
        for name,value in subs.items():
            if not isinstance(value,dict) or set(value)-{'argNum','formatSpecifier','variations'} or not isinstance(value.get('argNum'),int) or isinstance(value['argNum'],bool) or value['argNum']<1 or not re.fullmatch(r'(?:ll|l)?[diufg@]',value.get('formatSpecifier','')): raise PackError('invalid substitution: '+path+'/'+name)
            output+=leaves({'variations':value.get('variations')},path+'/substitutions/'+name)
    if not output: raise PackError('payload has no strings: '+path)
    return output

def signature(payload):
    sig={path:placeholders(value) for path,value in leaves(payload)}
    subs={k:(v['argNum'],v['formatSpecifier']) for k,v in payload.get('substitutions',{}).items()}
    return sig,subs

def validate_payload(reference,payload,key):
    expected,expected_subs=signature(reference); actual,actual_subs=signature(payload)
    if expected_subs!=actual_subs: raise PackError('substitution identity/type mismatch: '+key)
    for path,sig in actual.items():
        fallback=re.sub(r'/plural/(?:zero|one|two|few|many)(?=/|$)','/plural/other',path)
        reference_sig=expected.get(path,expected.get(fallback))
        if reference_sig is None and re.fullmatch(r'/plural/(zero|one|two|few|many|other)',path): reference_sig=expected.get('')
        if reference_sig is None or sig!=reference_sig: raise PackError('placeholder/variant mismatch: '+key+path)
    for path in expected:
        if '/plural/' not in path and path not in actual and not (path=='' and '/plural/other' in actual): raise PackError('missing variant: '+key+path)
    # Target-specific plural categories are legal; every source axis still needs other.
    for path in expected:
        if path.endswith('/plural/other') and path not in actual: raise PackError('missing plural other: '+key+path)

def validate_empty_sentinel(payload):
    if payload != {'stringUnit': {'state': 'translated', 'value': ''}}:
        raise PackError('the original empty-key sentinel must remain exactly empty and translated')

def baseline(catalog,key):
    entry=catalog['strings'][key]
    en=entry.get('localizations',{}).get('en')
    if en: return en
    # Historical catalog source keys are English text. New semantic keys must have
    # an explicit English resource before a language can pass the release gate.
    semantic_id = re.fullmatch(r'[a-z][A-Za-z0-9_]*(?:\.[A-Za-z0-9_]+)+', key) is not None
    if entry.get('comment','').startswith('v1.5 pending English') or semantic_id:
        raise PackError('English baseline requires Chat translation: '+key)
    return {'stringUnit':{'state':'translated','value':key}}

def validate_pack(catalog,pack):
    if type(pack.get('schemaVersion')) is not int or pack.get('schemaVersion')!=1 or pack.get('catalogVersion')!='fintrack-v1.5': raise PackError('schema/catalog version mismatch')
    if not isinstance(pack.get('nativeName'),str) or not pack['nativeName'].strip(): raise PackError('nativeName required')
    locale=pack.get('locale','')
    if not re.fullmatch(r'[a-z]{2,3}(?:-[A-Z][a-z]{3})?(?:-(?:[A-Z]{2}|\d{3}))?(?:-[A-Za-z0-9]{2,8})*',locale): raise PackError('invalid BCP-47 locale')
    entries=pack.get('entries')
    if not isinstance(entries,dict): raise PackError('entries object required')
    required=set(catalog['strings']); provided=set(entries)
    if required!=provided: raise PackError('key mismatch: missing='+str(sorted(required-provided))+' extra='+str(sorted(provided-required)))
    for key,payload in entries.items():
        if key=='':
            validate_empty_sentinel(payload); continue
        if locale=='en' and not catalog['strings'][key].get('localizations',{}).get('en'):
            ref=catalog['strings'][key].get('localizations',{}).get('zh-Hans')
            # Old Xcode catalogs can retain English source-text keys with no
            # localization subtrees. The immutable key itself is their contract.
            if ref is None: ref=baseline(catalog,key)
        else: ref=baseline(catalog,key)
        if locale=='en':
            # A reviewed target may replace an unreviewed English draft. Its
            # reference state is not an argument/variant contract.
            ref=copy.deepcopy(ref)
            def reviewed_reference(value):
                if isinstance(value,dict):
                    if isinstance(value.get('stringUnit'),dict): value['stringUnit']['state']='translated'
                    for child in value.values(): reviewed_reference(child)
                elif isinstance(value,list):
                    for child in value: reviewed_reference(child)
            reviewed_reference(ref)
        validate_payload(ref,payload,key)
    return locale

def merge(catalog,pack):
    locale=validate_pack(catalog,pack); result=copy.deepcopy(catalog)
    for key,value in pack['entries'].items(): result['strings'][key].setdefault('localizations',{})[locale]=value
    return result

def main():
    p=argparse.ArgumentParser(description=__doc__); p.add_argument('--catalog',default='Resources/Localizable.xcstrings'); p.add_argument('--backup-dir',default='Local/Localization/Backups')
    sub=p.add_subparsers(dest='action',required=True)
    ex=sub.add_parser('export'); ex.add_argument('--locale',required=True); ex.add_argument('--native-name',required=True); ex.add_argument('--output',required=True)
    for name in ['validate','import']:
        s=sub.add_parser(name); s.add_argument('pack')
    s=sub.add_parser('coverage'); s.add_argument('--locale',required=True)
    s=sub.add_parser('assemble'); s.add_argument('--base',required=True); s.add_argument('--output',required=True); s.add_argument('fragments',nargs='+')
    s=sub.add_parser('release-manifest'); s.add_argument('--language',action='append',required=True,help='locale=nativeName'); s.add_argument('--output',required=True)
    args=p.parse_args(); catalog=read(args.catalog)
    if args.action=='assemble':
        pack=read(args.base); seen=set()
        for filename in args.fragments:
            fragment=read(filename)
            for field in ['schemaVersion','catalogVersion','locale','nativeName']:
                if fragment.get(field)!=pack.get(field): raise PackError('fragment metadata mismatch: '+filename)
            entries=fragment.get('entries')
            if not isinstance(entries,dict) or set(entries)-set(pack['entries']): raise PackError('unknown fragment keys: '+filename)
            if seen.intersection(entries): raise PackError('duplicate keys across fragments: '+filename)
            seen.update(entries);pack['entries'].update(entries)
        validate_pack(catalog,pack);atomic(args.output,encoded(pack));print(json.dumps({'status':'PASS','action':'assemble','entries':len(pack['entries'])}));return
    if args.action=='release-manifest':
        languages=[]
        for raw in args.language:
            locale,native=raw.split('=',1)
            entries={k:(v.get('localizations',{}).get(locale) or (baseline(catalog,k) if locale=='en' else None)) for k,v in catalog['strings'].items()}
            validate_pack(catalog,dict(schemaVersion=1,catalogVersion='fintrack-v1.5',locale=locale,nativeName=native,entries=entries))
            languages.append(dict(id=locale,nativeName=native))
        if not languages or languages[0]['id']!='en' or len({x['id'] for x in languages})!=len(languages): raise PackError('English must be first; duplicate languages forbidden')
        atomic(args.output,encoded(dict(schemaVersion=1,catalogVersion='fintrack-v1.5',languages=languages)));print(json.dumps({'status':'PASS','action':'release-manifest','languages':languages}));return
    if args.action=='export':
        entries={}
        for key,value in catalog['strings'].items():
            if key=='':
                entries[key]={'stringUnit':{'state':'translated','value':''}}; continue
            payload=value.get('localizations',{}).get(args.locale)
            if payload is None and args.locale=='en':
                try: payload=baseline(catalog,key)
                except PackError: pass
            entries[key]=payload or {'stringUnit':{'state':'new','value':''}}
        atomic(args.output,encoded(dict(schemaVersion=1,catalogVersion='fintrack-v1.5',locale=args.locale,nativeName=args.native_name,entries=entries)))
        print(json.dumps({'status':'EXPORTED','entries':len(entries),'output':args.output}));return
    if args.action=='coverage':
        failures={}
        for key,item in catalog['strings'].items():
            try:
                value=item.get('localizations',{}).get(args.locale)
                if value is None and args.locale=='en': value=baseline(catalog,key)
                if key=='': validate_empty_sentinel(value)
                else: validate_payload(baseline(catalog,key),value,key)
            except (PackError,TypeError) as e: failures[key]=str(e)
        print(json.dumps({'locale':args.locale,'total':len(catalog['strings']),'valid':len(catalog['strings'])-len(failures),'failures':failures},ensure_ascii=False,indent=2));sys.exit(bool(failures))
    pack=read(args.pack); updated=merge(catalog,pack)
    if args.action=='import':
        path=Path(args.catalog); original=path.read_bytes(); data=encoded(updated)
        if data!=original:
            backup=Path(args.backup_dir)/(path.name+'.'+hashlib.sha256(original).hexdigest()[:12]+'.bak')
            if not backup.exists(): atomic(backup,original)
            atomic(path,data)
    print(json.dumps({'status':'PASS','locale':pack['locale'],'entries':len(pack['entries']),'action':args.action}))

if __name__=='__main__':
    try: main()
    except (PackError,ValueError,OSError) as error: print('FAIL: '+str(error),file=sys.stderr);sys.exit(2)
