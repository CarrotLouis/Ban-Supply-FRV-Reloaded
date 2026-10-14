local ffi,bit=require('ffi'),require('bit')
local Native=require('native')
local actual=require('profile')
local checks=0
local function expect(value,label) assert(value,label);checks=checks+1 end
local function fixture()
    local game=ffi.new('uint8_t[64]')
    local buffer=ffi.new('uint8_t[16]')
    local timer_buffer=ffi.new('uint8_t[8]')
    local flags=ffi.cast('uint8_t *',buffer)
    local clocks=ffi.cast('uint8_t *',timer_buffer)
    local code='test native boundary';ffi.copy(game,code,#code)
    local profile={reload_zones={5,6},reload_mask=0x60,held_timer=actual.held_timer,
                   default_timer=actual.default_timer,delayed_property=actual.delayed_property,functions={}}
    for _,name in ipairs({'set_zone','queue_change','timer_update','receive_flags','initialize_zones'}) do
        profile.functions[name]={rva=0,length=#code,fingerprint=Native.fingerprint(code)}
    end
    local state={manager=ffi.cast('uint8_t *',game),flags=flags,clocks=clocks,
                 owned=true,identity='vehicle generation',network_unit=654}
    local function put(at,value) local b=ffi.new('uint32_t[1]',value);ffi.copy(at,b,4) end
    local function get(at) local b=ffi.new('uint32_t[1]');ffi.copy(b,at,4);return tonumber(b[0]) end
    put(flags,127);put(flags+4,1);put(flags+8,0x12345678)
    ffi.copy(clocks,actual.default_timer,4);ffi.copy(clocks+4,actual.default_timer,4)
    local calls,notifications,writes={},{},{}
    local memory={
        read=function(at,n) return ffi.string(at,n) end,
        write=function(at,bytes)
            assert(#bytes==4,'only one 32-bit field per checked write')
            assert(at==flags or at==flags+4 or at==state.clocks or at==state.clocks+4,'write outside target fields')
            if state.fail_write==at then state.fail_write=nil;return false end
            writes[#writes+1]={at=at,bytes=bytes};ffi.copy(at,bytes,4);return true
        end,
        writable_data=function(at,n) return at==flags and n==16 end,
    }
    local reader={interaction=function(self,v)
        return {manager=state.manager,flags=flags,mask=get(flags),delayed=get(flags+4),locked=flags[12]~=0,
                owned=state.owned,identity=state.identity,network_unit=state.network_unit,data=ffi.string(flags,16),
                timers={{zone=5,at=state.clocks,data=ffi.string(state.clocks,4)},
                        {zone=6,at=state.clocks+4,data=ffi.string(state.clocks+4,4)}}}
    end}
    local function call(manager,id,zone,enabled)
        assert(manager==state.manager and type(manager)=='cdata','pointer ABI')
        assert(id==548,'entity ID must not be network unit or manager index')
        calls[#calls+1]={zone=zone,enabled=enabled}
        local flag=bit.lshift(1,zone)
        put(flags,enabled and bit.bor(get(flags),flag) or bit.band(get(flags),bit.bnot(flag)))
        if state.foreign_change then put(flags,bit.bxor(get(flags),1)) end
    end
    local function notify(unit,property,at)
        assert(unit==654,'queue must use fresh network unit, not stale vehicle snapshot')
        assert(at==flags+(property==profile.delayed_property and 4 or 0),'native property field pointer')
        notifications[#notifications+1]={property=property,value=get(at)}
    end
    local action=Native.new(memory,game,profile,reader,call,notify)
    local vehicle={id=548,network_unit=321,key='mission/stable generation'}
    return action,vehicle,state,calls,notifications,writes,get,put,profile,memory,reader,call,notify,game
end
do
    local action,v,s,calls,queue,writes,get=fixture()
    local ok,changed=action:apply(v,false)
    expect(ok and changed and get(s.flags)==31,'both reload bits disabled; other zones preserved')
    expect(get(s.flags+4)==97,'both vanilla recovery bits armed; other pending bit preserved')
    expect(ffi.string(s.clocks,8)==actual.held_timer..actual.held_timer,'both local clocks held')
    expect(#calls==2 and calls[1].zone==5 and calls[2].zone==6,'exactly two native disable calls')
    expect(#queue==1 and queue[1].property==0x99901914 and queue[1].value==97,'delayed mask is replicated')
    local n=#writes
    ok,changed=action:apply(v,false)
    expect(ok and not changed and #writes==n and #calls==2 and #queue==1,'stationary lease makes zero writes/calls')
    ok,changed=action:apply(v,true)
    expect(ok and changed and get(s.flags)==127 and get(s.flags+4)==1,'OFF restores zones and releases ONLY our delay bits')
    expect(ffi.string(s.clocks,8)==actual.default_timer..actual.default_timer,'local clocks restored')
    expect(get(s.flags+8)==0x12345678 and s.flags[12]==0,'other flags preserved')
end
do
    local action,v,s,calls,queue,writes,get=fixture()
    action:apply(v,false)
    s.owned=false
    local n,c,q=#writes,#calls,#queue
    local ok=action:apply(v,true)
    expect(not ok and #writes==n and #calls==c and #queue==q,'remote-owned flags are never mutated, even on restore')
    ok=action:release_local(v)
    expect(ok and #writes==n+2 and #calls==c and #queue==q,'loss of authority resets ONLY local clocks')
    expect(get(s.flags)==31 and get(s.flags+4)==97,'old peer leaves replicated recovery state to new owner')
    expect(ffi.string(s.clocks,8)==actual.default_timer..actual.default_timer,'old peer can later reacquire with normal clocks')
    n=#writes;action:release_local(v)
    expect(#writes==n,'local cleanup is idempotent')
end
do
    local action,v,s,calls,queue,writes,get,put=fixture()
    put(s.flags,31);put(s.flags+4,97)
    local ok=action:apply(v,true)
    expect(ok and get(s.flags)==127 and get(s.flags+4)==1,'new OFF controller restores inherited lease without old ticket')
    put(s.flags,31);put(s.flags+4,1)
    ok=action:apply(v,false)
    expect(ok and get(s.flags+4)==97,'already disabled zones still need recovery armed')
end
do
    local action,v,s,calls,queue,writes,get,put=fixture()
    action:apply(v,false)
    -- No Lua step at all during an outgoing AND returning handoff.
    s.owned=true
    local ok=action:apply(v,true)
    expect(ok and get(s.flags)==127 and get(s.flags+4)==1,'OFF restores even after an entirely missed transfer cycle')
end
do
    local action,v,s,calls,queue,writes,get=fixture()
    s.fail_write=s.clocks+4
    local ok,changed,reason=action:apply(v,false)
    expect(not ok and reason:find('timer write failed',1,true),'checked partial timer write reports failure')
    expect(ffi.string(s.clocks,8)==actual.default_timer..actual.default_timer,'partial timer hold rolled back')
    expect(get(s.flags)==127 and get(s.flags+4)==1 and #calls==0 and #queue==0,'failure before arming leaves gameplay state untouched')
end
do
    local action,v,s,calls,queue,writes,get,put=fixture()
    put(s.flags,95);s.foreign_change=true
    local ok,_,reason=action:apply(v,false)
    expect(not ok and reason:find('unrelated vehicle',1,true),'read-back catches foreign enabled-bit changes')
    expect(ffi.string(s.clocks,8)==actual.default_timer..actual.default_timer,'failed zone update releases held clocks for vanilla recovery')
    expect(bit.band(get(s.flags+4),96)==96,'partial zone disable retains native recovery bits')
end
do
    local action,v,s,calls,queue,writes,get,put=fixture()
    action:apply(v,false);s.flags[12]=1
    local n=#calls
    local ok=action:apply(v,true)
    expect(ok and get(s.flags)==127 and get(s.flags+4)==1 and #calls==n,'OFF restores bits under ordinary global lock')
    expect(s.flags[12]==1 and get(s.flags+8)==0x12345678,'global lock and other flags stay unchanged')
    expect(queue[#queue-1].property==0x788b9753,'checked locked restoration uses native enabled property')
end
do
    local action,v,s,calls,queue,writes,get,put=fixture()
    action:apply(v,false)
    local previous=s.clocks
    local moved_buffer=ffi.new('uint8_t[8]');ffi.copy(moved_buffer,previous,8)
    s.clocks=ffi.cast('uint8_t *',moved_buffer);s.owned=false
    local ok=action:release_local(v)
    expect(ok and ffi.string(s.clocks,8)==actual.default_timer..actual.default_timer,'cleanup resolves relocated runtime clocks afresh')
    expect(ffi.string(previous,8)==actual.held_timer..actual.held_timer,'cleanup never writes a stale runtime pointer')
end
do
    local _,_,s,_,_,_,_,_,profile,memory,reader,call,notify,game=fixture()
    profile.functions.receive_flags.fingerprint=0
    expect(not pcall(Native.new,memory,game,profile,reader,call,notify),'changed native receiver is refused before any gameplay call')
end
expect(Native.fingerprint('hello')==0x4f9f2cab,'independent FNV-1a vector')
local held=ffi.new('float[1]');ffi.copy(held,actual.held_timer,4)
expect(held[0]>9.99e19 and held[0]<1.01e20,'held timer bytes encode finite float32 1e20')
print('PASS native boundary: '..checks..' checks')
