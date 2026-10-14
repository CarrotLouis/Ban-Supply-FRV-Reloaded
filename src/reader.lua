-- No engine calls, process scans, data writes or retained raw pointers.
-- Every capture is bounded and rejected if the records change during the read.
local ffi, bit = require('ffi'), require('bit')
local M = {}

local function u32(bytes, offset)
    local a,b,c,d = bytes:byte(offset+1, offset+4)
    assert(d, 'short integer read')
    return a+b*256+c*65536+d*16777216
end
local function signed(n) return n >= 2147483648 and n-4294967296 or n end
local function hash(bytes)
    return bytes:reverse():gsub('.', function(c) return string.format('%02x', c:byte()) end)
end
local function entity(bytes)
    return {resource=hash(bytes:sub(1,8)), id=u32(bytes,8), unit=u32(bytes,12),
            network_unit=u32(bytes,16), owned=bit.band(u32(bytes,20),1)~=0,
            -- A network ID can change during migration; these 16 bytes cannot.
            identity=bytes:sub(1,16)}
end
M.u32, M.entity = u32, entity

function M.new(memory, game, profile)
    local self = {}
    local reads, guards
    local function read(at, size)
        reads = reads+1
        assert(reads <= 768, 'vehicle read budget exceeded')
        local bytes = memory.read(at,size)
        assert(bytes and #bytes == size, 'vehicle state unreadable')
        return bytes
    end
    local function keep(at, size)
        local bytes=read(at,size)
        guards[#guards+1]={at,bytes}
        return bytes
    end
    local function pointer(bytes, offset)
        return assert(memory.pointer(bytes,offset), 'invalid vehicle pointer')
    end
    local function global(name) return pointer(keep(game+profile.globals[name],8)) end
    local function check()
        for _,g in ipairs(guards) do
            assert(read(g[1],#g[2])==g[2], 'vehicle changed during observation')
        end
    end
    local function begin() reads, guards=0,{} end
    local function lookup(header,id,limit)
        local capacity,empty,mult=u32(header,8),u32(header,12),u32(header,16)
        if capacity==0 then return nil end
        assert(capacity <= limit and bit.band(capacity,capacity-1)==0, 'invalid vehicle map')
        local rows=pointer(header)
        local start=tonumber(ffi.cast('uint32_t',ffi.new('uint64_t',id)*ffi.new('uint64_t',mult)))
        for probe=0,math.min(capacity,64)-1 do
            local at=rows+bit.band(start+probe,capacity-1)*8
            local row=keep(at,8)
            if u32(row,0)==id then
                local index=u32(row,4)
                return index~=0xffffffff and index or nil
            end
            if u32(row,0)==empty then return nil end
        end
        error('vehicle map probe budget exceeded')
    end
    local function seats(name)
        local base=global(name)
        local count=keep(base+8,12)
        local capacity,active,owned=u32(count,0),u32(count,4),u32(count,8)
        assert(capacity<=256 and active<=capacity and owned<=active, 'invalid seat manager')
        return {base=base, active=active, map=keep(base+0x20,20),
                records=pointer(keep(base+0x38,8)), states=pointer(keep(base+0x48,8))}
    end

    function self:capture(tracked)
        begin()
        local mission=global('mission')
        local row=keep(mission,0x44)
        local value,phase=u32(row,8),u32(row,64)
        if value==0 or phase<1 or phase>7 then check(); return {active=false} end
        local entities=global('entities')
        local players=global('player')
        local counts=keep(players+0x84,8)
        local player_count,local_count=u32(counts,0),u32(counts,4)
        assert(player_count<=4 and local_count<=1, 'unsupported player counts')
        local local_entity
        if local_count>0 then
            local local_handle=u32(keep(players+0x3a8,20),0)
            if local_handle~=0x7fff then
                local local_index=lookup(keep(entities+profile.entity_map,20),local_handle,1048576)
                if local_index then
                    assert(local_index<262144,'invalid local avatar index')
                    local resolved=entity(keep(entities+profile.entity_records+local_index*24,24))
                    if resolved.resource==profile.avatar_resource and resolved.owned then local_entity=resolved end
                end
            end
        end

        local collection,seater=seats('collection'),seats('seater')
        local context=tostring(mission)..'/'..tostring(entities)..'/'..tostring(collection.base)..'/'..value
        local drivers, ids={},{}
        local avatars=global('avatar')
        local avatar_count=u32(keep(avatars+0x6c,4),0)
        assert(avatar_count<=8,'invalid avatar count')
        for i=0,avatar_count-1 do
            local avatar=entity(keep(pointer(keep(avatars+0x110+i*8,8)),24))
            assert(avatar.resource==profile.avatar_resource,'unexpected avatar identity')
            local index=lookup(seater.map,avatar.id,4096)
            if index and index<seater.active then
                local record=entity(keep(pointer(keep(seater.records+index*8,8)),24))
                assert(record.identity==avatar.identity,'seater identity changed')
                local state=keep(seater.states+index*64,64)
                local vehicle,role=u32(state,0),u32(state,8)
                local current,target=signed(u32(state,20)),signed(u32(state,24))
                local entering=state:byte(49)~=0
                local leaving=state:byte(52)~=0
                if vehicle~=0 and vehicle~=0xffffffff and role==1 and not leaving
                        and (current==0 or entering and target==0) then
                    assert(not drivers[vehicle],'ambiguous vehicle driver')
                    local is_local=local_entity~=nil and avatar.identity==local_entity.identity
                    drivers[vehicle]={id=avatar.id, identity=avatar.identity, is_local=is_local,
                                      stable=current==0 and not entering, entering=entering}
                    ids[vehicle]=true
                end
            end
        end
        local tracked_count=0
        for id in pairs(tracked or {}) do
            tracked_count=tracked_count+1
            assert(tracked_count<=32,'too many tracked supply vehicles')
            ids[id]=true
        end
        local vehicles={}
        for id in pairs(ids) do
            local index=lookup(collection.map,id,4096)
            if index and index<collection.active then
                local v=entity(keep(pointer(keep(collection.records+index*8,8)),24))
                assert(v.id==id,'vehicle identity changed')
                if v.resource==profile.vehicle_resource then
                    assert(u32(keep(collection.states+index*100,4),0)==profile.transition,
                           'supply vehicle seat layout changed')
                    assert(v.network_unit>0 and v.network_unit<0x7fff,'supply vehicle not networked')
                    v.driver=drivers[id]
                    v.key=context..'/'..v.identity
                    vehicles[id]=v
                end
            end
        end
        check()
        return {active=true,context=context,vehicles=vehicles,reads=reads}
    end

    -- Freshly resolve the per-instance interaction, including after compaction.
    -- Never use a manager index or pointer saved in a preceding frame.
    function self:interaction(vehicle)
        begin()
        local manager=global('interactable')
        local header=keep(manager+0x14038,72)
        local capacity,active,owned=u32(header,0),u32(header,8),u32(header,12)
        assert(capacity<=16384 and active<=capacity and owned<=active,'invalid interactable counts')
        local index=lookup(header:sub(25,44),vehicle.id,65536)
        assert(index and index<active,'supply interaction not ready')
        local records=pointer(header,48)
        local states=pointer(header,56)
        local flags=pointer(header,64)
        local current=entity(keep(pointer(keep(records+index*8,8)),24))
        assert(current.identity==vehicle.identity,'supply interaction identity changed')
        local state=states+index*0x370
        local zone_count=u32(keep(state+0x340,4),0)
        assert(zone_count==#profile.zone_types,'supply interaction zone count changed')
        for i,expected in ipairs(profile.zone_types) do
            assert(u32(keep(state+(i-1)*0x68+0x44,4),0)==expected,
                   'supply interaction zone type changed')
        end
        local at=flags+index*16
        local data=keep(at,16)
        local mask=u32(data,0)
        local delayed=u32(data,4)
        assert(mask<=255,'unexpected supply interaction enabled mask')
        assert(delayed<=255,'unexpected supply interaction delayed mask')
        local timers={}
        for _,zone in ipairs(profile.reload_zones) do
            local timer=state+zone*0x68+0x5c
            timers[#timers+1]={zone=zone,at=timer,data=keep(timer,4)}
        end
        check()
        return {manager=manager,flags=at,mask=mask,delayed=delayed,locked=data:byte(13)~=0,
                owned=current.owned,identity=current.identity,index=index,data=data,
                network_unit=current.network_unit,timers=timers}
    end
    return self
end
return M
