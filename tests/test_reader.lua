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
local globals={mission=mission,entities=entities,player=players,avatar=avatars,
               collection=collection,seater=seater,interactable=interactable}
for name,p in pairs(globals)do overlay(game+profile.globals[name],ptrbytes(p)) end
put32(mission,8,888);put32(mission,64,2)
put32(players,0x84,1);put32(players,0x88,1);put32(players,0x3a8,77)
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
