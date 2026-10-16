local VERSION='0.2.0'
local BUILD='0.2.0-callin.1'
local KEY='BanSupplyFRVReloaded'
if rawget(_G,KEY) then return rawget(_G,KEY) end
local api={version=VERSION,build=BUILD,enabled=true,status='waiting for ModOptionsMenu',steam_build=profile.steam_build}
rawset(_G,KEY,api)

local log_path=(os.getenv('LOCALAPPDATA') or '.')..'/CowboyBingus/Helldivers2/Logs/BanSupplyFRVReloaded.log'
local status_path=log_path:gsub('%.log$','-STATUS.txt')
local function log(line)
    local f=io.open(log_path,'ab')
    if f then f:write(os.date('!%Y-%m-%dT%H:%M:%SZ')..' '..line..'\r\n');f:close() end
end
local function status(value)
    local stamp=value..'/'..tostring(api.enabled)
    if api.status_stamp==stamp then return end
    api.status_stamp=stamp
    api.status=value;log('status: '..value)
    local f=io.open(status_path,'wb')
    if f then
        f:write('Ban Supply FRV Reloaded '..VERSION..'\r\n'..value..'\r\n',
                'Build: '..BUILD..'\r\n',
                'Steam build: '..profile.steam_build..'\r\n',
                'Enabled: '..tostring(api.enabled)..'\r\n');f:close()
    end
end
log('loaded v'..VERSION..'; build '..BUILD..'; default ON; expected Steam build '..profile.steam_build)
local menu=menu_module.new(log)
local elapsed,next_read,initialized,refused=0,0,false,false
local memory,controller,reader
local last_refusal,last_refusal_at=nil,-100
local function hold(reason)
    if reason~=last_refusal or elapsed-last_refusal_at>=30 then
        last_refusal,last_refusal_at=reason,elapsed;status('held: '..reason)
    end
end
local function initialize()
    memory=memory_module.new(runtime)
    local valid,reason=memory.verify_build(profile)
    if not valid then refused=true;status('unsupported game build: '..tostring(reason));return end
    write_module.extend(memory)
    local game=assert(memory.module('game.dll'),'game module not loaded')
    reader=reader_module.new(memory,game,profile)
    controller=policy_module.new(native_module.new(memory,game,profile,reader),log)
    initialized=true;status('ready; waiting for a Supply FRV call-in or driver')
end
local function step(dt)
    elapsed=elapsed+math.max(0,math.min(tonumber(dt) or 0,0.25))
    local ready=menu:step()
    api.enabled=menu.enabled
    if refused then return end
    if not ready then status('waiting for ModOptionsMenu');return end
    if elapsed<20 then status('startup grace');return end
    if not initialized then initialize();if not initialized then return end end
    if elapsed<next_read then return end
    -- Vanilla recovery survives transfers completed between Lua observations.
    -- Held float32 clocks do not need per-frame writes; observe at 10 Hz.
    next_read=elapsed+0.1
    local ok,reason=pcall(function()
        local snapshot=reader:capture(controller.tracked)
        controller:step(snapshot,api.enabled)
        local count=0;for _ in pairs(controller.tracked) do count=count+1 end
        api.tracked=count
        if controller.held then hold(controller.held) else
            status(snapshot.active and ('ready; protected vehicles: '..count..'; setting '..(api.enabled and 'ON' or 'OFF'))
                   or 'ready; outside mission')
        end
    end)
    if not ok then hold(tostring(reason)) end
end
api.guard=runtime.guard({name=KEY,step=step,log=log,
    stop=function(reason) status('stopped: '..tostring(reason)) end}):install()
return api

--[===[Ban Supply FRV Reloaded - quick guide

Ban Supply FRV Reloaded 0.2.0 (test build; call-in activation)

依赖 / Requirements
- Bingus Shared Loader v18 或更新版本 / v18 or newer
  https://github.com/CowboyBingus/BingusSharedLoader/releases/latest
- Mod Options Menu
  https://github.com/CowboyBingus/ModOptionsMenu/releases/latest
- 本测试版支持 Steam build 25480438；其他版本自动停止修改。
  This candidate supports Steam build 25480438. Other builds refuse gameplay changes.

安装与开关
1. 将本 ZIP 导入 HD2Arsenal，启用本模组及上述依赖，部署后重新启动游戏。
2. ESC > MODS > Ban Supply FRV Reloaded > Ban Supply FRV Reload。
3. 开关默认开启。修改后按 APPLY（键盘通常是 Tab）应用。

效果
开启后，你呼叫的 M-103 补给 FRV 在生成并可交互时即禁用左右两侧车载机枪补给，无需上车。
仍保留原有触发方式：你驾驶并取得控制权的其他补给 FRV 也会生效。
仅根据本次投放的呼叫者与实际货物实体关联识别；队友呼叫的车、地图原有车不会因此自动生效。
开关在运输投放开始时记录；车外关闭不撤销已启动投放或已生效车辆。关闭后驾驶该车可以恢复。
采用禁用交互方式；游戏可能仍显示灰色提示。上车、取补给和自动机枪本身不受本模组修改。
效果记在每辆车上：下车、乘坐其他座位、死亡和驾驶另一辆车都不会主动撤销原车效果。
没有开启本功能的新驾驶员接管时，由原版游戏恢复交互；未安装模组的队友也适用。
若新驾驶员也开启本功能，其模组会再次禁用交互。恢复不依赖原驾驶员抢在控制权交接前写回。
关闭开关时，你当前驾驶的车恢复；如果你在车外关闭，之前受影响的车会保留效果，直到重新接管。

Usage
Import this ZIP in HD2Arsenal, enable it and its two requirements, deploy, then restart the game.
Open ESC > MODS > Ban Supply FRV Reloaded. The single toggle defaults to ON; press APPLY to commit edits.
Calling an M-103 Supply FRV while enabled protects it as soon as its cargo entity and interactions are ready.
No driver is required. Driving and controlling another Supply FRV still activates protection as before.
The native delivery links its caller and exact cargo. Teammate deliveries and map vehicles are not auto-protected.
The applied toggle is sampled when native transport delivery starts. OFF on foot does not cancel a started delivery.
Grey prompts may remain. Seat entry, supply pickups and the automatic gun are unchanged.
The vehicle retains the effect when empty, after your death, and while you drive another vehicle.
A new controller without this feature restores resupply through vanilla game logic, including unmodded teammates.
An enabled new controller reapplies the ban. Recovery does not depend on the old driver's Lua handoff timing.
OFF restores the vehicle you currently drive. Turning OFF while on foot leaves previously affected cars protected
until someone controls them again.

验证与日志 / Validation and logs
本版已完成呼叫归属、无需驾驶、死亡复活、客机玩家槽位、交接恢复和安装包的离线检查。
原生指令仿真验证了投放关联、新触发与原版接管恢复；尚未完成 0.2.0 游戏内联机实测。
Actual addon Lua and captured native instructions verify delivery links, activation without a driver and takeover recovery.
This is offline verification. Live host/guest call-in behavior and actual network delivery remain pending for 0.2.0.

日志 / Log:
%LOCALAPPDATA%/CowboyBingus/Helldivers2/Logs/BanSupplyFRVReloaded.log
状态 / Status:
%LOCALAPPDATA%/CowboyBingus/Helldivers2/Logs/BanSupplyFRVReloaded-STATUS.txt

不包含共享加载器、菜单模组、原始游戏资源或额外 DLL。
The two requirements are installed separately. This package contains no original game assets or helper DLLs.
]===]
