# Ban Supply FRV Reloaded

绝地潜兵 2 的 Bingus Shared Loader Lua 模组，通过 ModOptionsMenu 提供一个**默认开启**的开关。

- 开启功能的人呼叫 M-103 补给 FRV 后，车辆生成并可交互时立即禁用两侧“为车载机枪重新补给”，无需先上车。
- 原有的驾驶触发仍保留：开启功能的人驾驶并控制另一辆补给 FRV，也会使该车生效。
- 限制逐车保存，空车、下车、死亡或驾驶另一辆车不主动撤销。
- 没有开启功能的人接管驾驶后恢复，包括未安装模组的队友。
- 已恢复的车不会因为旧的呼叫记录被反复禁用；开启者再次驾驶时可以重新生效。

依赖 [Bingus Shared Loader](https://github.com/CowboyBingus/BingusSharedLoader) 和
[ModOptionsMenu](https://github.com/CowboyBingus/ModOptionsMenu)。没有自定义按键。
安装包导入 HD2Arsenal，启用依赖并部署后重启游戏。开关位于
`ESC > MODS > Ban Supply FRV Reloaded`，修改后按 APPLY。

当前为 **0.2.0 测试版**，支持 Steam build **25480438**，其他版本拒绝修改。
交互采用禁用方式，灰色提示可能保留。车外关闭不会撤销已经生效的车；关闭功能后驾驶该车可以恢复。
开关在运输投放开始时读取，已经开始的投放不会因之后在车外关闭而取消。

## Status and behavior

Calling an M-103 Supply FRV while enabled protects its two mounted-gun resupply
interactions as soon as its cargo entity and interactions are ready. No driver
is required. The original drive-and-control trigger remains available.
Vanilla native takeover recovery handles an inactive new driver, including an
unmodded teammate. An enabled new driver renews the restriction.

The delivery reader joins the transport's exact spawned cargo ID to its caller's
avatar ID. Local peer identity selects the correct roster slot, and scene-bound
avatar history preserves attribution across death and respawn. No proximity or
spawn-time guess attributes teammate or map vehicles to the local player.
A call is consumed once, so its remaining transport record cannot fight a later
driver's restoration. The applied toggle is sampled when native transport starts.

**Offline verified; 0.2.0 live host/guest acceptance remains pending.** The tests
exercise actual addon Lua and captured native instructions with synthetic peer
memory and intercepted network transport. They do not establish real network
delivery or live game stability. See [validation](docs/VALIDATION.md).

## Project layout

```text
src/              Lua source and locked shared runtime modules
tests/            LuaJIT, Win32 and captured-native offline verification
scripts/          gated packaging, FFI audit and isolated manager verification
docs/             implementation evidence and live acceptance boundary
build/            ignored temporary assembly, fixtures and reports
outputs/          ignored installable and source ZIPs
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for Windows setup, build commands and the
source-sync workflow. [CHANGELOG.md](CHANGELOG.md) records behavior changes.
The installation guide in the mod ZIP is extracted from `src/entry.lua`.

```text
python -m pip install -r requirements-dev.txt
python scripts/build.py --validate-only
python scripts/build.py --loader <BingusSharedLoader-checkout> --source-bundle
```

Packaging uses the loader author's separately obtained `scripts/build_addon.py`
and `scripts/archive.py`. The builder never deploys to a game or manager profile.
Outputs, original game assets, memory captures, logs and build dependencies are
excluded from Git and source exports. The mod is MIT licensed; the unchanged
shared runtime files carry their original 0BSD notices.
