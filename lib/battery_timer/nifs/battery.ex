defmodule BatteryTimer.Nifs.Battery do
  @moduledoc false

  @on_load :load_nif

  def load_nif do
    _ = :erlang.load_nif(~c"battery", 0)
    :ok
  end

  @spec status() :: {atom(), integer()}
  def status, do: :erlang.nif_error(:nif_not_loaded)
end
