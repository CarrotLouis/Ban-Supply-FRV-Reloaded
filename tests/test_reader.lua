local ffi=require('ffi')
local Reader=require('reader')
local profile=require('profile')
local checks=0
local function expect(value,label)assert(value,label);checks=checks+1 end
local regions={}
local function addr(p)return tonumber(ffi.cast('uintptr_t',p)) end
local function allocate(size)
    local buffer=ffi.new('uint8_t[?]',size)
    local pointer=ffi.cast('uint8_t *',buffer)
    regions[#regions+1]={at=addr(pointer),size=size,buffer=buffer}
    return pointer
end
local function overlay(pointer,bytes)
    local buffer=ffi.new('uint8_t[?]',#bytes);ffi.copy(buffer,bytes,#bytes)
    regions[#regions+1]={at=addr(pointer),size=#bytes,buffer=buffer}
end
local function u32(value)
    local b=ffi.new('uint32_t[1]',value)
    return ffi.string(b,4)
end
local function put32(p,offset,value) ffi.copy(p+offset,u32(value),4) end
local function putptr(p,offset,value)
    local b=ffi.new('uintptr_t[1]',ffi.cast('uintptr_t',value));ffi.copy(p+offset,b,8)
end
local function ptrbytes(p)
    local b=ffi.new('uintptr_t[1]',ffi.cast('uintptr_t',p));return ffi.string(b,8)
end
local function hashbytes(hex)
    return hex:gsub('..',function(s)return string.char(tonumber(s,16))end):reverse()
end
local function ent(resource,id,unit,net,owned)
    return hashbytes(resource)..u32(id)..u32(unit)..u32(net)..u32(owned and 1 or 0)
end
local function map(id,index)
    local rows=allocate(8*8)
    for i=0,7 do put32(rows,i*8,0xffffffff);put32(rows,i*8+4,0xffffffff) end
    put32(rows,(id%8)*8,id);put32(rows,(id%8)*8+4,index)
    return ptrbytes(rows)..u32(8)..u32(0xffffffff)..u32(1)
end
local game=allocate(8)
local mission,entities,players,avatars=allocate(0x44),allocate(16),allocate(0x400),allocate(0x160)
local collection,seater,interactable=allocate(0x58),allocate(0x50),allocate(0x14080)
local transport,user=allocate(0x58),allocate(0xb3a0)
put32(transport,8,2) -- no active delivery until the spawn-specific cases
local globals={mission=mission,entities=entities,player=players,avatar=avatars,
               collection=collection,seater=seater,interactable=interactable,transport=transport,user=user}
for name,p in pairs(globals)do overlay(game+profile.globals[name],ptrbytes(p)) end
put32(mission,8,888);put32(mission,64,2)
put32(players,0x84,1);put32(players,0x88,1);put32(players,0x3a8,77)
local peer=string.char(0x12,0x34,0x56,0x78,0xf0,0xde,0xbc,0x9a)
ffi.copy(user+0xb398,peer,8);ffi.copy(players+0x2c8,peer,8)
local avatar_bytes=ent(profile.avatar_resource,13,901,44,true)
local vehicle_bytes=ent(profile.vehicle_resource,54,902,321,true)
overlay(entities+profile.entity_map,map(77,3))
overlay(entities+profile.entity_records+3*24,avatar_bytes)
local avatar,vehicle=allocate(24),allocate(24)
ffi.copy(avatar,avatar_bytes,24);ffi.copy(vehicle,vehicle_bytes,24)
put32(avatars,0x6c,1);putptr(avatars,0x110,avatar)
local seater_records,seater_states=allocate(8),allocate(64)
putptr(seater_records,0,avatar)
put32(seater,8,1);put32(seater,12,1);put32(seater,16,1)
ffi.copy(seater+0x20,map(13,0),20)
putptr(seater,0x38,seater_records);putptr(seater,0x48,seater_states)
put32(seater_states,0,54);put32(seater_states,8,1)
local collection_records,collection_states=allocate(8),allocate(100)
putptr(collection_records,0,vehicle);put32(collection_states,0,27)
put32(collection,8,1);put32(collection,12,1);put32(collection,16,1)
ffi.copy(collection+0x20,map(54,0),20)
putptr(collection,0x38,collection_records);putptr(collection,0x48,collection_states)
local interaction_records,interaction_states,interaction_flags=allocate(8),allocate(0x370),allocate(16)
putptr(interaction_records,0,vehicle)
put32(interactable,0x14038,1);put32(interactable,0x14040,1);put32(interactable,0x14044,1)
ffi.copy(interactable+0x14050,map(54,0),20)
putptr(interactable,0x14068,interaction_records);putptr(interactable,0x14070,interaction_states)
putptr(interactable,0x14078,interaction_flags)
put32(interaction_states,0x340,7)
for i,v in ipairs(profile.zone_types)do put32(interaction_states,(i-1)*0x68+0x44,v) end
for _,z in ipairs(profile.reload_zones)do ffi.copy(interaction_states+z*0x68+0x5c,profile.default_timer,4) end
put32(interaction_flags,0,127)
put32(interaction_flags,4,96)
local memory={
    read=function(p,n)
        local start=addr(p)
        for i=#regions,1,-1 do
            local r=regions[i]
            if start>=r.at and start+n<=r.at+r.size then
                return ffi.string(r.buffer+start-r.at,n)
            end
        end
        return nil
    end,
    pointer=function(bytes,offset)
        offset=offset or 0
        if not bytes or #bytes<offset+8 then return nil end
        local cell=ffi.new('uintptr_t[1]');ffi.copy(cell,bytes:sub(offset+1,offset+8),8)
        if tonumber(cell[0])<65536 then return nil end
        return ffi.cast('uint8_t *',cell[0])
    end,
}
local reader=Reader.new(memory,game,profile)
local snapshot=reader:capture({})
expect(snapshot.active and snapshot.vehicles[54].driver.is_local,'local handle resolves to entity ID, not unit')
expect(snapshot.vehicles[54].driver.stable,'role 1 / node 0 is the settled driver')
expect(snapshot.vehicles[54].network_unit==321,'network unit is preserved separately from entity ID')
expect(snapshot.vehicles[54].owned,'ownership needs no pending-handoff map or timing window')
local interaction=reader:interaction(snapshot.vehicles[54])
expect(interaction.mask==127 and interaction.owned and interaction.index==0,'instance mask and identity are validated')
expect(interaction.delayed==96 and interaction.network_unit==321,'vanilla recovery mask and fresh network unit')
expect(#interaction.timers==2 and interaction.timers[1].data==profile.default_timer
       and interaction.timers[2].at==interaction_states+6*0x68+0x5c,'only the two instance-local timers are resolved')
local old_vehicle=snapshot.vehicles[54]
put32(vehicle,16,654);put32(vehicle,20,0)
snapshot=reader:capture({[54]={}})
expect(snapshot.vehicles[54].key==old_vehicle.key and not snapshot.vehicles[54].owned,
       'ownership and network ID changes preserve stable vehicle identity')
interaction=reader:interaction(old_vehicle)
expect(interaction.network_unit==654 and not interaction.owned,'stale snapshot resolves fresh network ID after transfer')
put32(vehicle,12,903)
expect(not pcall(reader.interaction,reader,old_vehicle),'changed unit generation rejects stale vehicle')
put32(vehicle,12,902);put32(vehicle,16,321);put32(vehicle,20,1)
snapshot=reader:capture({[54]={}})
put32(interaction_states,6*0x68+0x44,19)
expect(not pcall(reader.interaction,reader,snapshot.vehicles[54]),'unknown zone layout is refused')
put32(interaction_states,6*0x68+0x44,21)
put32(interaction_states,0x340,8)
expect(not pcall(reader.interaction,reader,snapshot.vehicles[54]),'unknown zone count is refused')
put32(interaction_states,0x340,7)
put32(seater,12,0);put32(seater,16,0)
snapshot=reader:capture({[54]={}})
expect(snapshot.vehicles[54] and not snapshot.vehicles[54].driver,'empty protected car remains in the observation')
put32(players,0x88,0)
snapshot=reader:capture({[54]={}})
expect(snapshot.active and snapshot.vehicles[54],'local death / respawn does not discard a protected car')
-- A spawned car is discovered through its exact native delivery, with no
-- driver, tracked ticket or current local avatar. Player ID 79 is NOT avatar 13.
local player=allocate(24);ffi.copy(player,ent('123456789abcdef0',79,910,411,true),24)
putptr(players,0xe8,player)
local aircraft=allocate(24)
ffi.copy(aircraft,ent(profile.transport_resource,99,911,412,true),24)
local delivery_records,delivery_elements=allocate(16),allocate(128)
putptr(delivery_records,0,aircraft)
putptr(transport,0x38,delivery_records);putptr(transport,0x40,delivery_elements)
put32(transport,12,1);put32(transport,16,1)
ffi.copy(delivery_elements,hashbytes(profile.vehicle_resource),8)
put32(delivery_elements,8,54);put32(delivery_elements,0x18,13)
snapshot=reader:capture({})
local _,delivery=next(snapshot.deliveries)
expect(delivery and delivery.caller==13 and delivery.peer==peer and delivery.cargo==54,
       'native delivery links exact cargo and historical caller AVATAR, preserving full 64-bit peer bytes')
expect(snapshot.vehicles[54] and not snapshot.vehicles[54].driver,
       'called FRV discovered without driving or a previous ticket')
expect(snapshot.reads<768,'spawn discovery stays inside the bounded read budget')
put32(delivery_elements,8,0)
snapshot=reader:capture({})
expect(next(snapshot.deliveries) and not next(snapshot.vehicles),'pending call observed before cargo exists')
put32(delivery_elements,8,0xffffffff)
snapshot=reader:capture({})
local _,pending=next(snapshot.deliveries)
expect(pending and not pending.cargo,'native invalid cargo sentinel is not an entity')
put32(delivery_elements,8,54);put32(delivery_elements,0x18,79)
snapshot=reader:capture({})
expect(not next(snapshot.deliveries) and not next(snapshot.vehicles),'Player entity ID cannot be mistaken for the caller avatar')
put32(delivery_elements,0x18,80)
snapshot=reader:capture({})
expect(not next(snapshot.deliveries),'host authority does not attribute a teammate call to the host')
put32(delivery_elements,0x18,13);put32(aircraft,20,0);put32(transport,16,0)
snapshot=reader:capture({})
expect(not next(snapshot.deliveries),'unowned remote transport copy is not a local call')
putptr(transport,0x40,ffi.cast('uint8_t *',0))
snapshot=reader:capture({[54]={}})
expect(snapshot.vehicles[54] and not next(snapshot.deliveries),
       'guest with only remote transports needs no local transport-state array and keeps driving reader usable')
putptr(transport,0x40,delivery_elements)
put32(aircraft,20,1);put32(transport,16,1)
ffi.copy(delivery_elements,hashbytes('123456789abcdef0'),8)
snapshot=reader:capture({})
expect(not next(snapshot.deliveries),'normal FRVs, mechs and other cargo are excluded by resource')
ffi.copy(delivery_elements,hashbytes(profile.vehicle_resource),8)
ffi.copy(aircraft,ent('123456789abcdef0',99,911,412,true),24)
snapshot=reader:capture({})
expect(not next(snapshot.deliveries),'non-Pelican transport component is not accepted as this delivery')
ffi.copy(aircraft,ent(profile.transport_resource,99,911,412,true),24)
ffi.copy(vehicle,ent('123456789abcdef0',54,902,321,true),24)
snapshot=reader:capture({})
expect(next(snapshot.deliveries) and not snapshot.vehicles[54],'cargo entity must independently match Supply FRV resource')
ffi.copy(vehicle,vehicle_bytes,24)
local foreign_peer=string.rep('\x11',8)
ffi.copy(players+0x2c8,foreign_peer,8);ffi.copy(players+0x300,peer,8)
putptr(players,0xf0,player);put32(players,0x84,2)
put32(players,0x3a8,0x7fff);put32(players,0x3c8,77);put32(players,0x88,1)
put32(seater,12,1);put32(seater,16,1)
snapshot=reader:capture({})
expect(snapshot.vehicles[54] and next(snapshot.deliveries),'local caller can be a guest in any roster slot')
expect(snapshot.vehicles[54].driver.is_local,'guest driving uses matching peer slot, never assumed roster slot zero')
put32(players,0x84,1);ffi.copy(players+0x2c8,peer,8)
put32(players,0x3a8,77);put32(players,0x88,0);put32(seater,12,0);put32(seater,16,0)
local respawned=ent(profile.avatar_resource,14,913,45,true)
overlay(entities+profile.entity_records+3*24,respawned);ffi.copy(avatar,respawned,24)
put32(players,0x88,1)
snapshot=reader:capture({})
expect(next(snapshot.deliveries) and snapshot.vehicles[54],
       'a new local avatar does not lose the old avatar call already in flight')
overlay(entities+profile.entity_records+3*24,avatar_bytes);ffi.copy(avatar,avatar_bytes,24)
put32(players,0x88,0)
local second_aircraft=allocate(24)
ffi.copy(second_aircraft,ent(profile.transport_resource,100,912,413,true),24)
putptr(delivery_records,8,second_aircraft);ffi.copy(delivery_elements+64,delivery_elements,64)
put32(transport,12,2);put32(transport,16,2)
local unambiguous,ambiguity=pcall(reader.capture,reader,{})
expect(not unambiguous and ambiguity:find('ambiguous Supply FRV delivery',1,true),
       'two local sources claiming one cargo are rejected as ambiguous')
put32(transport,12,1);put32(transport,16,1)
local original_source_read=memory.read
memory.read=function(at,n)
    local raw=original_source_read(at,n)
    if at==delivery_elements and n==64 then put32(delivery_elements,0x18,80) end
    return raw
end
expect(not pcall(reader.capture,reader,{}),'changing delivery source cannot publish a mixed caller/cargo snapshot')
memory.read=original_source_read;put32(delivery_elements,0x18,13)
put32(transport,12,3)
expect(not pcall(reader.capture,reader,{}),'impossible delivery counts are rejected')
put32(transport,12,1)
ffi.copy(user+0xb398,foreign_peer,8);ffi.copy(players+0x2c8,foreign_peer,8)
snapshot=reader:capture({})
expect(not next(snapshot.deliveries),'a changed session peer cannot reuse another session caller history')
ffi.copy(user+0xb398,peer,8);ffi.copy(players+0x2c8,peer,8)
put32(transport,12,0);put32(transport,16,0)
put32(mission,8,0)
snapshot=reader:capture({[54]={}})
expect(not snapshot.active,'ship / mission exit does not inspect cars')
put32(mission,8,888)
local original_read=memory.read
local reads=0
memory.read=function(p,n)
    local bytes=original_read(p,n);reads=reads+1
    if reads==7 then put32(mission,8,889) end
    return bytes
end
expect(not pcall(reader.capture,reader,{[54]={}}),'mixed-generation observations are rejected')
print('PASS reader: '..checks..' guarded binary-layout checks')
