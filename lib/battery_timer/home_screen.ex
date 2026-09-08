defmodule BatteryTimer.HomeScreen do
  @moduledoc "Log battery on launch, close, plug events, 20%, charge 80%, and manual tap."

  use Mob.Screen

  alias BatteryTimer.{Battery, History, I18n}

  @label 0xFFC5CDD6
  @tick_ms 1000
  @history_days 3

  def mount(_params, _session, socket) do
    History.drain_close()
    now = DateTime.utc_now()
    current = Battery.read(now)
    History.record(:app_start, current)
    Process.send_after(self(), :tick, @tick_ms)
    {history, older?} = History.window(@history_days)

    {:ok,
     Mob.Socket.assign(socket,
       now: now,
       locale: I18n.current(),
       current: current,
       last_state: current.state,
       last_percent: current.percent,
       crossed_20?: current.percent != -1 and current.percent <= 20,
       crossed_80?: current.percent != -1 and current.percent >= 80,
       history_days: @history_days,
       history: history,
       older?: older?
     )}
  end

  def render(assigns) do
    locale = assigns.locale
    log_tap = {self(), :log_now}
    lang_tap = {self(), :toggle_locale}
    label = @label
    title = I18n.t(locale, :title)
    hint1 = I18n.t(locale, :hint1)
    hint2 = I18n.t(locale, :hint2)
    current = I18n.t(locale, :current)
    history = I18n.t(locale, :history)
    log = I18n.t(locale, :log)
    lang = I18n.toggle_label(locale)
    version = app_version()
    percent = Battery.percent_label(assigns.current.percent, locale)
    state = Battery.state_label(assigns.current.state, locale)
    since = since_text(assigns.history, assigns.now, locale)

    ~MOB"""
    <Scroll background={:background}>
      <Column background={:background} padding={24} fill_width={true}>
        <Row align="center">
          <Text text={title} text_size={:xl} text_color={:on_background} font_weight="bold" />
          <Spacer size={10} />
          <Button
            text={lang}
            background={:surface}
            text_color={:on_surface}
            text_size={11}
            padding={4}
            corner_radius={6}
            fill_width={false}
            on_tap={lang_tap}
          />
        </Row>
        <Spacer size={8} />
        <Text text={hint1} text_size={:sm} text_color={label} />
        <Text text={hint2} text_size={:sm} text_color={label} />
        <Spacer size={20} />
        <Column background={:surface_raised} corner_radius={16} fill_width={true}>
          <Column padding={24} fill_width={true}>
            <Text text={current} text_size={:sm} text_color={label} />
            <Spacer size={6} />
            <Text
              text={percent}
              text_size={40}
              text_color={:on_surface}
              font_weight="bold"
            />
            <Spacer size={8} />
            <Row align="center" fill_width={true}>
              <Text text={state} text_size={:base} text_color={:on_surface} />
              <Spacer size={12} />
              <Text text={since} text_size={:sm} text_color={label} />
            </Row>
          </Column>
        </Column>
        <Spacer size={28} />
        <Row align="center">
          <Text text={history} text_size={:lg} text_color={:on_background} font_weight="bold" />
          <Spacer size={10} />
          <Button
            text={log}
            background={:surface}
            text_color={:on_surface}
            text_size={11}
            padding={4}
            corner_radius={6}
            fill_width={false}
            on_tap={log_tap}
          />
        </Row>
        <Spacer size={12} />
        {history_section(assigns)}
        <Spacer size={32} />
        <Text text={version} text_size={:sm} text_color={label} />
        <Spacer size={24} />
      </Column>
    </Scroll>
    """
  end

  def handle_info({:tap, :log_now}, socket) do
    {:noreply, log_now(socket)}
  end

  def handle_info({:tap, :toggle_locale}, socket) do
    {:noreply, Mob.Socket.assign(socket, :locale, I18n.put(I18n.toggle(socket.assigns.locale)))}
  end

  def handle_info({:tap, :load_earlier}, socket) do
    {:noreply, load_earlier(socket)}
  end

  def handle_info(:tick, socket) do
    Process.send_after(self(), :tick, @tick_ms)
    {:noreply, on_tick(socket)}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  defp on_tick(socket) do
    now = now()
    current = Battery.read(now)

    socket
    |> Mob.Socket.assign(:now, now)
    |> Mob.Socket.assign(:current, current)
    |> maybe_log_events(current)
    |> Mob.Socket.assign(:last_state, current.state)
    |> Mob.Socket.assign(:last_percent, current.percent)
  end

  defp maybe_log_events(socket, current) do
    prev_state = socket.assigns.last_state
    prev_percent = socket.assigns.last_percent

    socket
    |> maybe_power(prev_state, current)
    |> maybe_low_20(prev_percent, current)
    |> maybe_charge_80(prev_percent, current)
  end

  defp maybe_power(socket, prev, current) do
    cond do
      not Battery.power_changed?(prev, current.state) ->
        socket

      current.state == :charging ->
        put_record(socket, :plug, current)

      current.state == :unplugged ->
        put_record(socket, :unplug, current)

      current.state == :full ->
        put_record(socket, :full, current)

      true ->
        socket
    end
  end

  defp maybe_low_20(socket, prev, current) do
    cond do
      socket.assigns.crossed_20? ->
        socket

      current.percent != -1 and current.percent <= 20 and (prev == -1 or prev > 20) ->
        socket
        |> put_record(:low_20, current)
        |> Mob.Socket.assign(:crossed_20?, true)

      current.percent > 20 ->
        Mob.Socket.assign(socket, :crossed_20?, false)

      true ->
        socket
    end
  end

  defp maybe_charge_80(socket, prev, current) do
    charging? = current.state in [:charging, :full]

    cond do
      socket.assigns.crossed_80? ->
        if current.percent != -1 and current.percent < 80,
          do: Mob.Socket.assign(socket, :crossed_80?, false),
          else: socket

      charging? and current.percent != -1 and current.percent >= 80 and (prev == -1 or prev < 80) ->
        socket
        |> put_record(:charge_80, current)
        |> Mob.Socket.assign(:crossed_80?, true)

      true ->
        socket
    end
  end

  defp log_now(socket) do
    now = DateTime.utc_now()
    sample = Battery.read(now)

    socket
    |> Mob.Socket.assign(:now, now)
    |> put_record(:manual, sample)
  end

  defp put_record(socket, reason, sample) do
    History.record(reason, sample, 0)
    refresh_history(socket, sample)
  end

  defp load_earlier(socket) do
    days = socket.assigns.history_days + @history_days
    {history, older?} = History.window(days)

    socket
    |> Mob.Socket.assign(:history_days, days)
    |> Mob.Socket.assign(:history, history)
    |> Mob.Socket.assign(:older?, older?)
  end

  defp refresh_history(socket, sample) do
    {history, older?} = History.window(socket.assigns.history_days)

    socket
    |> Mob.Socket.assign(:current, sample)
    |> Mob.Socket.assign(:history, history)
    |> Mob.Socket.assign(:older?, older?)
  end

  defp history_section(%{history: []} = assigns), do: empty_history(assigns.locale)

  defp history_section(assigns) do
    locale = assigns.locale
    rows = grouped_rows(assigns.history, locale)
    children = if assigns.older?, do: rows ++ [spacer(12), earlier_button(locale)], else: rows
    %{type: :column, props: %{fill_width: true}, children: children}
  end

  defp grouped_rows(history, locale) do
    history
    |> Enum.group_by(&Battery.local_date(&1.at))
    |> Enum.sort_by(fn {date, _} -> date end, {:desc, Date})
    |> Enum.with_index()
    |> Enum.flat_map(fn {{date, entries}, i} ->
      block = [date_divider(date, locale), spacer(8) | entry_rows(entries, locale)]
      if i == 0, do: block, else: [spacer(16) | block]
    end)
  end

  defp entry_rows(entries, locale) do
    entries
    |> Enum.with_index()
    |> Enum.flat_map(fn {entry, i} ->
      if i == 0, do: [history_row(entry, locale)], else: [spacer(6), history_row(entry, locale)]
    end)
  end

  defp now do
    case Process.get(:utc_now) do
      %DateTime{} = at -> at
      _ -> DateTime.utc_now()
    end
  end

  defp since_text([], _now, _locale), do: ""
  defp since_text([entry | _], now, locale), do: Battery.since_label(entry.at, now, locale)

  defp app_version do
    vsn =
      case :application.get_key(:battery_timer, :vsn) do
        {:ok, value} -> to_string(value)
        _ -> "0.1.0"
      end

    "v#{vsn}"
  end

  defp spacer(size), do: %{type: :spacer, props: %{size: size}, children: []}

  defp empty_history(locale) do
    label = @label
    empty = I18n.t(locale, :empty)
    ~MOB(<Text text={empty} text_size={:sm} text_color={label} />)
  end

  defp date_divider(date, locale) do
    label = @label
    text = Battery.date_label(date, locale)

    ~MOB"""
    <Text text={text} text_size={:sm} text_color={label} font_weight="bold" />
    """
  end

  defp earlier_button(locale) do
    tap = {self(), :load_earlier}
    text = I18n.t(locale, :earlier)

    ~MOB"""
    <Button
      text={text}
      background={:surface}
      text_color={:on_surface}
      text_size={11}
      padding={4}
      corner_radius={6}
      fill_width={true}
      on_tap={tap}
    />
    """
  end

  defp history_row(entry, locale) do
    line =
      "#{Battery.clock_label(entry.at)}  ·  #{Battery.battery_label(entry, locale)}  ·  #{History.reason_label(entry.reason, locale)}"

    ~MOB"""
    <Column background={:surface} padding={8} corner_radius={10} fill_width={true}>
      <Text text={line} text_size={:sm} text_color={:on_surface} />
    </Column>
    """
  end
end
