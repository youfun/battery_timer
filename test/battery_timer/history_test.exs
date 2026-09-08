defmodule BatteryTimer.HistoryTest do
  use ExUnit.Case, async: false

  alias BatteryTimer.History

  setup do
    History.clear()
    :ok
  end

  test "inserts samples into sqlite and lists newest first" do
    t1 = ~U[2026-09-08 01:00:00Z]
    t2 = ~U[2026-09-08 01:01:00Z]

    History.insert(%{at: t1, percent: 80, state: :unplugged, elapsed_ms: 0, reason: :app_start})
    History.insert(%{at: t2, percent: 79, state: :charging, elapsed_ms: 60_000, reason: :plug})

    assert [
             %{at: ^t2, percent: 79, state: :charging, reason: :plug},
             %{at: ^t1, percent: 80, state: :unplugged, reason: :app_start}
           ] = History.list()
  end

  test "drain_close turns the kotlin close file into an app_close row" do
    dir = System.get_env("MOB_DATA_DIR")
    at = ~U[2026-09-08 03:00:00Z]

    File.write!(
      Path.join(dir, "battery_close.txt"),
      "unplugged|22|#{DateTime.to_unix(at) * 1000}"
    )

    History.drain_close()

    assert [%{reason: :app_close, percent: 22, state: :unplugged, at: ^at}] = History.list()
    refute File.exists?(Path.join(dir, "battery_close.txt"))
  end

  test "window keeps the last three local days and reports older rows" do
    today = DateTime.utc_now() |> DateTime.truncate(:second)
    old = DateTime.add(today, -5, :day)

    History.insert(%{at: old, percent: 10, state: :unplugged, elapsed_ms: 0, reason: :manual})
    History.insert(%{at: today, percent: 90, state: :unplugged, elapsed_ms: 0, reason: :manual})

    {rows, older?} = History.window(3)
    assert older?
    assert Enum.all?(rows, &(&1.percent == 90))
    refute Enum.any?(rows, &(&1.percent == 10))

    {more, still?} = History.window(6)
    refute still?
    assert Enum.any?(more, &(&1.percent == 10))
  end

  test "clear removes every sample" do
    History.insert(%{
      at: DateTime.utc_now(),
      percent: 50,
      state: :full,
      elapsed_ms: 0,
      reason: :full
    })

    History.clear()
    assert History.list() == []
  end
end
