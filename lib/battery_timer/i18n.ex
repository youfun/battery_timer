defmodule BatteryTimer.I18n do
  @moduledoc false

  @locales [:en, :zh]
  @pt_key {__MODULE__, :locale}

  @strings %{
    en: %{
      title: "Battery Log",
      hint1: "Launch, close, plug, unplug, and full charge are logged.",
      hint2: "Crossing 20% battery or 80% while charging is logged too.",
      current: "Battery",
      history: "History",
      log: "Log",
      empty: "No entries yet.",
      today: "Today",
      yesterday: "Yesterday",
      earlier: "Earlier",
      since_last: "since last log",
      unknown: "Unknown",
      charging: "Charging",
      full: "Full",
      unplugged: "Unplugged",
      app_start: "Launch",
      app_close: "Close",
      plug: "Plug",
      unplug: "Unplug",
      full_reason: "Full",
      low_20: "20%",
      charge_80: "80%",
      timer_start: "Timer",
      manual: "Manual",
      record: "Log"
    },
    zh: %{
      title: "电量记录",
      hint1: "启动、关闭、插电、拔电、充满会自动记。",
      hint2: "电量到 20%、充电到 80% 也会记一条。",
      current: "当前电量",
      history: "历史电量",
      log: "记录",
      empty: "还没有记录。",
      today: "今天",
      yesterday: "昨天",
      earlier: "查看更早",
      since_last: "距离上次记录",
      unknown: "未知",
      charging: "充电中",
      full: "已充满",
      unplugged: "未充电",
      app_start: "启动",
      app_close: "关闭",
      plug: "充电",
      unplug: "拔电",
      full_reason: "充满",
      low_20: "电量 20%",
      charge_80: "充电 80%",
      timer_start: "开始计时",
      manual: "手动",
      record: "记录"
    }
  }

  def supported, do: @locales

  def t(locale, key) do
    loc = normalize(locale)
    @strings[loc][key] || @strings[:en][key] || ""
  end

  def since_last(locale, hours, minutes, seconds)
      when is_integer(hours) and is_integer(minutes) and is_integer(seconds) do
    case normalize(locale) do
      :zh -> "#{t(:zh, :since_last)} #{hours}小时#{minutes}分钟#{seconds}秒"
      _ -> "#{hours}h #{minutes}m #{seconds}s #{t(:en, :since_last)}"
    end
  end

  def toggle_label(:zh), do: "EN"
  def toggle_label(:en), do: "ZH"
  def toggle_label(_), do: "ZH"

  def toggle(:zh), do: :en
  def toggle(:en), do: :zh
  def toggle(_), do: :en

  def current do
    case :persistent_term.get(@pt_key, :unset) do
      locale when locale in @locales ->
        locale

      :unset ->
        case state_get() do
          locale when locale in @locales -> locale
          _ -> detect()
        end
    end
  end

  def put(locale) do
    locale = normalize(locale)
    :persistent_term.put(@pt_key, locale)
    state_put(locale)
    locale
  end

  def reset do
    _ = :persistent_term.erase(@pt_key)
    state_delete()
    :ok
  end

  def detect do
    [
      prop("persist.sys.locale"),
      prop("persist.sys.language"),
      System.get_env("LANG"),
      System.get_env("LC_ALL"),
      System.get_env("LC_MESSAGES")
    ]
    |> Enum.find_value(:en, &classify/1)
  end

  def parse(tag), do: classify(tag) || :en

  defp classify(nil), do: nil
  defp classify(""), do: nil

  defp classify(tag) when is_binary(tag) do
    down = tag |> String.trim() |> String.downcase()

    cond do
      down in ["c", "posix"] -> nil
      String.starts_with?(down, "zh") -> :zh
      String.contains?(down, "hans") -> :zh
      String.contains?(down, "hant") -> :zh
      String.contains?(down, "chinese") -> :zh
      String.starts_with?(down, "en") -> :en
      true -> :en
    end
  end

  defp classify(tag) when is_list(tag), do: classify(List.to_string(tag))
  defp classify(_), do: nil

  defp normalize(locale) when locale in @locales, do: locale
  defp normalize(_), do: :en

  defp state_get do
    Mob.State.get(:locale, :unset)
  rescue
    _ -> :unset
  catch
    _, _ -> :unset
  end

  defp state_put(locale) do
    Mob.State.put(:locale, locale)
    :ok
  rescue
    _ -> :ok
  catch
    _, _ -> :ok
  end

  defp state_delete do
    Mob.State.delete(:locale)
    :ok
  rescue
    _ -> :ok
  catch
    _, _ -> :ok
  end

  defp prop(name) do
    case System.find_executable("getprop") do
      nil ->
        nil

      bin ->
        case System.cmd(bin, [name], stderr_to_stdout: true) do
          {out, 0} ->
            case String.trim(out) do
              "" -> nil
              value -> value
            end

          _ ->
            nil
        end
    end
  end
end
