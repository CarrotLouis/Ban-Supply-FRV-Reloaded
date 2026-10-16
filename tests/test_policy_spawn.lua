local Policy=require('policy')
local checks=0
local function expect(value,label)assert(value,label);checks=checks+1 end
local local_driver={identity='local avatar',is_local=true,stable=true}
local remote_driver={identity='unmodded avatar',is_local=false,stable=true}
local function car(id,owned,driver)
    return {id=id,key='mission/vehicle/'..id,owned=owned~=false,driver=driver}
end
local function source(key,cargo)return {key=key,caller=79,cargo=cargo}end
local function fixture()
    local masks,calls,clocks={},{},{}
    local action={}
    function action:apply(v,enabled)
        assert(v.owned,'cannot publish to a remote owner')
        calls[#calls+1]={kind='apply',id=v.id,enabled=enabled}
        if v.fail then return false,false,'not ready' end
        local changed=masks[v.id]~=enabled
        masks[v.id]=enabled;clocks[v.id]=not enabled
        return true,changed
    end
    function action:release_local(v)
        calls[#calls+1]={kind='cleanup',id=v.id};clocks[v.id]=false;return true,true
    end
    function action:reset()end
    function action:forget(key)end
    local policy=Policy.new(action)
    local function step(enabled,sources,...)
        local vehicles={};for _,v in ipairs({...})do vehicles[v.id]=v end
        local deliveries={};for _,d in ipairs(sources or{})do deliveries[d.key]=d end
        policy:step({active=true,context='mission',vehicles=vehicles,deliveries=deliveries},enabled)
    end
    return policy,masks,calls,clocks,step
end
do
    local p,masks,calls,clocks,step=fixture()
    step(true,{})
    step(true,{source('call A')})
    expect(#calls==0 and p.deliveries['call A'].eligible,'ON call armed before any cargo or driver exists')
    step(true,{source('call A',1)},car(1),car(2))
    expect(masks[1]==false and p.tracked[1] and clocks[1],'delivered local-call FRV is immediately protected with no driver')
    expect(masks[2]==nil,'unrelated map/teammate vehicle is untouched')
    expect(p.deliveries['call A'].done,'delivery consumed once after successful activation')
    step(false,{},car(1))
    expect(masks[1]==false and p.tracked[1],'departed Pelican and OFF on foot retain vehicle protection')
end
do
    local p,masks,calls,clocks,step=fixture()
    step(true,{})
    step(true,{source('fast',3)},car(3))
    expect(masks[3]==false,'new call first observed with cargo already ready still activates')
    step(true,{source('fast',3)},car(3,false,remote_driver))
    expect(not p.tracked[3] and not clocks[3] and calls[#calls].kind=='cleanup',
           'unmodded takeover releases only old local clocks for vanilla restoration')
    local n=#calls
    step(true,{source('fast',3)},car(3,false))
    expect(#calls==n,'remaining original delivery metadata never re-arms after remote takeover')
    step(true,{source('fast',3)},car(3))
    expect(#calls==n and not p.tracked[3],'original caller does not re-ban a restored empty car after authority returns')
    step(true,{source('fast',3)},car(3,true,local_driver))
    expect(p.tracked[3] and masks[3]==false,'enabled driving can intentionally protect the same car again')
end
do
    local p,masks,calls,clocks,step=fixture()
    step(false,{})
    step(false,{source('OFF call')})
    step(true,{source('OFF call',4)},car(4))
    expect(masks[4]==nil and not p.tracked[4],'turning ON after an OFF call cannot replay it at delivery')
    step(true,{source('OFF call',4)},car(4,true,local_driver))
    expect(masks[4]==false,'existing ON-driving trigger remains available for an OFF-origin call')
end
do
    local p,masks,calls,clocks,step=fixture()
    step(true,{})
    step(true,{source('ON call')})
    step(false,{source('ON call',5)},car(5))
    expect(masks[5]==false,'ON call retains its sampled eligibility during flight when caller later turns OFF on foot')
    step(false,{source('ON call',5)},car(5,true,local_driver))
    expect(masks[5]==true and not p.tracked[5],'OFF driver overrides original call protection')
    step(true,{source('ON call',5)},car(5))
    expect(masks[5]==true,'spent call cannot re-ban after an OFF driver leaves')
end
do
    local p,masks,calls,clocks,step=fixture()
    step(true,{})
    step(true,{source('pending')})
    step(true,{source('pending',6)},car(6,false))
    expect(#calls==0 and not p.deliveries.pending.done,'new cargo waits for authority instead of taking ownership')
    local broken=car(6);broken.fail=true
    step(true,{source('pending',6)},broken)
    expect(not p.deliveries.pending.done and p.held=='not ready','not-ready interaction keeps delivery eligible for retry')
    step(true,{source('pending',6)},car(6))
    expect(masks[6]==false and p.deliveries.pending.done,'interaction readiness retry protects without driving')
end
do
    local p,masks,calls,clocks,step=fixture()
    step(true,{})
    step(true,{source('already driven')})
    step(true,{source('already driven',7)},car(7,false,remote_driver))
    expect(#calls==0 and p.deliveries['already driven'].done,'already-controlled remote cargo is never overridden by original call')
    step(false,{source('driven OFF')})
    step(false,{source('driven OFF',8)},car(8,true,local_driver))
    expect(masks[8]==true,'OFF local driver always restores, irrespective of spawn metadata')
end
do
    local p,masks,calls,clocks,step=fixture()
    step(true,{source('pre-existing',9)},car(9))
    expect(masks[9]==nil,'initial baseline does not replay a previously delivered car')
    step(true,{source('new A'),source('new B')},car(9))
    step(true,{source('new A',10),source('new B',11)},car(9),car(10),car(11))
    expect(masks[10]==false and masks[11]==false and masks[9]==nil,'two new independent calls protect only their exact cargo')
    step(true,{},car(10),car(11))
    expect(not next(p.deliveries) and p.tracked[10] and p.tracked[11],'delivery metadata can expire without lifting either ban')
    p:step({active=false},true)
    expect(not next(p.tracked) and not next(p.deliveries),'mission exit clears both source and vehicle state')
end
print('PASS spawn policy: '..checks..' behavioral checks')
