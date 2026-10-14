"""Audit the canonical runtime's versioned private declarations and exported aliases.

The HD2-Agent-Skills generic regex scanner cannot follow ffi.cdef(DECLARATIONS)
or computed private names. Keep upstream files byte-identical; inspect those
declaration strings instead, backed by test_memory.lua's real Windows calls.
"""
from pathlib import Path
import re
ROOT=Path(__file__).resolve().parents[1]

def audit():
    forbidden={'GetCursorPos','GetForegroundWindow','GetAsyncKeyState','GetWindowThreadProcessId','GetCursorInfo'}
    declarations={}
    for filename in ('bingus_memory.lua','bingus_write.lua'):
        text=(ROOT/'src'/filename).read_text()
        block=re.search(r'local DECLARATIONS\s*=\s*\[\[(.*?)\]\]',text,re.S).group(1)
        for private,export in re.findall(r'(bingus_\w+)\([^;]*?\)\s*__asm__\("(\w+)"\)\s*;',block,re.S):
            assert export not in forbidden,'unexpected user32 declaration'
            assert private.endswith('_'+export),'private alias/export mismatch'
            assert private not in declarations,'duplicate private symbol'
            declarations[private]=export
    assert len(declarations)==17,'unexpected canonical native-symbol count'
    assert 'WriteProcessMemory' in declarations.values()
    read_text=(ROOT/'src/bingus_memory.lua').read_text()
    functions=re.search(r'local FUNCTIONS = \{(.*?)\n\}',read_text,re.S).group(1)
    names=set(re.findall(r"'([A-Z]\w+)'",functions))
    assert names <= set(declarations.values()),'called canonical symbol has no private declaration'
    print('PASS FFI audit: 17 versioned private declarations; all dynamic bindings declared; no user32')

if __name__=='__main__':audit()
