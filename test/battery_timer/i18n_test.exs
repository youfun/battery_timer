defmodule BatteryTimer.I18nTest do
  use ExUnit.Case, async: false

  alias BatteryTimer.I18n

  setup do
    I18n.reset()
    :ok
  end

  test "unsupported tags fall back to English" do
    assert I18n.parse("ja-JP") == :en
    assert I18n.parse("fr_FR") == :en
    assert I18n.parse("C") == :en
    assert I18n.parse(nil) == :en
  end

  test "zh tags are Chinese" do
    assert I18n.parse("zh") == :zh
    assert I18n.parse("zh-CN") == :zh
    assert I18n.parse("zh_TW.UTF-8") == :zh
    assert I18n.parse("zh-Hans-CN") == :zh
  end

  test "en tags are English" do
    assert I18n.parse("en") == :en
    assert I18n.parse("en_US.UTF-8") == :en
  end

  test "toggle flips between zh and en" do
    assert I18n.toggle(:en) == :zh
    assert I18n.toggle(:zh) == :en
    assert I18n.toggle_label(:en) == "ZH"
    assert I18n.toggle_label(:zh) == "EN"
  end

  test "put persists for current/0" do
    assert I18n.put(:zh) == :zh
    assert I18n.current() == :zh
    assert I18n.put(:en) == :en
    assert I18n.current() == :en
  end

  test "copy tables differ by locale" do
    assert I18n.t(:en, :title) == "Battery Log"
    assert I18n.t(:zh, :title) == "电量记录"
    assert I18n.t(:en, :log) == "Log"
    assert I18n.t(:zh, :log) == "记录"
    assert I18n.since_last(:zh, 2, 15, 8) == "距离上次记录 2小时15分钟8秒"
    assert I18n.since_last(:en, 2, 15, 8) == "2h 15m 8s since last log"
  end
end
