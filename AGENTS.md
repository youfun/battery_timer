# Working on battery_timer

改 `lib/`、`android/`、`c_src/` 之前读这份。和代码矛盾时同一轮改掉。

产品：**电量记录**（`com.example.battery_timer`）。启动、关闭、插电、拔电、充满、20%、充电 80%、标题旁「记录」各写一条 SQLite。没有计时器。

## 不要改 `deps/mob`

`Mob.Device.battery_*` 在 Android 仍是 TODO（`{:unknown, -1}`）。`deps.get` 会盖掉对 deps 的补丁。电量走项目静态 NIF `:battery`。

## 电量 NIF

```
BatteryTimer.Battery.read/1
  → BatteryTimer.Nifs.Battery.status/0
  → c_src/battery.c
  → JNI MobBridge.batterySnapshot()
  → sticky ACTION_BATTERY_CHANGED
```

返回 `{state, percent}`：`:charging | :full | :unplugged | :unknown`，0..100，读不到 `-1`。

改桥要一起动：

1. `MobBridge.batterySnapshot()` — `"state|percent"`
2. `beam_jni.c` `JNI_OnLoad` 缓存 `g_app_bridge_cls`（NIF 线程再 `FindClass` 找不到 `MobBridge`）
3. `c_src/battery.c` — `ERL_NIF_INIT(Elixir.BatteryTimer.Nifs.Battery, …)`，`-DSTATIC_ERLANG_NIF` / `LIBNAME=battery`
4. `lib/battery_timer/nifs/battery.ex` — `load_nif` 失败也 `:ok`（主机没有 `.so`）
5. `mob.exs` `static_nifs: [%{module: :battery, archs: [:android]}]`，然后 `mix mob.regen_driver_tab`

NIF 里不要等人。充电 / 20% / 80% 用屏幕 1s tick 对比上次 `state`/`percent`。后台靠 `BatteryMonitorService` 吊住进程。

## 后台 / 关闭

`BatteryMonitorService`：`foregroundServiceType=specialUse`，通知标题是电量百分比，动作「停止」。划掉或点停止才 `recordClose` + `stopSelf`。不要用 `mediaPlayback`。通知不能隐形。

`MainActivity` 销毁时如果服务还在跑，不要写 `app_close`。关闭时 Kotlin 写 `battery_samples` + `filesDir/battery_close.txt`；下次 `History.drain_close/0` 按时间戳去重。

## 语言

`:en` / `:zh`。首次读 `getprop persist.sys.locale` / `persist.sys.language`，再 `LANG`；不是中文就英文。标题旁 ZH/EN 写入 `Mob.State`。文案在 `BatteryTimer.I18n`。

## 数据

`battery_samples`：`recorded_at` UTC、`percent`、`state`、`elapsed_ms`、`reason`。库：`MOB_DATA_DIR/app.db`。界面用本地时区（`:calendar.universal_time_to_local_time/1`）。历史默认最近 3 个本地日。

reason：`app_start` / `app_close` / `plug` / `unplug` / `full` / `low_20` / `charge_80` / `manual`。

迁移不要 `Application.app_dir/2`。设备 BEAM 是平铺 `-pa`，`:code.priv_dir/1` 失败后 Ecto 会假装 “already up”。`BatteryTimer.App` 读 `MOB_BEAMS_DIR`。`mix mob.deploy` 不同步 `priv/`，新迁移必须打进 APK。

## 布局（Mob Android）

- `Column gap` 经常没间距，用 `<Spacer size={n} />`
- `Box` 默认撑满宽，除非 `width` 是数字；内容宽度用 `Column`
- `~MOB` 里 `@name` 是 assign，不是模块属性
- 圆角卡片：外 `corner_radius={16}`，内 `padding={24}`，否则切字
- 改 Compose 必须重装原生，热推 Elixir 不够
- 同时只活一个 screen；这个应用 tick 在根屏幕里

## 安装

**能 `run-as` 的 Android**（常见：Mac + 模拟器/真机）：改原生 `mix mob.deploy --native`；只改 Elixir `mix mob.deploy`。`mix.exs` 的 `android.native` 是这条。

**Chromos / ARC**（本机 `arc:5555`，`x86_64`，内核关了 `run-as`）：`--native` 能装 APK，OTP 推不进 `filesDir`，启动没有 `start_clean.boot`。持久安装：

```sh
export JAVA_HOME=/home/hpbox/.local/share/mise/installs/java/temurin-17.0.18+8
export ANDROID_HOME=/home/hpbox/Android/Sdk
export PATH="/tmp/mob-bin:$JAVA_HOME/bin:$ANDROID_HOME/platform-tools:$PATH"
mix mob.pack_apk --device arc:5555
```

主机没有 `arp` 时 `mix mob.deploy` 会崩，PATH 前面放 `/tmp/mob-bin`。Java 必须 Temurin 17。

Chromos 窗口有时停在 `PlaceholderActivity`（黑屏）：

```sh
adb -s arc:5555 shell am start -n com.example.battery_timer/.MainActivity
```

截图前窗口要在前台。

## 热更新

只换 Elixir 字节码。改 Kotlin / C / NIF：能 `run-as` 用 `--native`，Chromos 用 `pack_apk`。

| 命令 | 能 `run-as` | Chromos |
|---|---|---|
| `mix mob.connect` | 建隧道，重启 App | 同左 |
| `mix mob.push` / `nl/1` | 热替换，杀进程就没了 | 同左；没 connect 则 No running nodes |
| `mix mob.watch` | 存盘自动 push | 同左 |
| `mix mob.deploy` | 推 BEAM 并写盘 | 不写盘，杀进程回到上次 pack_apk |
| `mix mob.deploy --native` | 装 APK + 推 OTP | 装 APK，OTP 失败 |
| `mix mob.pack_apk` | 一般不用 | 持久安装（OTP zip 打进 debug APK） |

`✓` 不够。改一个可见字符串，按上表安装，force-stop 再开。

## 查运行中的 App

状态问 BEAM，别先截图。

```sh
mix mob.connect --no-iex
```

节点：`battery_timer_android@127.0.0.1`（有时带 suffix）。

```elixir
n = :"battery_timer_android@127.0.0.1"
Mob.Test.screen(n)
Mob.Test.assigns(n)
Mob.Test.tap(n, :log_now)
Mob.Test.settle(n)
```

`tap/2` 的 `:ok` 只表示发出去了。断言 assigns：点记录后 `hd(history).reason == :manual`。`{:badrpc, :nodedown}` 就是没连上。

## CI

`.github/workflows/android-apk.yml` 打 `arm64-v8a` 和 `x86_64` 两个 debug APK（一份 OTP zip 一个 ABI）。本地：`bash script/ci_setup_android.sh` 然后 `mix mob.pack_apk --abi … --no-install --output …`。

## 验证

```sh
mix test
```

主机没有 `:battery` NIF。测试用 `Process.put(:battery_read, %{…})`。加载失败警告是预期的。

## 目录

```
lib/battery_timer/app.ex              启动、迁移、根屏幕
lib/battery_timer/home_screen.ex      UI 和事件采样
lib/battery_timer/battery.ex          快照、本地时钟
lib/battery_timer/history.ex          SQLite
lib/battery_timer/i18n.ex             EN/ZH
lib/battery_timer/nifs/battery.ex     NIF stub
c_src/battery.c                       静态 NIF
android/.../MobBridge.kt              batterySnapshot、recordClose
android/.../BatteryMonitorService.kt  前台服务
android/.../jni/beam_jni.c            g_app_bridge_cls
lib/mix/tasks/mob.pack_apk.ex         OTP-in-APK
script/ci_setup_android.sh            非交互安装
.github/workflows/android-apk.yml     CI APK
priv/repo/migrations/                 battery_samples
```
