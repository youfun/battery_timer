defmodule BatteryTimer.Battery do
  @moduledoc false

  @states [:unplugged, :charging, :full, :unknown]

  def read(at \\ DateTime.utc_now()) do
    case Process.get(:battery_read) do
      %{percent: percent, state: state} ->
        %{at: DateTime.truncate(at, :second), percent: percent, state: state}

      _ ->
        {state, percent} = snapshot()
        %{at: DateTime.truncate(at, :second), percent: percent, state: state}
    end
  end

  def power_changed?(prev, next) when prev == next, do: false
  def power_changed?(:unknown, _), do: false
  def power_changed?(_, :unknown), do: false
  def power_changed?(_, _), do: true

  def snapshot do
    case safe(&BatteryTimer.Nifs.Battery.status/0) do
      {state, pct} when state in @states and is_integer(pct) and pct != -1 ->
        {state, pct}

      {state, pct} when state in @states and is_integer(pct) ->
        fallback_or({state, pct})

      _ ->
        fallback_or({:unknown, -1})
    end
  end

  def level do
    {_state, percent} = snapshot()
    percent
  end

  def state do
    {state, _percent} = snapshot()
    state
  end

  def percent_label(-1, locale), do: BatteryTimer.I18n.t(locale, :unknown)
  def percent_label(n, _locale) when is_integer(n), do: "#{n}%"

  def state_label(state, locale) do
    key =
      case state do
        :charging -> :charging
        :full -> :full
        :unplugged -> :unplugged
        _ -> :unknown
      end

    BatteryTimer.I18n.t(locale, key)
  end

  def battery_label(sample, locale) do
    "#{percent_label(sample.percent, locale)} · #{state_label(sample.state, locale)}"
  end

  def since_label(nil, _now, _locale), do: ""

  def since_label(%DateTime{} = at, %DateTime{} = now, locale) do
    total = max(DateTime.diff(now, at, :second), 0)
    hours = div(total, 3600)
    minutes = rem(div(total, 60), 60)
    seconds = rem(total, 60)
    BatteryTimer.I18n.since_last(locale, hours, minutes, seconds)
  end

  def clock_label(%DateTime{} = at) do
    {_date, {h, m, s}} = to_local_erl(at)
    "#{pad(h)}:#{pad(m)}:#{pad(s)}"
  end

  def local_date(%DateTime{} = at) do
    {{y, m, d}, _} = to_local_erl(at)
    Date.new!(y, m, d)
  end

  def local_today do
    {date, _} = :calendar.local_time()
    Date.from_erl!(date)
  end

  def local_midnight_utc(%Date{} = date) do
    {Date.to_erl(date), {0, 0, 0}}
    |> :calendar.local_time_to_universal_time()
    |> NaiveDateTime.from_erl!()
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.truncate(:second)
  end

  def date_label(%Date{} = date, locale) do
    today = local_today()

    cond do
      date == today -> BatteryTimer.I18n.t(locale, :today)
      date == Date.add(today, -1) -> BatteryTimer.I18n.t(locale, :yesterday)
      true -> Calendar.strftime(date, "%Y-%m-%d")
    end
  end

  # Samples are stored UTC. Display uses the device wall clock via OTP's
  # universal→local conversion (bionic reads the Android timezone property).
  defp to_local_erl(%DateTime{} = at) do
    at
    |> DateTime.to_unix()
    |> DateTime.from_unix!()
    |> DateTime.to_naive()
    |> NaiveDateTime.to_erl()
    |> :calendar.universal_time_to_local_time()
  end

  def elapsed_label(ms) when is_integer(ms) and ms >= 0 do
    total = div(ms, 1000)
    h = div(total, 3600)
    m = rem(div(total, 60), 60)
    s = rem(total, 60)
    "#{pad(h)}:#{pad(m)}:#{pad(s)}"
  end

  def elapsed_ms(nil, _now), do: 0

  def elapsed_ms(%DateTime{} = started_at, %DateTime{} = now) do
    max(DateTime.diff(now, started_at, :millisecond), 0)
  end

  defp fallback_or(primary) do
    case mob_snapshot() do
      {state, pct} when state in @states and is_integer(pct) and pct != -1 ->
        {state, pct}

      _ ->
        primary
    end
  end

  defp mob_snapshot do
    state =
      case safe(&Mob.Device.battery_state/0) do
        s when s in @states -> s
        _ -> :unknown
      end

    percent =
      case safe(&Mob.Device.battery_level/0) do
        n when is_integer(n) -> n
        _ -> -1
      end

    {state, percent}
  end

  defp pad(n), do: n |> Integer.to_string() |> String.pad_leading(2, "0")

  defp safe(fun) do
    fun.()
  rescue
    _ -> nil
  catch
    _, _ -> nil
  end
end
