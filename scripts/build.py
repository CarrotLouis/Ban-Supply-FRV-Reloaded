"""Gate, assemble and package Ban Supply FRV Reloaded. Never deploys to a live game."""
from pathlib import Path
import argparse, hashlib, importlib.util, json, os, re, subprocess, sys, zipfile

ROOT=Path(__file__).resolve().parents[1]
RESOURCE='mods/carrotlouis/ban_supply_frv_reloaded'
GUID='95a02899-e47b-4c5a-bc28-26f8653f0c18'
DISPLAY='Ban Supply FRV Reloaded'
VERSION=re.search(r"local VERSION='([^']+)'",(ROOT/'src/entry.lua').read_text(encoding='utf-8')).group(1)

def load_file(name,path):
    spec=importlib.util.spec_from_file_location(name,path)
    module=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

def compose():
    parts=['-- HD2-Addon: '+RESOURCE,
           "if rawget(_G,'BanSupplyFRVReloaded') then return rawget(_G,'BanSupplyFRVReloaded') end"]
    for name,file in [('runtime','bingus_runtime'),('memory_module','bingus_memory'),('write_module','bingus_write'),
                      ('profile','profile'),('native_functions','functions'),('reader_module','reader'),
                      ('policy_module','policy'),('native_module','native'),('menu_module','menu')]:
        parts+=['local '+name+'=(function()', (ROOT/'src'/f'{file}.lua').read_text(encoding='utf-8'), 'end)()']
    parts+=['profile.functions=native_functions',(ROOT/'src/entry.lua').read_text(encoding='utf-8')]
    return ('\n'.join(parts)+'\n').encode('utf-8')

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--validate-only',action='store_true')
    parser.add_argument('--loader',type=Path,default=Path(os.environ.get('BINGUS_SHARED_LOADER',ROOT.parent/'BingusSharedLoader')))
    parser.add_argument('--output',type=Path,default=ROOT.parents[1]/'outputs'/f'Ban-Supply-FRV-Reloaded-{VERSION}-test.zip')
    parser.add_argument('--source-bundle',action='store_true')
    parser.add_argument('--native-capture',type=Path,help='retained capture for native recovery gate; never packaged')
    parser.add_argument('--frv-definition',type=Path,help='retained raw component for native timer initialization proof')
    args=parser.parse_args()
    if os.environ.get('HD2_LUPA_DIR'):sys.path.insert(0,os.environ['HD2_LUPA_DIR'])
    from lupa.luajit21 import LuaRuntime
    load_file('bsfrv_ffi_audit',ROOT/'scripts/audit_ffi.py').audit()
    load_file('bsfrv_tests',ROOT/'tests/run.py').run()
    native_evidence=None
    if args.native_capture:
        native_args=[str(args.native_capture)]
        if args.frv_definition:native_args+=['--frv-definition',str(args.frv_definition)]
        load_file('bsfrv_native_lease',ROOT/'tests/verify_native_lease.py').main(native_args)
        native_evidence=json.loads((ROOT/'build/native-lease-emulation.json').read_text())
    lock=json.loads((ROOT/'vendor-lock.json').read_text())
    for filename,expected in lock.items():
        assert hashlib.sha256((ROOT/'src'/filename).read_bytes()).hexdigest()==expected,filename+' differs from upstream'
    source=compose()
    assert not source.startswith(b'\xef\xbb\xbf') and b'\0' not in source and not source.startswith(b'\x1b')
    version=re.search(rb"local VERSION='([^']+)'",source).group(1).decode()
    assert version in args.output.name,'package filename must include source version'
    LuaRuntime().compile(source.decode('utf-8'),name=RESOURCE)
    readme=re.search(rb'--\[===\[(Ban Supply FRV Reloaded - quick guide.*?)\]===\]',source,re.S).group(1)
    assert b'ModOptionsMenu' in source and b'ModBindingsMenu' not in source
    build=ROOT/'build';build.mkdir(exist_ok=True)
    (build/'addon.lua').write_bytes(source)
    load_file('bsfrv_bundle_test',ROOT/'tests/verify_bundle.py').main()
    print('PASS exact bundled LuaJIT source, singleton, README, menu dependency and upstream file hashes')
    if args.validate_only:return
    tools=args.loader/'scripts'
    if not (tools/'build_addon.py').is_file() or not (tools/'archive.py').is_file():
        raise SystemExit('Missing Bingus packaging tools. Clone BingusSharedLoader, or pass --loader <checkout>.')
    sys.path.insert(0,str(tools))
    from build_addon import build_addon
    base=build/'envelope.zip'
    build_addon(RESOURCE,source,GUID,base,DISPLAY)
    with zipfile.ZipFile(base) as z: files={n:z.read(n) for n in z.namelist()}
    manifest=json.loads(files['manifest.json'])
    description=('Disables the two mounted-gun resupply interactions on M-103 Supply FRVs you drive. '
                 'Inactive new drivers, including unmodded teammates, restore resupply through vanilla logic. '
                 'Single default-ON toggle in Mod Options Menu. Requires Bingus Shared Loader and Mod Options Menu. '
                 'Version '+version+' test candidate; Steam build 25480438.')
    manifest['Description']=description
    manifest['Options'][0]['Description']=description
    files['manifest.json']=(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n').encode()
    files['README.txt']=readme.replace(b'\r\n',b'\n').replace(b'\n',b'\r\n')
    for filename in ('LICENSE','THIRD_PARTY_NOTICES.md'):
        files[filename]=(ROOT/filename).read_bytes()
    forbidden={'.bat','.cmd','.ps1','.vbs','.js','.exe','.dll','.py','.lua'}
    assert not [n for n in files if Path(n).suffix.lower() in forbidden]
    args.output.parent.mkdir(parents=True,exist_ok=True)
    with zipfile.ZipFile(args.output,'w',zipfile.ZIP_DEFLATED) as z:
        for name,body in sorted(files.items()):
            info=zipfile.ZipInfo(name,(1980,1,1,0,0,0));info.compress_type=zipfile.ZIP_DEFLATED
            info.external_attr=0o100644<<16;z.writestr(info,body)
    with zipfile.ZipFile(args.output) as z:
        assert set(z.namelist())==set(files)
        assert all(z.read(n)==b for n,b in files.items())
        patch=next(n for n in files if n.startswith('Addon/') and n.endswith('.patch_0'))
        assert int.from_bytes(z.read(patch)[:4],'little')==0xf0000011
        assert source in z.read(patch)
    evidence={'name':DISPLAY,'version':version,'resource':RESOURCE,'guid':GUID,
              'source_sha256':hashlib.sha256(source).hexdigest(),'package_sha256':hashlib.sha256(args.output.read_bytes()).hexdigest(),
              'package_bytes':args.output.stat().st_size,'game_launched':False,'live_profile_changed':False,
              'live_acceptance':'pending','requirements':['BingusSharedLoader','ModOptionsMenu']}
    if native_evidence:
        evidence['native_lease_checks']=native_evidence['checks']
        evidence['native_unmodded_recovery']=True
        evidence['native_emulation_report_sha256']=hashlib.sha256((build/'native-lease-emulation.json').read_bytes()).hexdigest()
    (build/'build-report.json').write_text(json.dumps(evidence,indent=2)+'\n')
    print(json.dumps(evidence,indent=2))
    if args.source_bundle:
        source_output=args.output.parent/f'Ban-Supply-FRV-Reloaded-{version}-source.zip'
        with zipfile.ZipFile(source_output,'w',zipfile.ZIP_DEFLATED) as z:
            for path in sorted(ROOT.rglob('*')):
                if path.is_file() and not any(p in {'.git','build','__pycache__'} for p in path.relative_to(ROOT).parts):
                    z.write(path,'Ban-Supply-FRV-Reloaded/'+path.relative_to(ROOT).as_posix())
        print('SOURCE',source_output)

if __name__=='__main__':main()
