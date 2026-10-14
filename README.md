# Ban Supply FRV Reloaded

A Bingus Shared Loader addon with one default-ON toggle in ModOptionsMenu.
It disables only the two mounted-gun resupply interactions on an M-103 Supply FRV
after the enabled local player drives and controls it. The per-vehicle state persists
when the vehicle is empty. An inactive new controller restores those interactions.
Grey disabled prompts may remain.

The installation instructions are embedded in `src/entry.lua` and extracted into the
mod ZIP as `README.txt`. Requires [Bingus Shared Loader](https://github.com/CowboyBingus/BingusSharedLoader)
and [ModOptionsMenu](https://github.com/CowboyBingus/ModOptionsMenu).

This is a **0.1.1 test candidate** for Steam build **25480438**.
Offline verification is separate from native-game and multiplayer acceptance.
See [docs/VALIDATION.md](docs/VALIDATION.md) for the remaining acceptance boundary.

## 0.1.1 交接恢复修复 / takeover recovery fix

用户实测和日志确认 0.1.0 会把禁用状态留给未安装模组的队友：旧版必须在
控制权交出前恢复交互，错过交接就无法再同步写回。
0.1.1 改为保留游戏自身的延迟恢复标记，仅延后启用者本地的两个恢复计时器。
没有开启功能的人接管时，其原版游戏恢复两侧交互，不要求队友安装模组。
空车、下车、死亡、换乘其他车辆仍保留原车效果；开关默认开启。
关闭功能后驾驶原车恢复，车外关闭不撤销已保护车辆。

The old release could miss the pre-transfer restoration window, leaving an
unmodded driver with a permanently disabled mask. The new release replicates the
game's ordinary delayed-enable bits and holds only the installing owner's local
timers. The new owner's unmodified timer update restores both zones. An enabled
new owner renews the ban, and an installed but OFF owner also restores it.
Neither an ownership-pending poll nor new-driver addon cooperation is required.

实际联机修复仍待验证。13 个离线场景运行了本模组真实 Lua 和捕获的游戏原生
指令，包括完全错过交接、无模组接管和重复交接；另有 Lua 回归检查车辆隔离。
This verifies instructions in emulated peer memory, with transport intercepted;
it does not establish actual multiplayer delivery or native execution in game.

Build dependencies: Python 3.12, `lupa==2.8`, and the loader author's separately
obtained `scripts/build_addon.py` and `scripts/archive.py`. Set `HD2_LUPA_DIR` when
using an existing Python dependency directory. Clone BingusSharedLoader beside this
repository, or pass its checkout with `--loader`.

```text
python tests/run.py
python scripts/build.py --validate-only
python scripts/build.py --source-bundle
python scripts/build.py --source-bundle --native-capture <retained-capture> --frv-definition <retained-frv-component>
```

Builds never modify a live game installation or manager profile. Raw game captures,
original assets and build-tool dependencies are excluded from source and mod packages.
