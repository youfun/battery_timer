defmodule BatteryTimer.Sample do
  use Ecto.Schema

  import Ecto.Changeset

  schema "battery_samples" do
    field(:recorded_at, :utc_datetime)
    field(:percent, :integer)
    field(:elapsed_ms, :integer, default: 0)
    field(:state, :string)
    field(:reason, :string, default: "manual")
    timestamps()
  end

  def changeset(sample, attrs) do
    sample
    |> cast(attrs, [:recorded_at, :percent, :state, :elapsed_ms, :reason])
    |> validate_required([:recorded_at, :percent, :state, :elapsed_ms, :reason])
  end
end
