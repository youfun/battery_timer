# 电量记录

Android 应用：启动、关闭、插电、拔电、充满、电量到 20%、充电到 80% 会自动记一条；「历史电量」旁的「记录」手动补一条。历史在 SQLite。界面按设备时区显示，库里存 UTC。

[English](README.md)

```sh
mix mob.new battery_timer --android --blank
```

改代码、电量 NIF、Chromos 安装、热更新见 [AGENTS.md](AGENTS.md)。

# 技术栈

| 层 | 用什么 |
|---|---|
| 语言 / VM | Elixir 1.20 + OTP 29，BEAM 跑在设备上 |
| UI | [Mob](https://hex.pm/packages/mob) 0.7.x：`Mob.Screen` + `~MOB`，原生 Jetpack Compose |
| 构建 | [mob_dev](https://hex.pm/packages/mob_dev)；Zig 编 native `.so`，Gradle 打 APK |
| 持久化 | Ecto + `ecto_sqlite3`，`MOB_DATA_DIR/app.db` |
| 电量 | 项目静态 NIF `:battery`（`Mob.Device.battery_*` 在 Android 仍是 TODO） |
| 图标 | `mix mob.icon --source icon_source.png --adaptive` |
