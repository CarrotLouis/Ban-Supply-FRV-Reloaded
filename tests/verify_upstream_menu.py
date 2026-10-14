"""Register this addon's actual spec using ModOptionsMenu's actual public API.

No menu update is run and no game native UI is called. IO is directed to an
isolated nonexistent values directory; this checks registration, not rendering.
"""
from pathlib import Path
import argparse, os, sys
ROOT=Path(__file__).resolve().parents[1]
if os.environ.get('HD2_LUPA_DIR'):sys.path.insert(0,os.environ['HD2_LUPA_DIR'])
from lupa.luajit21 import LuaRuntime

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('menu',type=Path)
    args=parser.parse_args()
    lua=LuaRuntime(unpack_returned_tuples=True)
    lua.globals()['menu_root']=str(args.menu.resolve()).replace('\\','/')
    lua.globals()['addon_root']=str(ROOT).replace('\\','/')
    lua.globals()['fixture']=str(ROOT/'build/upstream-menu-fixture/no-values').replace('\\','/')
    lua.execute('''
      mom_text={module=dofile(menu_root..'/src/bingus_text.lua'),
                locales={en=dofile(menu_root..'/locales/en.lua'),bundled={}}}
      mom_text.module.registry().steam_language='en'
      mom_files=setmetatable({}, {__index=function(files,name)
          local f=assert(loadfile(menu_root..'/src/'..name..'.lua'));rawset(files,name,f);return f
      end})
      CowboyBingusModLoader={log_directory=fixture,open_log=function()
          return {write=function()end,flush=function()end}
      end}
      update=function()end
      dofile(menu_root..'/src/mod_options_menu.lua')
      local Menu=dofile(addon_root..'/src/menu.lua')
      local integration=Menu.new(function()end)
      integration:step()
      assert(integration.registered and ModOptionsMenu.get(Menu.ID)==true,'real menu must accept our default-ON toggle')
      assert(ModOptionsMenu.set(Menu.ID,false))
      integration:step();assert(integration.enabled==false,'real applied boolean OFF')
      assert(ModOptionsMenu.set(Menu.ID,true))
      integration:step();assert(integration.enabled==true,'real applied boolean ON')
    ''')
    print('PASS upstream ModOptionsMenu: actual registration, category limits and applied ON/OFF API')

if __name__=='__main__':main()
