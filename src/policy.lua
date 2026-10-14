-- The ban is a vanilla per-vehicle recovery lease. Losing authority releases
-- only our local clocks; the new owner's game recovers without our polling.
local M = {}
function M.new(action, log)
    log=log or function()end
    local self={tracked={},controls={},context=nil,held=nil}
    local function apply(vehicle,enabled,reason)
        local ok,changed,refusal=action:apply(vehicle,enabled)
        if ok and changed then log(reason..': vehicle '..vehicle.id) end
        if not ok then self.held=refusal or 'waiting for vehicle authority' end
        return ok
    end
    local function reset(context)
        self.tracked={};self.controls={};self.context=context
        action:reset()
    end
    function self:step(snapshot, enabled)
        self.held=nil
        if not snapshot.active then reset(nil);return end
        if self.context~=snapshot.context then reset(snapshot.context) end
        for id,ticket in pairs(self.tracked) do
            local vehicle=snapshot.vehicles[id]
            if not vehicle or vehicle.key~=ticket.key then
                self.tracked[id]=nil;action:forget(ticket.key)
            end
        end
        for id,control in pairs(self.controls) do
            local vehicle=snapshot.vehicles[id]
            if not vehicle or vehicle.key~=control.key or not vehicle.driver
                    or vehicle.driver.identity~=control.driver then self.controls[id]=nil end
        end
        for id,vehicle in pairs(snapshot.vehicles) do
            local driver,ticket=vehicle.driver,self.tracked[id]
            if ticket and not vehicle.owned then
                -- May be observed long after migration. Never restore replicated
                -- flags on a remote owner's behalf; release only local clocks.
                local ok,changed,reason=action:release_local(vehicle)
                if ok then
                    self.tracked[id]=nil;self.controls[id]=nil
                    if changed then log('local lease released; new owner handles resupply: vehicle '..id) end
                else self.held=reason or 'local recovery timer cleanup pending' end
            elseif driver and driver.is_local and driver.stable and vehicle.owned then
                if enabled then
                    if apply(vehicle,false,'reload blocked; native recovery armed') then
                        self.tracked[id]={key=vehicle.key,driver=driver.identity}
                        self.controls[id]={key=vehicle.key,driver=driver.identity,enabled=true}
                    end
                else
                    -- This also restores a ban inherited from another enabled
                    -- client: the new controller's OFF setting wins.
                    local control=self.controls[id]
                    if not control or control.enabled then
                        if apply(vehicle,true,'reload restored by disabled controller') then
                            self.tracked[id]=nil
                            self.controls[id]={key=vehicle.key,driver=driver.identity,enabled=false}
                        end
                    end
                end
            elseif ticket and vehicle.owned then
                -- Empty, passenger, gunner and entry before actual migration
                -- retain the ban. An OFF setting on foot also retains it.
                apply(vehicle,false,'reload retained; native recovery armed')
            end
        end
    end
    return self
end
return M
