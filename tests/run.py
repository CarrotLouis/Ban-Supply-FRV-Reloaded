from pathlib import Path
import os, sys

ROOT=Path(__file__).resolve().parents[1]
if os.environ.get('HD2_LUPA_DIR'):
    sys.path.insert(0,os.environ['HD2_LUPA_DIR'])
from lupa.luajit21 import LuaRuntime

def run() -> None:
    for path in sorted(ROOT.joinpath('tests').glob('test_*.lua')):
        lua=LuaRuntime(unpack_returned_tuples=True)
        lua.execute("package.path="+repr(str(ROOT/'src/?.lua').replace('\\','/'))+"..';'..package.path")
        lua.execute(path.read_text(encoding='utf-8'))
    lua=LuaRuntime()
    for path in ROOT.joinpath('src').glob('*.lua'):
        lua.compile(path.read_text(encoding='utf-8'),name=path.name)
    print('PASS LuaJIT 2.1 compile: all source modules')

if __name__=='__main__':
    run()
