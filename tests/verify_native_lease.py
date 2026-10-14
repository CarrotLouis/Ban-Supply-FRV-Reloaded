"""Exercise actual addon Lua and retained native instructions in separate peers.

All addresses below are Unicorn memory, not Windows/game-process addresses.
The native setter, flags receiver, timer update and timer-initialization block
execute captured instructions. The downstream property queue is intercepted;
this verifies a transfer payload, not actual multiplayer transport.
"""
from pathlib import Path
import argparse, hashlib, json, os, struct, sys

ROOT=Path(__file__).resolve().parents[1]
if os.environ.get('HD2_LUPA_DIR'):
    sys.path.insert(0,os.environ['HD2_LUPA_DIR'])
from lupa.luajit21 import LuaRuntime
from unicorn import Uc, UC_ARCH_X86, UC_MODE_64, UC_HOOK_CODE
from unicorn.x86_const import (UC_X86_REG_RCX,UC_X86_REG_RDX,UC_X86_REG_R8,
    UC_X86_REG_R9,UC_X86_REG_RBX,UC_X86_REG_RDI,UC_X86_REG_RSP,UC_X86_REG_RIP,
    UC_X86_REG_XMM1)

ENABLED,DELAYED=0x788b9753,0x99901914

class Peer:
    def __init__(self,code,specs,owned=False):
        self.u=Uc(UC_ARCH_X86,UC_MODE_64)
        self.base=0x10000000
        self.manager,self.rows,self.records,self.flags,self.record,self.states=(
            0x30000000,0x40000000,0x41000000,0x42000000,0x43000000,0x44000000)
        self.index,self.id,self.unit=3,548,321
        self.cell=self.flags+self.index*16
        self.state=self.states+self.index*0x370
        self.stop,self.stack,self.payload=0x71000000,0x70002000,0x72000000
        for at,n in [(self.base+0x977000,0x2000),(self.base+0x980000,0x1000),
                     (self.base+0xfd9000,0x1000),(self.base+0x3483000,0x1000),
                     (self.manager,0x15000),(self.rows,0x1000),(self.records,0x1000),
                     (self.flags,0x1000),(self.record,0x1000),(self.states,0x2000),
                     (0x70000000,0x5000),(self.stop,0x1000),(self.payload,0x1000)]:
            self.u.mem_map(at,n)
        for spec in specs.values():
            rva,n=spec['rva'],spec['length']
            self.u.mem_write(self.base+rva,code[rva-0x1000:rva-0x1000+n])
        self.put32(self.base+0x3483c20,0xffffffff)
        self.put32(self.manager+0x14044,4)
        self.u.mem_write(self.manager+0x14050,struct.pack('<QIII',self.rows,8,0xffffffff,1))
        self.u.mem_write(self.manager+0x14068,struct.pack('<QQQ',self.records,self.states,self.flags))
        self.u.mem_write(self.rows,b'\xff'*64)
        self.u.mem_write(self.rows+(self.id%8)*8,struct.pack('<II',self.id,self.index))
        for i in range(4):
            self.u.mem_write(self.records+i*8,struct.pack('<Q',self.record+(0x100 if i!=self.index else 0)))
        self.put32(self.record+8,self.id);self.put32(self.record+16,self.unit)
        self.owned(owned)
        self.put32(self.state+0x340,7)
        for zone in range(7):
            self.u.mem_write(self.timer_at(zone),struct.pack('<f',-1 if zone in (5,6) else 1e20))
        self.notifications=[]
        self.lua=None
        def intercept(u,at,size,data):
            if at==self.base+specs['queue_change']['rva']:
                self.notify(u.reg_read(UC_X86_REG_RCX),u.reg_read(UC_X86_REG_RDX),u.reg_read(UC_X86_REG_R8))
                sp=u.reg_read(UC_X86_REG_RSP)
                ret=struct.unpack('<Q',u.mem_read(sp,8))[0]
                u.reg_write(UC_X86_REG_RSP,sp+8);u.reg_write(UC_X86_REG_RIP,ret)
        self.u.hook_add(UC_HOOK_CODE,intercept)

    def put32(self,at,n): self.u.mem_write(at,struct.pack('<I',n))
    def get32(self,at): return struct.unpack('<I',self.u.mem_read(at,4))[0]
    def timer_at(self,zone): return self.state+zone*0x68+0x5c
    def timers(self): return [bytes(self.u.mem_read(self.timer_at(z),4)) for z in (5,6)]
    def owned(self,value): self.put32(self.record+20,int(value))
    def blob(self): return bytes(self.u.mem_read(self.cell,16))
    def mask(self): return self.get32(self.cell)
    def delayed(self): return self.get32(self.cell+4)
    def notify(self,unit,prop,at):
        unit,prop,at=int(unit),int(prop),int(at)
        assert unit==self.unit and prop in (ENABLED,DELAYED)
        assert at==self.cell+(4 if prop==DELAYED else 0)
        self.notifications.append({'property':hex(prop),'value':self.get32(at),'network_unit':unit})
    def call(self,rva,args):
        self.u.mem_write(self.stack,struct.pack('<Q',self.stop))
        for register,value in args.items(): self.u.reg_write(register,int(value))
        self.u.reg_write(UC_X86_REG_RSP,self.stack)
        self.u.emu_start(self.base+rva,self.stop,count=10000)
        assert self.u.reg_read(UC_X86_REG_RIP)==self.stop,'native execution budget exceeded'
    def setter(self,manager,id,zone,enabled):
        assert int(manager)==self.manager and int(id)==self.id
        self.call(0x978610,{UC_X86_REG_RCX:self.manager,UC_X86_REG_RDX:self.id,
                         UC_X86_REG_R8:int(zone),UC_X86_REG_R9:int(enabled)})
    def frame(self):
        self.call(0x977fa0,{UC_X86_REG_RCX:self.manager,
                          UC_X86_REG_XMM1:struct.unpack('<I',struct.pack('<f',0.016))[0]})
    def receive(self,blob):
        self.u.mem_write(self.payload,blob);self.put32(self.payload+0x100,0)
        self.call(0x980020,{UC_X86_REG_RCX:self.manager,UC_X86_REG_RDX:self.id,
                          UC_X86_REG_R8:self.payload,UC_X86_REG_R9:self.payload+0x100})
        assert self.get32(self.payload+0x100)==16,'actual receiver consumed the flags payload'
    def initialize_timer(self,zone,value_bytes):
        # Execute the actual initialization copy at +97786F..+97787C. The
        # definition zone starts at component+8, RBX at definition-zone+0x10.
        definition=self.payload+0x200
        self.u.mem_write(definition+0x30,value_bytes)
        self.u.reg_write(UC_X86_REG_RBX,definition+0x10)
        self.u.reg_write(UC_X86_REG_RDI,self.state+zone*0x68+0x24)
        self.u.emu_start(self.base+0x97786f,self.base+0x97787c,count=3)
        assert bytes(self.u.mem_read(self.timer_at(zone),4))==value_bytes
    def install_addon(self):
        assert self.lua is None
        self.lua=LuaRuntime(encoding=None,unpack_returned_tuples=True)
        g=self.lua.globals()
        g[b'py_read']=lambda at,n: bytes(self.u.mem_read(int(at),int(n)))
        def write(at,body):
            at=int(at)
            assert len(body)==4 and at in (self.cell,self.cell+4,self.timer_at(5),self.timer_at(6))
            self.u.mem_write(at,body);return True
        g[b'py_write']=write
        g[b'py_writable']=lambda at,n: int(at)==self.cell and int(n)==16
        g[b'py_setter']=self.setter;g[b'py_notify']=self.notify
        g[b'addon_root']=str(ROOT).replace('\\','/').encode()
        for name,value in {'game':self.base,'manager':self.manager,'cell':self.cell,
                           'record':self.record,'state':self.state}.items(): g[name.encode()]=value
        self.lua.execute(b'''
            local ffi=require('ffi')
            local function ptr(at) return ffi.cast('uint8_t *',at) end
            local function num(at) return tonumber(ffi.cast('uintptr_t',at)) end
            package.path=addon_root..'/src/?.lua;'..package.path
            local Reader=require('reader')
            local profile=require('profile');profile.functions=require('functions')
            local memory={read=function(at,n)return py_read(num(at),n)end,
                write=function(at,bytes)return py_write(num(at),bytes)end,
                writable_data=function(at,n)return py_writable(num(at),n)end}
            local reader={interaction=function(self,v)
                local flags=py_read(cell,16)
                local descriptor=py_read(record,24)
                return {manager=ptr(manager),flags=ptr(cell),mask=Reader.u32(flags,0),
                    delayed=Reader.u32(flags,4),data=flags,locked=flags:byte(13)~=0,
                    owned=Reader.u32(descriptor,20)==1,identity='same-generation',
                    network_unit=Reader.u32(descriptor,16),timers={
                        {zone=5,at=ptr(state+5*0x68+0x5c),data=py_read(state+5*0x68+0x5c,4)},
                        {zone=6,at=ptr(state+6*0x68+0x5c),data=py_read(state+6*0x68+0x5c,4)}}}
            end}
            action=require('native').new(memory,ptr(game),profile,reader,
                function(manager,id,zone,enabled)py_setter(num(manager),id,zone,enabled)end,
                function(unit,prop,at)py_notify(unit,prop,num(at))end)
            vehicle={id=548,key='mission/same-generation',network_unit=111}
        ''')
    def addon_apply(self,enabled):
        result=self.lua.eval(b'function(enabled)return action:apply(vehicle,enabled)end')(enabled)
        assert result[0] is True,repr(result)
    def addon_release(self):
        result=self.lua.eval(b'function()return action:release_local(vehicle)end')()
        assert result[0] is True,repr(result)

def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('capture',type=Path)
    parser.add_argument('--frv-definition',type=Path,help='optional retained FRV component record; never packaged')
    parser.add_argument('--output',type=Path,default=ROOT/'build/native-lease-emulation.json')
    args=parser.parse_args(argv)
    code=(args.capture/'game.dll.01_00001000.bin').read_bytes()
    lua=LuaRuntime(encoding=None)
    lua.execute(('package.path='+repr(str(ROOT/'src/?.lua').replace('\\','/'))+"..';'..package.path").encode())
    specs={name.decode():{k.decode():v for k,v in spec.items()} for name,spec in lua.eval(b"require('functions')").items()}
    fingerprint=lua.eval(b"require('native').fingerprint")
    for name,spec in specs.items():
        rva,n=spec['rva'],spec['length']
        assert fingerprint(code[rva-0x1000:rva-0x1000+n])==spec['fingerprint'],name
    results=[]
    def passed(name):results.append(name)
    default=struct.pack('<f',-1);held=struct.pack('<f',1e20)
    initializer=Peer(code,specs)
    definitions=args.frv_definition.read_bytes() if args.frv_definition else None
    for z in (5,6):
        raw=definitions[8+z*136+0x30:8+z*136+0x34] if definitions else default
        assert raw==default,'retained FRV StartEnabledDelay must be -1'
        initializer.initialize_timer(z,raw)
    passed('actual native timer initialization copies local StartEnabledDelay=-1')

    # Negative control: reproduce v0.1.0's permanent inherited disabled mask.
    legacy=Peer(code,specs,True);legacy.receive(struct.pack('<IIII',31,0,0,0));legacy.frame()
    assert legacy.mask()==31 and legacy.delayed()==0
    passed('legacy disabled-mask-only transfer DOES NOT recover')

    owner=Peer(code,specs,True);owner.receive(struct.pack('<IIII',127,0,0,0))
    owner.install_addon();owner.addon_apply(False)
    assert owner.mask()==31 and owner.delayed()==96 and owner.timers()==[held,held]
    assert owner.notifications[0]['property']==hex(DELAYED)
    passed('actual addon Lua arms replicated recovery before captured native disable')
    count=len(owner.notifications)
    for _ in range(2400):owner.frame()
    owner.addon_apply(False)
    assert owner.mask()==31 and owner.delayed()==96 and owner.timers()==[held,held]
    assert len(owner.notifications)==count
    passed('empty owned vehicle persists for 2400 native frames without refresh or extra notifications')

    unmodded=Peer(code,specs)
    unmodded.receive(owner.blob())
    assert unmodded.timers()==[default,default]
    for _ in range(30):unmodded.frame()
    assert unmodded.mask()==31 and unmodded.delayed()==96
    passed('actual flags receive never imports held timers; unowned peer cannot restore')
    owner.owned(False) # Do NOT run old-owner Lua at all around the transfer.
    unmodded.owned(True);unmodded.frame()
    assert unmodded.lua is None and unmodded.mask()==127 and unmodded.delayed()==0
    assert [n['property'] for n in unmodded.notifications]==[hex(ENABLED),hex(DELAYED),hex(ENABLED),hex(DELAYED)]
    passed('unmodded new owner recovers BOTH zones with zero Lua on either side of handoff')

    owner.receive(unmodded.blob());owner.addon_release()
    assert owner.timers()==[default,default] and owner.mask()==127 and owner.delayed()==0
    passed('old owner cleanup changes only local clocks after transfer')
    owner.owned(True);owner.addon_apply(True);owner.frame()
    assert owner.mask()==127 and owner.delayed()==0
    passed('old client reacquiring with feature OFF keeps resupply enabled')

    owner.addon_apply(False);owner.owned(False)
    new_enabled=Peer(code,specs);new_enabled.receive(owner.blob());new_enabled.owned(True)
    new_enabled.install_addon();new_enabled.addon_apply(False);new_enabled.frame()
    assert new_enabled.mask()==31 and new_enabled.delayed()==96
    passed('enabled new controller renews lease even when inherited zones are already disabled')
    third=Peer(code,specs);third.receive(new_enabled.blob())
    new_enabled.owned(False);third.owned(True);third.frame()
    assert third.lua is None and third.mask()==127 and third.delayed()==0
    passed('ON driver to ON driver to unmodded driver recovers without polling window')

    off=Peer(code,specs);off.receive(owner.blob());off.owned(True);off.install_addon();off.addon_apply(True)
    assert off.mask()==127 and off.delayed()==0 and off.timers()==[default,default]
    passed('new installed-but-OFF controller explicitly restores inherited lease')
    for _ in range(5):
        owner.receive(third.blob());owner.owned(True);owner.addon_apply(False)
        third.owned(False);third.receive(owner.blob());owner.owned(False);third.owned(True);third.frame()
        assert third.mask()==127 and third.delayed()==0
        owner.addon_release()
    passed('five repeated transfers back to the same unmodded peer recover both zones')

    other=Peer(code,specs,True);other.receive(struct.pack('<IIII',117,4,0,0))
    other.install_addon();other.addon_apply(False)
    recipient=Peer(code,specs);recipient.receive(other.blob());recipient.owned(True);recipient.frame()
    assert recipient.mask()==117 and recipient.delayed()==4
    passed('unrelated enabled and delayed bits survive both addon disable and vanilla restore')

    report={'checks':len(results),'passed':results,'fingerprints_checked':len(specs),
            'source_sha256':{name:hashlib.sha256((ROOT/'src'/name).read_bytes()).hexdigest()
                             for name in ('native.lua','profile.lua','functions.lua')},
            'addon_lua':'actual src/native.lua on LuaJIT 2.1',
            'native_instructions':'actual retained capture in Unicorn',
            'native_timer_initialization_block':True,'retained_frv_definition_checked':definitions is not None,
            'native_unmodded_recovery':True,'lua_handoff_window_required':False,
            'downstream_property_queue':'intercepted boundary','real_network_delivery':'unverified',
            'game_launched':False,'live_profile_changed':False}
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(report,indent=2)+'\n')
    print('PASS native recovery lease:',len(results),'cases; actual addon Lua and native receive/update; unmodded recovery without handoff Lua')

if __name__=='__main__':main()
