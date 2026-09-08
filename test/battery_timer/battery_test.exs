defmodule BatteryTimer.BatteryTest do
  use ExUnit.Case, async: true

  alias BatteryTimer.Battery

  test "snapshot falls back to unknown off-device" do
    {state, percent} = Battery.snapshot()
    assert state in [:unplugged, :charging, :full, :unknown]
    assert is_integer(percent)
  end

  test "power_changed? treats plug and unplug as events" do
    refute Battery.power_changed?(:unplugged, :unplugged)
    refute Battery.power_changed?(:unknown, :charging)
    assert Battery.power_changed?(:unplugged, :charging)
    assert Battery.power_changed?(:charging, :full)
    assert Battery.power_changed?(:charging, :unplugged)
  end

  test "formats percent and charging state" do
    assert Battery.percent_label(83, :en) == "83%"
    assert Battery.percent_label(-1, :en) == "Unknown"
    assert Battery.percent_label(-1, :zh) == "未知"
    assert Battery.state_label(:charging, :zh) == "充电中"
    assert Battery.state_label(:charging, :en) == "Charging"
    assert Battery.battery_label(%{percent: 80, state: :unplugged}, :en) == "80% · Unplugged"
  end

  test "since_label is hours and minutes from the last sample" do
    at = ~U[2026-09-08 01:00:00Z]
    now = ~U[2026-09-08 03:15:00Z]
    assert Battery.since_label(at, now, :zh) == "距离上次记录 2小时15分钟0秒"
    assert Battery.since_label(at, now, :en) == "2h 15m 0s since last log"
    assert Battery.since_label(nil, now, :en) == ""
  end

  test "date_label uses today and yesterday in the machine timezone" do
    today = Battery.local_today()
    assert Battery.date_label(today, :en) == "Today"
    assert Battery.date_label(today, :zh) == "今天"
    assert Battery.date_label(Date.add(today, -1), :en) == "Yesterday"
    assert Battery.date_label(Date.add(today, -2), :en) == Calendar.strftime(Date.add(today, -2), "%Y-%m-%d")
  end

  test "clock_label converts UTC to the machine local time" do
    utc = ~U[2026-09-08 03:13:27Z]
    {_date, {h, m, s}} = :calendar.universal_time_to_local_time({{2026, 9, 8}, {3, 13, 27}})

    expected =
      [h, m, s]
      |> Enum.map(&Integer.to_string/1)
      |> Enum.map_join(":", &String.pad_leading(&1, 2, "0"))

    assert Battery.clock_label(utc) == expected
  end

  test "formats elapsed clock" do
    assert Battery.elapsed_label(0) == "00:00:00"
    assert Battery.elapsed_label(72_000) == "00:01:12"
    assert Battery.elapsed_label(3_662_000) == "01:01:02"
  end

  test "elapsed_ms is zero before start" do
    now = DateTime.utc_now()
    assert Battery.elapsed_ms(nil, now) == 0
    assert Battery.elapsed_ms(now, DateTime.add(now, 5, :second)) == 5_000
  end
end
