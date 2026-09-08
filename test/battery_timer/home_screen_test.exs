defmodule BatteryTimer.HomeScreenTest do
  use Mob.ScreenCase, async: false

  alias BatteryTimer.{History, HomeScreen, I18n}

  setup do
    History.clear()
    I18n.reset()
    I18n.put(:en)
    Process.delete(:battery_read)
    :ok
  end

  test "mounts, logs app_start, and renders" do
    Process.put(:battery_read, %{percent: 50, state: :unplugged})
    view = mount_screen(HomeScreen)
    assert_renderable(view)
    assert text(view) =~ "Battery Log"
    assert text(view) =~ "History"
    assert text(view) =~ "v0.1.0"
    assert text(view) =~ "0h 0m 0s since last log"
    assert hd(History.list()).reason == :app_start
    assert button_label(view, "Log")
    assert button_label(view, "ZH")
  end

  test "since-last text advances on tick" do
    Process.put(:battery_read, %{percent: 50, state: :unplugged})
    view = mount_screen(HomeScreen)
    at = hd(assigns(view).history).at
    later = DateTime.add(at, 3, :second)
    Process.put(:utc_now, later)
    view = render_info(view, :tick)
    assert text(view) =~ "0h 0m 3s since last log"
  end

  test "ZH/EN toggle switches copy" do
    Process.put(:battery_read, %{percent: 50, state: :unplugged})
    view = mount_screen(HomeScreen)
    view = render_info(view, {:tap, :toggle_locale})

    assert assigns(view).locale == :zh
    assert text(view) =~ "电量记录"
    assert text(view) =~ "历史电量"
    assert text(view) =~ "距离上次记录 0小时0分钟0秒"
    assert button_label(view, "记录")
    assert button_label(view, "EN")
  end

  test "manual record button logs current battery" do
    Process.put(:battery_read, %{percent: 50, state: :unplugged})
    view = mount_screen(HomeScreen)
    Process.put(:battery_read, %{percent: 48, state: :unplugged})
    view = render_info(view, {:tap, :log_now})

    assert hd(assigns(view).history).reason == :manual
    assert hd(assigns(view).history).percent == 48
  end

  test "plug-in auto-logs" do
    Process.put(:battery_read, %{percent: 40, state: :unplugged})
    view = mount_screen(HomeScreen)
    before = length(History.list())

    Process.put(:battery_read, %{percent: 41, state: :charging})
    view = render_info(view, :tick)

    assert length(History.list()) == before + 1
    assert hd(assigns(view).history).reason == :plug
  end

  test "crossing 20 percent logs low_20 once" do
    Process.put(:battery_read, %{percent: 21, state: :unplugged})
    view = mount_screen(HomeScreen)

    Process.put(:battery_read, %{percent: 20, state: :unplugged})
    view = render_info(view, :tick)
    assert hd(assigns(view).history).reason == :low_20

    Process.put(:battery_read, %{percent: 19, state: :unplugged})
    view = render_info(view, :tick)
    assert length(Enum.filter(assigns(view).history, &(&1.reason == :low_20))) == 1
  end

  test "history groups by local date and loads earlier days" do
    Process.put(:battery_read, %{percent: 50, state: :unplugged})
    old = DateTime.add(DateTime.utc_now(), -5, :day) |> DateTime.truncate(:second)

    History.insert(%{
      at: old,
      percent: 11,
      state: :unplugged,
      elapsed_ms: 0,
      reason: :manual
    })

    view = mount_screen(HomeScreen)
    assert text(view) =~ "Today"
    refute text(view) =~ "11%"
    assert button_label(view, "Earlier")

    view = render_info(view, {:tap, :load_earlier})
    assert assigns(view).history_days == 6
    assert Enum.any?(assigns(view).history, &(&1.percent == 11))
  end

  test "charging across 80 percent logs charge_80" do
    Process.put(:battery_read, %{percent: 79, state: :charging})
    view = mount_screen(HomeScreen)

    Process.put(:battery_read, %{percent: 80, state: :charging})
    view = render_info(view, :tick)
    assert hd(assigns(view).history).reason == :charge_80
  end

  defp button_label(view, wanted) do
    found =
      view
      |> flatten()
      |> Enum.any?(fn
        %{type: :button, props: %{text: ^wanted}} -> true
        _ -> false
      end)

    assert found, "missing button #{inspect(wanted)}"
    found
  end
end
