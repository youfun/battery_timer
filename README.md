# Battery Log

Android app. It writes a SQLite row on launch, close, plug, unplug, full charge, battery at 20%, charge at 80%, and when you tap **Log** next to History. Times on screen use the device timezone; the database stores UTC.

[中文](README.zh.md)

```sh
mix mob.new battery_timer --android --blank
```

Coding notes, the battery NIF, Chromos install, and hot reload: [AGENTS.md](AGENTS.md).

# Stack

| Layer | What |
|---|---|
| Language / VM | Elixir 1.20 + OTP 29; BEAM on device |
| UI | [Mob](https://hex.pm/packages/mob) 0.7.x: `Mob.Screen` + `~MOB`, Jetpack Compose |
| Build | [mob_dev](https://hex.pm/packages/mob_dev); Zig for native `.so`, Gradle for APK |
| Persistence | Ecto + `ecto_sqlite3`, `MOB_DATA_DIR/app.db` |
| Battery | Project static NIF `:battery` (`Mob.Device.battery_*` is still TODO on Android) |
| Icon | `mix mob.icon --source icon_source.png --adaptive` |
