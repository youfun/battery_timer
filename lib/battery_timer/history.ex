defmodule BatteryTimer.History do
  @moduledoc false

  import Ecto.Query

  alias BatteryTimer.{Battery, Repo, Sample}

  @limit 200
  @window_limit 500
  @close_file "battery_close.txt"

  @reasons [
    :app_start,
    :app_close,
    :plug,
    :unplug,
    :full,
    :low_20,
    :charge_80,
    :manual,
    :timer_start
  ]

  def list(limit \\ @limit) do
    Sample
    |> order_by([s], desc: s.recorded_at, desc: s.id)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.map(&to_entry/1)
  end

  def window(days) when is_integer(days) and days >= 1 do
    cutoff = Battery.local_midnight_utc(Date.add(Battery.local_today(), 1 - days))
    {list_since(cutoff), older?(cutoff)}
  end

  def list_since(%DateTime{} = cutoff) do
    Sample
    |> where([s], s.recorded_at >= ^cutoff)
    |> order_by([s], desc: s.recorded_at, desc: s.id)
    |> limit(^@window_limit)
    |> Repo.all()
    |> Enum.map(&to_entry/1)
  end

  def older?(%DateTime{} = cutoff) do
    Repo.exists?(from(s in Sample, where: s.recorded_at < ^cutoff))
  end

  def insert(attrs) do
    reason = attrs |> Map.get(:reason, :manual) |> reason_string()

    %Sample{}
    |> Sample.changeset(%{
      recorded_at: DateTime.truncate(attrs.at, :second),
      percent: attrs.percent,
      state: attrs.state |> to_string(),
      elapsed_ms: Map.get(attrs, :elapsed_ms, 0),
      reason: reason
    })
    |> Repo.insert!()
    |> to_entry()
  end

  def record(reason, sample, elapsed_ms \\ 0) do
    insert(Map.merge(sample, %{reason: reason, elapsed_ms: elapsed_ms}))
  end

  def drain_close do
    path = close_path()

    case File.read(path) do
      {:ok, body} ->
        _ = File.rm(path)
        ingest_close(body)

      {:error, _} ->
        :ok
    end
  end

  def already_logged?(:app_close, %DateTime{} = at) do
    case list(1) do
      [%{reason: :app_close, at: logged}] ->
        abs(DateTime.diff(logged, DateTime.truncate(at, :second), :second)) <= 2

      _ ->
        false
    end
  end

  def already_logged?(_, _), do: false

  def clear do
    Repo.delete_all(Sample)
    :ok
  end

  def reason_label(reason, locale) do
    key =
      case reason do
        :app_start -> :app_start
        :app_close -> :app_close
        :plug -> :plug
        :unplug -> :unplug
        :full -> :full_reason
        :low_20 -> :low_20
        :charge_80 -> :charge_80
        :timer_start -> :timer_start
        :manual -> :manual
        _ -> :record
      end

    BatteryTimer.I18n.t(locale, key)
  end

  defp ingest_close(body) do
    case String.split(String.trim(body), "|") do
      [state, percent, millis] ->
        {ms, _} = Integer.parse(millis)
        {pct, _} = Integer.parse(percent)

        at =
          ms
          |> div(1000)
          |> DateTime.from_unix!()

        unless already_logged?(:app_close, at) do
          record(:app_close, %{
            at: at,
            percent: pct,
            state: parse_state(state)
          })
        end

        :ok

      _ ->
        :ok
    end
  end

  defp close_path do
    dir =
      System.get_env("MOB_DATA_DIR") ||
        System.get_env("HOME") ||
        Path.join(File.cwd!(), "priv/repo")

    Path.join(dir, @close_file)
  end

  defp reason_string(reason) when reason in @reasons, do: Atom.to_string(reason)
  defp reason_string(reason) when is_binary(reason), do: reason
  defp reason_string(_), do: "manual"

  defp to_entry(%Sample{} = sample) do
    %{
      at: utc(sample.recorded_at),
      percent: sample.percent,
      state: parse_state(sample.state),
      elapsed_ms: sample.elapsed_ms,
      reason: parse_reason(sample.reason)
    }
  end

  defp utc(%DateTime{} = at), do: DateTime.truncate(at, :second)

  defp utc(%NaiveDateTime{} = at),
    do: at |> DateTime.from_naive!("Etc/UTC") |> DateTime.truncate(:second)

  defp parse_state("charging"), do: :charging
  defp parse_state("full"), do: :full
  defp parse_state("unplugged"), do: :unplugged
  defp parse_state(_), do: :unknown

  defp parse_reason("app_start"), do: :app_start
  defp parse_reason("app_close"), do: :app_close
  defp parse_reason("plug"), do: :plug
  defp parse_reason("unplug"), do: :unplug
  defp parse_reason("full"), do: :full
  defp parse_reason("low_20"), do: :low_20
  defp parse_reason("charge_80"), do: :charge_80
  defp parse_reason("timer_start"), do: :timer_start
  defp parse_reason(_), do: :manual
end
