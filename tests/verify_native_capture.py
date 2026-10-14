"""Run retained native bytes only in Unicorn, not in Windows or the game process."""
from pathlib import Path
import argparse, json, os, struct, sys

ROOT=Path(__file__).resolve().parents[1]

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('capture',type=Path)
    parser.add_argument('--output',type=Path,default=ROOT/'build/native-emulation.json')
    args=parser.parse_args()
    if os.environ.get('HD2_LUPA_DIR'):sys.path.insert(0,os.environ['HD2_LUPA_DIR'])
    from lupa.luajit21 import LuaRuntime
    from unicorn import Uc, UC_ARCH_X86, UC_MODE_64, UC_HOOK_CODE
    from unicorn.x86_const import UC_X86_REG_RCX,UC_X86_REG_RDX,UC_X86_REG_R8,UC_X86_REG_R9,UC_X86_REG_RSP,UC_X86_REG_RIP
    code=(args.capture/'game.dll.01_00001000.bin').read_bytes()
    lua=LuaRuntime()
    lua.execute('package.path='+repr(str(ROOT/'src/?.lua').replace('\\','/'))+"..';'..package.path")
    native=lua.eval("require('native')")
    functions=lua.eval("require('functions')")
    for name,spec in functions.items():
        body=code[spec['rva']-0x1000:spec['rva']-0x1000+spec['length']]
        assert native['fingerprint'](body)==spec['fingerprint'],name+' fingerprint differs from capture'
    setter=functions['set_zone']
    u=Uc(UC_ARCH_X86,UC_MODE_64)
    base=0x10000000
    entry=base+setter['rva']
    queue=base+functions['queue_change']['rva']
    u.mem_map(entry&~0xfff,0x2000)
    u.mem_write(entry,code[setter['rva']-0x1000:setter['rva']-0x1000+setter['length']])
    u.mem_map(queue&~0xfff,0x1000)
    # The stock setter's RIP-relative invalid-entity sentinel.
    u.mem_map(base+0x3483000,0x1000)
    u.mem_write(base+0x3483c20,struct.pack('<I',0xffffffff))
    manager,map_rows,records,flags,record=0x30000000,0x40000000,0x41000000,0x42000000,0x43000000
    for address,size in [(manager,0x15000),(map_rows,0x1000),(records,0x1000),(flags,0x1000),(record,0x1000)]:
        u.mem_map(address,size)
    u.mem_write(manager+0x14050,struct.pack('<QIII',map_rows,8,0xffffffff,1))
    u.mem_write(manager+0x14068,struct.pack('<Q',records))
    u.mem_write(manager+0x14078,struct.pack('<Q',flags))
    u.mem_write(map_rows,b'\xff'*64)
    entity_id,network_unit,index=548,321,3
    u.mem_write(map_rows+(entity_id%8)*8,struct.pack('<II',entity_id,index))
    u.mem_write(records+index*8,struct.pack('<Q',record))
    u.mem_write(record+0x10,struct.pack('<I',network_unit))
    cell=flags+index*16
    u.mem_write(cell,struct.pack('<IIII',127,0xaabbccdd,0x12345678,0))
    stack,stop=0x70000000,0x71000000
    u.mem_map(stack,0x4000);u.mem_map(stop,0x1000)
    notifications=[]
    def intercept(uc,address,size,user_data):
        if address==queue:
            unit=uc.reg_read(UC_X86_REG_RCX)
            prop=uc.reg_read(UC_X86_REG_RDX)
            pointer=uc.reg_read(UC_X86_REG_R8)
            assert unit==network_unit and prop==0x788b9753 and pointer==cell
            notifications.append({'network_unit':unit,'property':hex(prop),
                                  'mask':struct.unpack('<I',uc.mem_read(cell,4))[0]})
            sp=uc.reg_read(UC_X86_REG_RSP)
            target=struct.unpack('<Q',uc.mem_read(sp,8))[0]
            uc.reg_write(UC_X86_REG_RSP,sp+8);uc.reg_write(UC_X86_REG_RIP,target)
    u.hook_add(UC_HOOK_CODE,intercept)
    def call(zone,enabled):
        sp=stack+0x2000
        u.mem_write(sp,struct.pack('<Q',stop))
        for register,value in [(UC_X86_REG_RCX,manager),(UC_X86_REG_RDX,entity_id),
                               (UC_X86_REG_R8,zone),(UC_X86_REG_R9,int(enabled)),(UC_X86_REG_RSP,sp)]:
            u.reg_write(register,value)
        u.emu_start(entry,stop,count=10000)
        assert u.reg_read(UC_X86_REG_RIP)==stop,'native setter exceeded execution budget'
        assert bytes(u.mem_read(cell+4,8))==struct.pack('<II',0xaabbccdd,0x12345678)
        return struct.unpack('<I',u.mem_read(cell,4))[0]
    assert call(5,False)==95
    assert call(6,False)==31
    assert len(notifications)==2
    assert call(6,False)==31 and len(notifications)==2
    assert call(5,True)==63 and call(6,True)==127
    u.mem_write(cell+12,b'\x01')
    assert call(5,False)==95
    count=len(notifications)
    assert call(5,True)==95 and len(notifications)==count,'native global lock was not respected'
    report={'native_instructions':'actual retained capture','downstream_network_queue':'intercepted boundary',
            'fingerprints_checked':len(list(functions.items())),'setter_abi_verified':True,
            'zone_5_6_only':True,'entity_network_and_index_distinct':True,'idempotence':True,
            'native_global_lock_refusal':True,'notifications':notifications,
            'game_launched':False,'real_network_delivery':'unverified'}
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(report,indent=2)+'\n')
    print('PASS captured-native emulation: exact ABI, two bits, network arguments, idempotence, global lock')

if __name__=='__main__':main()
