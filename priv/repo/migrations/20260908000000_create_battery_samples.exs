defmodule BatteryTimer.Repo.Migrations.CreateBatterySamples do
  use Ecto.Migration

  def change do
    create table(:battery_samples) do
      add :recorded_at, :utc_datetime, null: false
      add :percent, :integer, null: false
      add :state, :string, null: false
      add :elapsed_ms, :integer, null: false, default: 0
      timestamps()
    end

    create index(:battery_samples, [:recorded_at, :id])
  end
end
