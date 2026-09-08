tmp = Path.join(System.tmp_dir!(), "battery_timer_test")
File.mkdir_p!(tmp)
System.put_env("MOB_DATA_DIR", tmp)

{:ok, _} = Application.ensure_all_started(:ecto_sqlite3)

case BatteryTimer.Repo.start_link() do
  {:ok, _} -> :ok
  {:error, {:already_started, _}} -> :ok
end

Ecto.Migrator.run(
  BatteryTimer.Repo,
  Path.join([File.cwd!(), "priv", "repo", "migrations"]),
  :up,
  all: true
)

ExUnit.start()
