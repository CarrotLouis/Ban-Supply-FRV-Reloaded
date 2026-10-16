-- Replicate disabled zones WITH their vanilla delayed-enable bits. Only this
-- owner's local timers are held. An unmodded new owner has ordinary timers, so
-- the game's existing update enables both zones without any addon callback.
-- No code hook, ownership request, custom RPC or shared definition edit.
local bit=require('bit')
local M={}
local function fingerprint(bytes)
    local value=bit.tobit(2166136261)
    for i=1,#bytes do
        value=bit.bxor(value,bytes:byte(i))
        value=bit.tobit(value+bit.lshift(value,1)+bit.lshift(value,4)+bit.lshift(value,7)
                       +bit.lshift(value,8)+bit.lshift(value,24))
    end
    return value<0 and value+4294967296 or value
end
M.fingerprint=fingerprint
local function u32_bytes(value)
    return string.char(bit.band(value,255),bit.band(bit.rshift(value,8),255),
                       bit.band(bit.rshift(value,16),255),bit.band(bit.rshift(value,24),255))
end

function M.new(memory,game,profile,reader,call,notify)
    for name,spec in pairs(profile.functions) do
        local bytes=memory.read(game+spec.rva,spec.length)
        assert(bytes and #bytes==spec.length and fingerprint(bytes)==spec.fingerprint,
               'native interaction function changed: '..name)
    end
    for _,name in ipairs({'set_zone','queue_change','timer_update','receive_flags','initialize_zones',
                          'delivery_caller','transport_caller','cargo_entity'}) do
        assert(profile.functions[name],'missing native interaction proof: '..name)
    end
    assert(type(memory.write)=='function','checked interaction writer unavailable')
    if not call then
        local setter=require('ffi').cast('void (*)(void *, uint32_t, uint32_t, uint8_t)',
                                         game+profile.functions.set_zone.rva)
        call=function(manager,id,zone,enabled) setter(manager,id,zone,enabled and 1 or 0) end
    end
    if not notify then
        local enqueue=require('ffi').cast('void (*)(uint32_t, uint32_t, void *)',
                                          game+profile.functions.queue_change.rva)
        notify=function(network_unit,property,at) enqueue(network_unit,property,at) end
    end
    -- Values and stable identities only. Resolve all addresses anew on release.
    local baselines={}
    local self={}
    local function key(vehicle) return assert(vehicle.key,'missing stable vehicle key') end
    local function timer_write(timer,value)
        if timer.data==value then return false end
        assert(memory.read(timer.at,4)==timer.data,'local resupply timer changed before write')
        assert(memory.write(timer.at,value),'checked local resupply timer write failed')
        assert(memory.read(timer.at,4)==value,'local resupply timer read-back failed')
        return true
    end
    local function publish_delay(state,value)
        if state.delayed==value then return false end
        assert(memory.read(state.flags,16)==state.data,'interaction flags changed before delay update')
        assert(memory.write(state.flags+4,u32_bytes(value)),'checked delayed-mask write failed')
        assert(memory.read(state.flags,16)==state.data:sub(1,4)..u32_bytes(value)..state.data:sub(9),
               'delay update changed another interaction flag')
        notify(state.network_unit,profile.delayed_property,state.flags+4)
        return true
    end
    function self:release_local(vehicle)
        local saved=baselines[key(vehicle)]
        if not saved then return true,false end
        local state=reader:interaction(vehicle)
        local changed=false
        for i,timer in ipairs(state.timers) do
            -- Never clobber a timer another operation has already replaced.
            if timer.data==profile.held_timer then changed=timer_write(timer,saved[i]) or changed end
        end
        baselines[key(vehicle)]=nil
        -- NO enabled-mask, delayed-mask, setter or network write after transfer.
        return true,changed
    end
    local function update(vehicle,enabled)
        local state=reader:interaction(vehicle)
        if not state.owned then return false,false,'waiting for local vehicle authority' end
        assert(memory.writable_data(state.flags,16),'interaction flags are not private writable data')
        local other=bit.band(state.mask,bit.bnot(profile.reload_mask))
        local other_delayed=bit.band(state.delayed,bit.bnot(profile.reload_mask))
        local changed=false
        if not enabled then
            local saved=baselines[key(vehicle)]
            if not saved then
                saved={}
                for i,timer in ipairs(state.timers) do
                    saved[i]=timer.data==profile.held_timer and profile.default_timer or timer.data
                end
                baselines[key(vehicle)]=saved
            end
            for _,timer in ipairs(state.timers) do changed=timer_write(timer,profile.held_timer) or changed end
            -- Arm recovery before disabling either zone. On a later failure,
            -- releasing our clocks leaves native recovery available.
            changed=publish_delay(state,bit.bor(state.delayed,profile.reload_mask)) or changed
        else
            -- Reacquiring with OFF also releases a lease inherited from a peer.
            local saved=baselines[key(vehicle)] or {}
            for i,timer in ipairs(state.timers) do
                if timer.data==profile.held_timer then
                    changed=timer_write(timer,saved[i] or profile.default_timer) or changed
                end
            end
        end
        for _,zone in ipairs(profile.reload_zones) do
            local is_enabled=bit.band(state.mask,bit.lshift(1,zone))~=0
            if is_enabled~=enabled then
                if enabled and state.locked then
                    -- Preserve the game's global lock while restoring our bits.
                    local fresh=reader:interaction(vehicle)
                    assert(fresh.owned,'vehicle authority changed during restore')
                    assert(memory.read(fresh.flags,16)==fresh.data,'interaction flags changed during restore')
                    assert(memory.write(fresh.flags,u32_bytes(bit.bor(fresh.mask,profile.reload_mask))),
                           'checked enabled-mask restoration failed')
                    notify(fresh.network_unit,0x788b9753,fresh.flags)
                    changed=true
                    break
                end
                call(state.manager,vehicle.id,zone,enabled)
                changed=true
            end
        end
        if enabled then
            local fresh=reader:interaction(vehicle)
            assert(fresh.owned,'vehicle authority changed during restore')
            changed=publish_delay(fresh,bit.band(fresh.delayed,bit.bnot(profile.reload_mask))) or changed
        end
        local result=reader:interaction(vehicle)
        assert(result.identity==state.identity,'vehicle changed during native interaction update')
        assert(bit.band(result.mask,bit.bnot(profile.reload_mask))==other,
               'unrelated vehicle interactions changed')
        assert(bit.band(result.delayed,bit.bnot(profile.reload_mask))==other_delayed,
               'unrelated delayed interactions changed')
        assert(result.data:sub(9)==state.data:sub(9),'another interaction flag changed')
        assert(bit.band(result.mask,profile.reload_mask)==(enabled and profile.reload_mask or 0),
               'native interaction setter refused')
        assert(bit.band(result.delayed,profile.reload_mask)==(enabled and 0 or profile.reload_mask),
               'native recovery lease not armed or released')
        if not enabled then
            for _,timer in ipairs(result.timers) do
                assert(timer.data==profile.held_timer,'native recovery timer not held')
            end
        else baselines[key(vehicle)]=nil end
        return true,changed
    end
    function self:apply(vehicle,enabled)
        local ok,accepted,changed,reason=pcall(update,vehicle,enabled)
        if ok then return accepted,changed,reason end
        -- Never strand indefinite local timers after a checked-write failure.
        -- Pending vanilla bits recover any partial zone disable.
        pcall(self.release_local,self,vehicle)
        return false,false,tostring(accepted)
    end
    function self:reset() baselines={} end
    function self:forget(vehicle_key) baselines[vehicle_key]=nil end
    return self
end
return M
