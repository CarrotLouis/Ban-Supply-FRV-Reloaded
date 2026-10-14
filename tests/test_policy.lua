local Policy=require('policy')
local checks=0
local function expect(value,label) assert(value,label);checks=checks+1 end
local function car(id,driver,owned)
    return {id=id,key='mission/car/'..id,owned=owned~=false,driver=driver}
end
local local_driver={identity='player A',is_local=true,stable=true}
local remote_driver={identity='player B',is_local=false,stable=true}
local entering_remote={identity='player B',is_local=false,stable=false,entering=true}
local function fixture()
    local calls,masks,clocks={},{},{}
    local action={}
    function action:apply(v,enabled)
        assert(v.owned,'policy must never write remote-owned flags')
        calls[#calls+1]={id=v.id,kind='apply',enabled=enabled}
        if v.fail then return false,false,'refused' end
        local changed=masks[v.id]~=enabled
        masks[v.id]=enabled;clocks[v.id]=not enabled
        return true,changed
    end
    function action:release_local(v)
        calls[#calls+1]={id=v.id,kind='local cleanup'}
        if v.fail then return false,false,'cleanup refused' end
        clocks[v.id]=false;return true,true
    end
    function action:reset() end
    function action:forget(key) end
    local p=Policy.new(action)
    local function step(enabled,...)
        local vehicles={};for _,v in ipairs({...}) do vehicles[v.id]=v end
        p:step({active=true,context='mission',vehicles=vehicles},enabled)
    end
    return p,calls,masks,step,clocks
end
do
    local p,calls,masks,step=fixture()
    step(true,car(1,local_driver),car(2,nil))
    expect(masks[1]==false and masks[2]==nil,'only driven vehicle is banned')
    expect(p.tracked[1]~=nil,'activation creates per-vehicle ticket')
    step(true,car(1,nil),car(2,local_driver))
    expect(masks[1]==false and masks[2]==false,'driving B retains both independent bans')
    step(false,car(1,nil),car(2,nil))
    expect(masks[1]==false and masks[2]==false,'OFF on foot retains parked bans')
    step(false,car(1,local_driver),car(2,nil))
    expect(masks[1]==true and masks[2]==false,'OFF controlling A restores only A')
    local n=#calls;step(false,car(1,local_driver),car(2,nil))
    expect(#calls==n+1,'restored OFF driver is idle; only parked B serviced')
    step(true,car(1,local_driver),car(2,nil))
    expect(masks[1]==false,'ON while driving re-arms protection')
    step(true,car(1,entering_remote),car(2,nil))
    expect(masks[1]==false and p.tracked[1],'entry before actual control transfer retains protection')
    step(true,car(1,nil),car(2,nil))
    expect(masks[1]==false and p.tracked[1],'cancelled driver entry keeps original ban')
    step(true,car(1,remote_driver,false),car(2,nil))
    expect(p.tracked[1]==nil and calls[#calls-1].kind=='local cleanup','remote takeover only releases our local clocks')
    n=#calls;step(true,car(1,remote_driver,false),car(2,nil))
    expect(#calls==n+1,'old controller leaves new driver alone; only parked B serviced')
end
do
    local p,calls,masks,step=fixture()
    step(false,car(3,local_driver))
    expect(masks[3]==true and not p.tracked[3],'OFF restores inherited ban without old controller ticket')
    step(true,car(4,{identity='passenger',is_local=true,stable=false}))
    expect(masks[4]==nil,'entering local driver does not activate prematurely')
    step(true,car(5,local_driver,false))
    expect(masks[5]==nil,'no modification before local authority arrives')
    step(true,car(6,nil),car(7,remote_driver))
    expect(masks[6]==nil and masks[7]==nil,'uncontrolled vehicles remain untouched')
end
do
    local p,calls,masks,step,clocks=fixture()
    step(true,car(8,local_driver));step(true,car(8,nil))
    -- There is NO pending-handoff observation, Lua tick, or new avatar record.
    step(true,car(8,nil,false))
    expect(not p.tracked[8] and not clocks[8],'fully missed handoff still cleans local timer without driver discovery')
    expect(calls[#calls].kind=='local cleanup' and masks[8]==false,'no fictitious replicated restore after losing authority')
    local n=#calls;step(true,car(8,remote_driver,false))
    expect(#calls==n,'no retries against unmodded new owner')
    step(false,car(8,local_driver))
    expect(masks[8]==true,'later inactive reacquisition restores normally')
    step(true,car(8,local_driver))
    expect(masks[8]==false and clocks[8],'later enabled reacquisition re-arms lease')
end
do
    local p,calls,masks,step=fixture()
    local v=car(9,local_driver);v.fail=true;step(true,v)
    expect(not p.tracked[9] and p.held=='refused','failed activation is not reported as protected')
    v.fail=nil;step(true,v)
    local remote=car(9,remote_driver,false);remote.fail=true;step(true,remote)
    expect(p.tracked[9] and p.held=='cleanup refused','failed local cleanup retains retry ticket')
    remote.fail=nil;step(true,remote)
    expect(not p.tracked[9],'local cleanup retries without remote replicated writes')
end
do
    local p,calls,masks,step=fixture()
    step(true,car(10,local_driver))
    local replacement=car(10,nil);replacement.key='mission/new-generation/10'
    local n=#calls;step(true,replacement)
    expect(#calls==n and not p.tracked[10],'reused entity ID does not inherit another vehicle ban')
    step(true,car(11,local_driver));n=#calls;p:step({active=false},true)
    expect(next(p.tracked)==nil and #calls==n,'scene exit does not touch destroyed runtime state')
    step(true,car(12,local_driver))
    p:step({active=true,context='new mission',vehicles={[12]=car(12,nil)}},true)
    expect(next(p.tracked)==nil,'new scene forgets old tickets')
end
do
    local p,calls,masks,step=fixture()
    step(true,car(13,local_driver))
    -- New driver also has ON; old client must not fight its replicated ban.
    step(true,car(13,remote_driver,false))
    local n=#calls;step(false,car(13,remote_driver,false))
    expect(#calls==n and masks[13]==false,'remote ON controller owns its policy despite old client OFF')
end
print('PASS policy: '..checks..' behavioral checks')
