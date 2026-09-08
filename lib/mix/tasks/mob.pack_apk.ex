defmodule Mix.Tasks.Mob.PackApk do
  @shortdoc "Bundle OTP into the debug APK and adb-install it"
  @moduledoc """
  Chromos/ARC cannot `adb run-as`, so `mix mob.deploy --native` cannot push
  the OTP tree after install. Package `otp.zip` into the APK the same way
  `mix mob.release --android` does, then install with adb.

  Defaults to the connected device ABI (x86_64 on this Chromos box).

  One APK holds one OTP zip, so arm64 and x86_64 are separate builds:

      mix mob.pack_apk --abi arm64-v8a --no-install --output battery_timer-arm64.apk
      mix mob.pack_apk --abi x86_64 --no-install --output battery_timer-x86_64.apk
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        switches: [
          abi: :string,
          device: :string,
          slim: :boolean,
          install: :boolean,
          output: :string
        ]
      )

    Mix.Task.run("compile")

    abi = opts[:abi] || detect_abi(opts[:device])
    slim? = Keyword.get(opts, :slim, true)
    install? = Keyword.get(opts, :install, true)
    app_name = Mix.Project.config()[:app] |> to_string()

    Mix.shell().info("Packing OTP for ABI #{abi} into debug APK...")

    with {:ok, otp_dir} <- MobDev.OtpDownloader.ensure_android(abi),
         :ok <- zig_native(abi, otp_dir),
         {:ok, staging} <- stage(otp_dir, app_name),
         zip_path <- zip_path(),
         :ok <- File.mkdir_p(Path.dirname(zip_path)),
         {:ok, info} <- MobDev.OtpAssetBundle.build(staging, zip_path, slim: slim?),
         _ <- File.rm_rf!(staging),
         _ <-
           Mix.shell().info(
             "  otp.zip: #{info.zipped_files} files, #{div(info.zip_size_kb, 1024)}MB"
           ),
         {:ok, apk} <- assemble_debug(abi),
         apk <- copy_output(apk, opts[:output]) do
      Mix.shell().info("  APK: #{apk}")
      if install?, do: install_apk(apk, opts[:device]), else: :ok
    else
      {:error, reason} -> Mix.raise(inspect(reason))
    end
  end

  defp zig_native(abi, otp_dir) do
    case MobDev.Toolchain.zig_status() do
      {:ok, _} ->
        copy_erts_helpers!(otp_dir, abi)
        run_zig(abi, otp_dir)

      status ->
        {:error, MobDev.NativeBuild.zig_required_message(status)}
    end
  end

  defp run_zig(abi, otp_dir) do
    platform =
      case abi do
        "arm64-v8a" -> :android_arm64
        "armeabi-v7a" -> :android_arm32
        "x86_64" -> :android_x86_64
      end

    {:ok, nif_args} = MobDev.NativeBuild.project_nif_zig_args(platform)
    nif_args = Enum.reject(nif_args, &String.starts_with?(&1, "-Dproject_root="))

    app_name = Mix.Project.config()[:app] |> to_string()
    root = Path.expand(".")
    jni_libs = Path.join([root, "android/app/src/main/jniLibs", abi])
    File.mkdir_p!(jni_libs)

    args = [
      "build",
      "native-lib",
      "--build-file",
      "android/app/src/main/jni/build.zig",
      "--prefix",
      "android/app/build/zig-out",
      "-Dabi=#{abi}",
      "-Dotp_dir=#{otp_dir}",
      "-Derts_vsn=#{erts_vsn(otp_dir)}",
      "-Dmob_dir=#{Path.join(root, "deps/mob")}",
      "-Ddriver_tab=#{Path.join(root, "priv/generated/driver_tab_android.zig")}",
      "-Dproject_jni_dir=#{Path.join(root, "android/app/src/main/jni")}",
      "-Dndk_sysroot=#{MobDev.NdkVersion.sysroot()}",
      "-Dapp_name=#{app_name}",
      "-Dproject_root=#{root}",
      "-Dexqlite_src=#{Path.join(root, "deps/exqlite/c_src")}"
      | nif_args
    ]

    Mix.shell().info("  zig build native-lib -Dabi=#{abi}")

    case System.cmd("zig", args, stderr_to_stdout: true, into: IO.stream()) do
      {_, 0} -> :ok
      {_, rc} -> {:error, "zig build #{abi} failed (#{rc})"}
    end
  end

  defp copy_erts_helpers!(otp_dir, abi) do
    jni_libs = Path.join(["android/app/src/main/jniLibs", abi])
    File.mkdir_p!(jni_libs)

    case Path.wildcard(Path.join(otp_dir, "erts-*/bin")) do
      [erts_bins | _] ->
        Enum.each(
          [
            {"erl_child_setup", "liberl_child_setup.so"},
            {"inet_gethost", "libinet_gethost.so"},
            {"epmd", "libepmd.so"}
          ],
          fn {exe, lib} ->
            src = Path.join(erts_bins, exe)
            if File.exists?(src), do: File.cp!(src, Path.join(jni_libs, lib))
          end
        )

      _ ->
        :ok
    end
  end

  defp erts_vsn(otp_dir) do
    case File.ls(otp_dir) do
      {:ok, entries} ->
        entries
        |> Enum.filter(&String.starts_with?(&1, "erts-"))
        |> Enum.sort(:desc)
        |> List.first() || "erts-17.0"

      _ ->
        "erts-17.0"
    end
  end

  defp zip_path, do: Path.expand("android/app/src/debug/assets/otp.zip")

  defp stage(otp_dir, app_name) do
    staging =
      Path.join(System.tmp_dir!(), "mob_pack_apk_#{:erlang.unique_integer([:positive])}")

    File.rm_rf!(staging)

    case System.cmd("cp", ["-R", otp_dir <> "/.", staging], stderr_to_stdout: true) do
      {_, 0} ->
        dest = Path.join(staging, app_name)
        File.mkdir_p!(dest)

        Enum.each(MobDev.HotPush.runtime_beam_dirs(), fn dir ->
          System.cmd("cp", ["-r", "#{Path.expand(dir)}/.", dest], stderr_to_stdout: true)
        end)

        local_priv = Path.join(File.cwd!(), "priv")

        if File.dir?(local_priv) do
          System.cmd("cp", ["-R", local_priv, Path.join(dest, "priv")], stderr_to_stdout: true)
        end

        add_exqlite!(staging)
        {:ok, staging}

      {out, _} ->
        {:error, "copy OTP failed: #{out}"}
    end
  end

  defp add_exqlite!(staging) do
    with vsn when is_binary(vsn) <- MobDev.AppFile.dep_version(:exqlite),
         [ebin | _] <- Path.wildcard("_build/dev/lib/exqlite/ebin") do
      lib_dir = Path.join(staging, "lib/exqlite-#{vsn}")
      File.mkdir_p!(Path.join(lib_dir, "ebin"))
      File.mkdir_p!(Path.join(lib_dir, "priv"))

      System.cmd("cp", ["-r", "#{Path.expand(ebin)}/.", Path.join(lib_dir, "ebin")],
        stderr_to_stdout: true
      )
    else
      _ -> :ok
    end
  end

  defp assemble_debug(abi) do
    gradlew = Path.expand("android/gradlew")
    apk = Path.expand("android/app/build/outputs/apk/debug/app-debug.apk")

    case System.cmd(
           "bash",
           [gradlew, "assembleDebug", "--no-daemon", "-PmobAbi=#{abi}"],
           cd: Path.expand("android"),
           stderr_to_stdout: true,
           into: IO.stream()
         ) do
      {_, 0} ->
        if File.exists?(apk), do: {:ok, apk}, else: {:error, "APK missing at #{apk}"}

      {_, rc} ->
        {:error, "assembleDebug failed (#{rc})"}
    end
  end

  defp copy_output(apk, nil), do: apk

  defp copy_output(apk, output) do
    dest = Path.expand(output)
    File.mkdir_p!(Path.dirname(dest))
    File.cp!(apk, dest)
    dest
  end

  defp install_apk(apk, device) do
    adb = System.find_executable("adb") || Mix.raise("adb not found")
    serial = device || default_serial()
    args = if serial, do: ["-s", serial, "install", "-r", apk], else: ["install", "-r", apk]
    Mix.shell().info("  adb #{Enum.join(args, " ")}")

    case System.cmd(adb, args, stderr_to_stdout: true) do
      {out, 0} ->
        Mix.shell().info(out)
        launch(serial)

      {out, rc} ->
        Mix.raise("adb install failed (#{rc}): #{out}")
    end
  end

  defp launch(nil), do: :ok

  defp launch(serial) do
    adb = System.find_executable("adb")

    System.cmd(
      adb,
      [
        "-s",
        serial,
        "shell",
        "am",
        "start",
        "-n",
        "com.example.battery_timer/.MainActivity"
      ],
      stderr_to_stdout: true
    )

    :ok
  end

  defp detect_abi(device) do
    adb = System.find_executable("adb")

    args =
      if device,
        do: ["-s", device, "shell", "getprop", "ro.product.cpu.abi"],
        else: ["shell", "getprop", "ro.product.cpu.abi"]

    case adb && System.cmd(adb, args, stderr_to_stdout: true) do
      {out, 0} ->
        case String.trim(out) do
          "x86_64" -> "x86_64"
          "armeabi-v7a" -> "armeabi-v7a"
          _ -> "arm64-v8a"
        end

      _ ->
        "arm64-v8a"
    end
  end

  defp default_serial do
    adb = System.find_executable("adb") || Mix.raise("adb not found")

    case System.cmd(adb, ["devices"], stderr_to_stdout: true) do
      {out, 0} ->
        out
        |> String.split("\n")
        |> Enum.map(&String.split(&1, "\t"))
        |> Enum.find_value(fn
          [serial, "device"] -> serial
          _ -> nil
        end)

      _ ->
        nil
    end
  end
end
