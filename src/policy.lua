-- The ban is a vanilla per-vehicle recovery lease. Losing authority releases
-- only our local clocks; the new owner's game recovers without our polling.
local M = {}
function M.new(action, log)
    log=log or function()end
    local self={tracked={},controls={},deliveries={},context=nil,held=nil}
    local function apply(vehicle,enabled,reason)
        local ok,changed,refusal=action:apply(vehicle,enabled)
        if ok and changed then log(reason..': vehicle '..vehicle.id) end
        if not ok then self.held=refusal or 'waiting for vehicle authority' end
        return ok
    end
    local function reset(context)
        self.tracked={};self.controls={};self.deliveries={};self.context=context
        action:reset()
    end
    function self:step(snapshot, enabled)
        self.held=nil
        if not snapshot.active then reset(nil);return end
        local baseline=self.context~=snapshot.context
        if baseline then reset(snapshot.context) end
        -- Capture the applied toggle when a call's transport is first observed,
        -- before its cargo exists. A later ON cannot replay an OFF delivery.
        local incoming=snapshot.deliveries or {}
        for key in pairs(self.deliveries) do
            if not incoming[key] then self.deliveries[key]=nil end
        end
        for key,source in pairs(incoming) do
            if not self.deliveries[key] then
                self.deliveries[key]={eligible=enabled and (not baseline or not source.cargo),done=false}
            end
        end
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
        for key,source in pairs(incoming) do
            local delivery=self.deliveries[key]
            local vehicle=source.cargo and snapshot.vehicles[source.cargo]
            if delivery.eligible and not delivery.done and vehicle then
                local driver=vehicle.driver
                -- A driver already controlling it takes precedence over the
                -- original caller. Never re-ban after an inactive takeover.
                if driver and (not driver.is_local or not enabled) then
                    delivery.done=true
                elseif vehicle.owned then
                    if self.tracked[vehicle.id] or apply(vehicle,false,'reload blocked on called Supply FRV; native recovery armed') then
                        self.tracked[vehicle.id]={key=vehicle.key,delivery=key}
                        delivery.done=true
                    end
                end
            end
        end
    end
    return self
end
return M
