local Menu=require('menu')
local checks=0
local function expect(value,label) assert(value,label);checks=checks+1 end
local m=Menu.new(function()end)
ModOptionsMenu=nil
expect(not m:step() and m.enabled,'missing dependency leaves default ON but no activation')
local registrations=0
ModOptionsMenu={api=1,values={},register_option=function(id,spec)
    registrations=registrations+1
    assert(id==Menu.ID and spec.default==true and spec.type=='toggle','one ON toggle')
    assert(#spec.mod<=40 and #spec.label<=64 and #spec.description<=400,'real menu limits')
    ModOptionsMenu.values[id]=spec.default
    return true
end,get=function(id) return ModOptionsMenu.values[id] end,ready=function()return true end}
expect(m:step() and m.enabled and registrations==1,'late-loaded menu registers one default-ON toggle')
m:step();expect(registrations==1,'no duplicate registration')
ModOptionsMenu.values[Menu.ID]=false
expect(m:step() and not m.enabled,'applied OFF is read as boolean')
ModOptionsMenu.values[Menu.ID]=1
expect(not m:step(),'choice indexes are not accepted as toggle values')
ModOptionsMenu={api=1,register_option=function()return false,'full'end,get=function()return true end}
expect(not m:step(),'a refused option leaves gameplay inactive')
print('PASS menu: '..checks..' checks')
