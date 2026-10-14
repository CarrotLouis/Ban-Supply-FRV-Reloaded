local M={}
M.ID='carrotlouis.ban_supply_frv_reloaded.enabled'
function M.new(log)
    local self={enabled=true,host=nil,registered=false}
    function self:step()
        local host=rawget(_G,'ModOptionsMenu')
        if type(host)~='table' or host.api~=1 or type(host.register_option)~='function'
                or type(host.get)~='function' then return false end
        if self.host~=host then
            self.host=host
            local ok,accepted,reason=pcall(host.register_option,M.ID,{
                type='toggle',default=true,mod='Ban Supply FRV Reloaded',
                mod_id='carrotlouis.ban_supply_frv_reloaded',
                label='Ban Supply FRV Reload',
                description='While enabled, driving a Supply FRV disables its two gun resupply interactions. '
                    ..'The effect stays after you leave. A new driver without this feature, including an unmodded teammate, restores resupply. '
                    ..'With this option OFF, drive the vehicle again to restore gun resupply.'})
            self.registered=ok and accepted==true
            log(self.registered and 'menu: registered 1 of 1 options; default ON'
                or 'menu: registration refused: '..tostring(ok and reason or accepted))
        end
        if not self.registered then return false end
        local value=host.get(M.ID)
        if type(value)~='boolean' then return false end
        if self.enabled~=value then
            self.enabled=value
            log('setting applied: '..(value and 'ON' or 'OFF'))
        end
        return type(host.ready)~='function' or host.ready()==true
    end
    return self
end
return M
