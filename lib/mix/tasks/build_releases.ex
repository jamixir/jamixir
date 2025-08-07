defmodule Mix.Tasks.BuildReleases do
  @moduledoc """
  Builds releases for both tiny and prod environments with platform-specific naming and GitHub release automation.

  ## Usage
  mix build_releases

  ## Requirements & Assumptions

  ### Directory Structure
  - `jamixir-releases/` folder must exist as a sibling to the project root
  - Example: if project is in `/path/to/jamixir/`, releases folder should be `/path/to/jamixir-releases/`

  ### GitHub CLI Setup
  - GitHub CLI (`gh`) must be installed and authenticated
  - Run `gh auth login` before using this task
  - Must have push access to the jamixir-releases repository

  ### Platform Support
  - Linux (x86-64, arm64)
  - macOS (x86-64, arm64)
  - Automatically detects current platform and architecture

  ### Multi-Platform Workflow
  - Task supports collaborative builds across platforms
  - First run: Creates new GitHub release with current platform files
  - Subsequent runs: Adds files to existing release (if same version)
  - Uses `--clobber` flag to overwrite files with same names

  ## What This Task Does

  1. **Build Releases**: MIX_ENV=tiny and MIX_ENV=prod (with auto-confirm overwrite)
  2. **Rename Files**: Platform-specific naming format:
    - `jamixir_linux-x86-64-gp_JAM_VERSION_vAPP_VERSION_SIZE.tar.gz`
    - `jamixir_macos-arm64-gp_JAM_VERSION_vAPP_VERSION_SIZE.tar.gz`
  3. **Copy Files**: To `../jamixir-releases/` folder
  4. **GitHub Release**: Create new release or add to existing one
    - Tag/Release name: `gp-JAM_VERSION-APP_VERSION`
    - Auto-generated release notes (first creation only)

  ## Example Workflow

  1. Developer on Linux runs: `mix build_releases`
    - Creates release `gp-0.6.6-1.6.0` with Linux files
  2. Developer on macOS runs: `mix build_releases`
    - Adds macOS files to existing `gp-0.6.6-1.6.0` release

  ## Version Source
  Versions are read from `Jamixir.Meta` module which pulls from `mix.exs`:
  - JAM version: `jam_version` config
  - App version: `app_version` config

  **To create a new release**: Bump either `jam_version` or `app_version` in `mix.exs`
  - Release name format: `gp-JAM_VERSION-APP_VERSION`
  - Same versions = files added to existing release
  - Different versions = new release created
  """

  use Mix.Task

  @shortdoc "Builds releases for tiny and prod environments with platform-specific naming"

  @build_dir "_build"
  @relaese_repo_dir "../jamixir-releases"
  @release_envs ["tiny", "prod"]

  def run(_args) do
    {jam_major, jam_minor, jam_patch} = Jamixir.Meta.jam_version()
    {app_major, app_minor, app_patch} = Jamixir.Meta.app_version()

    jam_version = "#{jam_major}.#{jam_minor}.#{jam_patch}"
    app_version = "#{app_major}.#{app_minor}.#{app_patch}"
    platform_suffix = detect_platform()

    ctx = %{
      jam_version: jam_version,
      app_version: app_version,
      platform_suffix: platform_suffix,
      tiny_file: generate_filename(platform_suffix, jam_version, app_version, "tiny"),
      full_file: generate_filename(platform_suffix, jam_version, app_version, "full"),
      release_title: "gp-#{jam_version}-v#{app_version}"
    }

    Mix.shell().info("Building releases for platform: #{ctx.platform_suffix}")
    Mix.shell().info("JAM version: #{ctx.jam_version}, App version: #{ctx.app_version}")

    Enum.each(@release_envs, fn env ->
      Mix.shell().info("Building #{env} release...")

      {_output, 0} =
        System.cmd("mix", ["release", "--overwrite"],
          env: [{"MIX_ENV", env}],
          into: IO.stream(:stdio, :line)
        )
    end)

    # Rename the generated tar.gz files
    Enum.each(@release_envs, fn env ->
      rename_release_files(ctx, env)
    end)

    # Copy files to jamixir-releases folder and create GitHub release
    copy_to_releases_folder(ctx)
    create_github_release(ctx)

    Mix.shell().info("Release builds completed successfully!")
  end

  defp generate_filename(platform_suffix, jam_version, app_version, size) do
    "jamixir_#{platform_suffix}_#{jam_version}_v#{app_version}_#{size}.tar.gz"
  end

  defp detect_platform do
    {os, arch} =
      case :os.type() do
        {:unix, :darwin} ->
          {"macos", detect_arch()}

        {:unix, :linux} ->
          {"linux", detect_arch()}

        _ ->
          Mix.shell().error("Unsupported platform")
          System.halt(1)
      end

    "#{os}-#{arch}-gp"
  end

  defp detect_arch do
    case System.cmd("uname", ["-m"]) do
      {"x86_64\n", 0} ->
        "x86-64"

      {"aarch64\n", 0} ->
        "arm64"

      {"arm64\n", 0} ->
        "arm64"

      {arch, 0} ->
        Mix.shell().error("Unsupported architecture: #{String.trim(arch)}")
        System.halt(1)

      _ ->
        Mix.shell().error("Failed to detect architecture")
        System.halt(1)
    end
  end

  defp rename_release_files(ctx, env) do
    release_dir = "#{@build_dir}/#{env}"
    original_pattern = Path.join(release_dir, "jamixir-[0-9]*.tar.gz")

    target_filename = if env == "tiny", do: ctx.tiny_file, else: ctx.full_file

    # Find the actual generated file
    case Path.wildcard(original_pattern) do
      [actual_file] ->
        new_path = Path.join(release_dir, target_filename)

        case File.rename(actual_file, new_path) do
          :ok ->
            Mix.shell().info("Renamed #{env} release: #{target_filename}")

          {:error, reason} ->
            Mix.shell().error("Failed to rename #{env} release: #{reason}")
        end

      [] ->
        Mix.shell().error("No #{env} release tar.gz file found in #{release_dir}")

      multiple_files ->
        Mix.shell().error("Multiple #{env} release files found: #{inspect(multiple_files)}")
    end
  end

  defp copy_to_releases_folder(ctx) do
    # Check if releases directory exists
    unless File.exists?(@relaese_repo_dir) do
      Mix.shell().error("jamixir-releases directory not found at #{@relaese_repo_dir}")
      System.halt(0)
    end

    Mix.shell().info("Copying files to jamixir-releases folder...")

    # Copy the renamed files (with full paths)
    files_to_copy = [
      "_build/tiny/#{ctx.tiny_file}",
      "_build/prod/#{ctx.full_file}"
    ]

    Enum.each(files_to_copy, fn file_path ->
      if File.exists?(file_path) do
        filename = Path.basename(file_path)
        dest_path = Path.join(@relaese_repo_dir, filename)

        case File.cp(file_path, dest_path) do
          :ok ->
            Mix.shell().info("Copied: #{filename}")

          {:error, reason} ->
            Mix.shell().error("Failed to copy #{filename}: #{reason}")
        end
      else
        Mix.shell().error("File not found: #{file_path}")
      end
    end)
  end

  defp create_github_release(ctx) do
    tag_name = ctx.release_title

    # Change to releases directory
    original_dir = File.cwd!()
    File.cd!(@relaese_repo_dir)

    try do
      # Check if gh CLI is available
      case System.cmd("gh", ["--version"]) do
        {_output, 0} ->
          # Check if release already exists
          case System.cmd("gh", ["release", "view", tag_name], stderr_to_stdout: true) do
            {_output, 0} ->
              # Release exists, upload new files to it
              Mix.shell().info("Release #{tag_name} already exists. Adding new platform files...")

              case System.cmd("gh", [
                     "release",
                     "upload",
                     tag_name,
                     ctx.tiny_file,
                     ctx.full_file,
                     # This overwrites files with same name if they exist
                     "--clobber"
                   ]) do
                {_output, 0} ->
                  Mix.shell().info(
                    "Successfully added #{ctx.platform_suffix} files to existing release #{tag_name}!"
                  )

                {error, _} ->
                  Mix.shell().error("Failed to upload files to existing release: #{error}")
              end

            {_error, _} ->
              # Release doesn't exist, create it
              Mix.shell().info("Creating new GitHub release #{tag_name}...")

              case System.cmd("gh", [
                     "release",
                     "create",
                     tag_name,
                     "--title",
                     ctx.release_title,
                     "--generate-notes",
                     ctx.tiny_file,
                     ctx.full_file
                   ]) do
                {_output, 0} ->
                  Mix.shell().info("GitHub release #{tag_name} created successfully!")

                {error, _} ->
                  Mix.shell().error("Failed to create GitHub release: #{error}")
              end
          end

        {_error, _} ->
          Mix.shell().error(
            "GitHub CLI (gh) not found. Please install it to create releases automatically."
          )

          Mix.shell().info("Files have been copied to #{@relaese_repo_dir}")
      end
    after
      # Always return to original directory
      File.cd!(original_dir)
    end
  end
end
