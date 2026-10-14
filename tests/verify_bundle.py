"""Check the EXACT assembled entry's startup and singleton/update-chain contract."""
from pathlib import Path
import os, sys
ROOT=Path(__file__).resolve().parents[1]
if os.environ.get('HD2_LUPA_DIR'):sys.path.insert(0,os.environ['HD2_LUPA_DIR'])
from lupa.luajit21 import LuaRuntime

def main():
    # All IO, including the addon's ordinary load log, goes into this fixture.
    os.environ['LOCALAPPDATA']=str(ROOT/'build/startup-fixture')
    (Path(os.environ['LOCALAPPDATA'])/'CowboyBingus/Helldivers2/Logs').mkdir(parents=True,exist_ok=True)
    source=(ROOT/'build/addon.lua').read_text(encoding='utf-8')
    lua=LuaRuntime(unpack_returned_tuples=True)
    lua.execute('''
        lower_calls=0
        update=function(dt,extra) lower_calls=lower_calls+1;return dt,nil,extra end
        ModOptionsMenu={api=1,values={},registered=0,
          register_option=function(id,spec)
            assert(spec.type=='toggle' and spec.default==true)
            ModOptionsMenu.registered=ModOptionsMenu.registered+1
            ModOptionsMenu.values[id]=spec.default;return true
          end,
          get=function(id)return ModOptionsMenu.values[id]end,
          ready=function()return true end}
    ''')
    first=lua.execute(source)
    assert first['enabled'] is True
    assert lua.eval('update')(0.1,'lower return')==(0.1,None,'lower return')
    lua.execute('assert(lower_calls==1 and ModOptionsMenu.registered==1)')
    lua.globals()['initial_api']=first
    lua.execute(source)
    lua.execute('assert(BanSupplyFRVReloaded==initial_api)')
    assert lua.eval('update')(0.1,'second')==(0.1,None,'second')
    lua.execute('assert(lower_calls==2 and ModOptionsMenu.registered==1)')
    assert first['status']=='startup grace'
    print('PASS exact entry: default ON, late menu registration, singleton and lossless update chaining')

if __name__=='__main__':main()
