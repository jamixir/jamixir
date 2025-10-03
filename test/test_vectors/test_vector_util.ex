defmodule TestVectorUtil do
  alias Block.Extrinsic
  alias Block.Extrinsic.Disputes
  alias Codec.State
  use ExUnit.Case
  import Mox
  import Codec.Encoder
  alias Util.Hash
  Application.put_env(:elixir, :ansi_enabled, true)

  @owner "w3f"
  @repo "jam-test-vectors"
  @branch "master"
  @headers [{"User-Agent", "Elixir"}]

  # ANSI color codes
  @blue IO.ANSI.blue()
  @green IO.ANSI.green()
  @yellow IO.ANSI.yellow()
  @red IO.ANSI.red()
  @cyan IO.ANSI.cyan()
  @bright IO.ANSI.bright()
  @reset IO.ANSI.reset()
  def print_error(file_name, expected, received, status) do
    status_indicator = if status == :pass, do: "#{@green}✓", else: "#{@red}✗"

    IO.puts("""
    #{@bright}#{@cyan}#{file_name}#{@reset}
    #{@yellow}│#{@reset} #{status_indicator}#{@reset} errors: expected #{format_error(expected)} / received #{format_error(received)}
    """)
  end

  def format_error("none"), do: "#{@blue}'none'#{@reset}"
  def format_error(error), do: "#{@yellow}'#{error}'#{@reset}"

  def fetch_and_parse_json(file_name, path, owner \\ @owner, repo \\ @repo, branch \\ @branch) do
    case fetch_file(file_name, path, owner, repo, branch) do
      {:ok, body} -> {:ok, Jason.decode!(body) |> Utils.atomize_keys()}
      e -> e
    end
  end

  def fetch_binary(file_name, path, owner \\ @owner, repo \\ @repo, branch \\ @branch) do
    case fetch_file(file_name, path, owner, repo, branch) do
      {:ok, body} -> body
      e -> e
    end
  end

  def local_vectors_dir do
    case System.get_env("JAM_PROJECTS_PATH") do
      nil -> "../"
      path -> path
    end
  end

  def list_test_files(path) do
    for f <- File.ls!(Path.join("#{local_vectors_dir()}/#{@repo}", path)),
        String.ends_with?(f, ".json") do
      String.replace(f, ".json", "")
    end
  end

  def fetch_file(file_name, path, owner \\ @owner, repo \\ @repo, branch \\ @branch) do
    file_path = "#{local_vectors_dir()}#{repo}/#{path}/#{file_name}"

    case File.read(file_path) do
      {:ok, content} ->
        {:ok, content}

      {:error, _} ->
        url = "https://raw.githubusercontent.com/#{owner}/#{repo}/#{branch}/#{path}/#{file_name}"
        fetch_from_url(url)
    end
  end

  defmacro define_repo_variables do
    quote do
      @owner "davxy"
      @repo "jam-test-vectors"
      @branch "master"
    end
  end

  defmacro define_vector_tests(type) do
    quote do
      for vector_type <- [:tiny, :full] do
        for file_name <- files_to_test() do
          @tag file_name: file_name
          @tag vector_type: vector_type
          @tag :"#{vector_type}_vectors"
          test "verify #{unquote(type)} #{vector_type} vectors #{file_name}", %{
            file_name: file_name,
            vector_type: vector_type
          } do
            execute_test(file_name, "stf/#{unquote(type)}/#{vector_type}")
          end
        end
      end
    end
  end

  defp fetch_from_url(url) do
    result =
      case HTTPoison.get(url, @headers) do
        {:ok, %HTTPoison.Response{status_code: 200, body: body}} -> {:ok, body}
        {:ok, %HTTPoison.Response{}} -> {:error, :failed_to_fetch}
        {:error, %HTTPoison.Error{}} -> {:error, :failed_to_fetch}
      end

    case result do
      {:ok, body} ->
        {:ok, body}

      # try to fetch files from local system when JAM_PROJECTS_PATH is set
      {:error, e} ->
        {:error, "#{e} cant read file or download it at #{url}"}
    end
  end

  def accumulate_mock_return,
    do: %{
      accumulation_outputs: <<>>,
      authorizer_queue: [],
      services: %{},
      next_validators: [],
      privileged_services: %{},
      accumulation_history: %{},
      ready_to_accumulate: %{},
      accumulation_stats: %{}
    }

  def stats_mock,
    do: %{
      blocks: 0,
      tickets: 0,
      pre_images: 0,
      pre_images_size: 0,
      guarantees: 0,
      assurances: 0
    }

  def mock_accumulate do
    stub(MockAccumulation, :do_transition, fn _, _, _ -> accumulate_mock_return() end)
  end

  def put_vector_services_stats_on_state(json_data) do
    json_data =
      put_in(json_data[:post_state][:statistics], %{
        services: json_data[:post_state][:statistics],
        vals_current: [],
        vals_last: [],
        cores: []
      })

    json_data =
      put_in(json_data[:pre_state][:statistics], %{
        services: [],
        vals_current: for(_ <- 1..6, do: stats_mock()),
        vals_last: for(_ <- 1..6, do: stats_mock()),
        cores: []
      })

    json_data
  end

  def assert_expected_results(json_data, tested_keys, file_name, extrinsic \\ nil, header \\ nil) do
    pre_state = State.Json.decode(json_data[:pre_state])
    ok_output = json_data[:output][:ok]

    header =
      header || Map.merge(if(ok_output == nil, do: %{}, else: ok_output), json_data[:input])

    block =
      Block.from_json(%{
        extrinsic: extrinsic || default_build_extrinsic(json_data),
        header: header
      })

    expected_state = State.Json.decode(json_data[:post_state])
    result = System.State.add_block(pre_state, block)

    case {result, json_data[:output][:err]} do
      {{:ok, state_}, nil} ->
        # No error expected, assert on the tested keys
        Enum.each(tested_keys, fn key ->
          our_result = fetch_key_from_state(state_, key)
          expected_result = fetch_key_from_state(expected_state, key)

          {our_result, expected_result} =
            if key == :services do
              transform_services_storage(our_result, expected_result)
            else
              {our_result, expected_result}
            end

          # special handling for services map - so many fields to compare full objects
          if key == :services do
            for {id, service} <- expected_result do
              exp_service = Map.from_struct(service)

              for {field, value} <- exp_service do
                our_value = Map.get(our_result[id], field)

                assert our_value == value,
                       "In services[#{id}].#{field} - expected #{inspect(value)}, got #{inspect(our_value)}"
              end
            end
          else
            assert our_result == expected_result
          end
        end)

      {{:ok, _}, error_expected} ->
        print_error(file_name, error_expected, "none", :fail)
        flunk("Expected error '#{error_expected}', but no error occurred")

      {{:error, _returned_state, reason}, nil} ->
        print_error(file_name, "none", reason, :fail)
        flunk("Expected no error, but received error: '#{reason}'")

      {{:error, returned_state, reason}, error_expected} ->
        if System.get_env("FAIL_ON_WRONG_ERROR") do
          assert String.to_atom(error_expected) == reason
        end

        if System.get_env("PRINT_ERROR") do
          print_error(file_name, error_expected, reason, :pass)
        end

        Enum.each(tested_keys, fn key ->
          our_result = fetch_key_from_state(returned_state, key)
          expected_result = fetch_key_from_state(pre_state, key)

          assert our_result == expected_result,
                 "State changed unexpectedly for key: #{format_key(key)}"
        end)
    end

    :ok
  end

  defp transform_services_storage(our_result, expected_result) do
    {transform_services(our_result), transform_services(expected_result)}
  end

  # the key traformation logic comes from Chapter B.6 (General functions)
  # read host call https://graypaper.fluffylabs.dev/#/cc517d7/30bb0130c201?v=0.6.6
  defp transform_services(services) do
    for {service_id, service_account} <- services, service_account != nil, into: %{} do
      updated_storage =
        for {storage_key, storage_value} <- service_account.storage, into: %{} do
          new_key =
            if byte_size(storage_key) == 32 do
              storage_key
            else
              Hash.default(<<service_id::m(service_id)>> <> storage_key)
            end

          {new_key, storage_value}
        end

      updated_service_account = %{service_account | storage: updated_storage}
      {service_id, updated_service_account}
    end
  end

  defp fetch_key_from_state(state, key) do
    case key do
      {namespace, subkey} ->
        Map.get(Map.get(state, namespace), subkey)

      {namespace, subkey, func} when is_function(func) ->
        func.(Map.get(Map.get(state, namespace), subkey))

      simple_key ->
        Map.get(state, simple_key)
    end
  end

  defp default_build_extrinsic(json_data) do
    Map.from_struct(%Extrinsic{})
    |> Map.put(:tickets, json_data[:input][:extrinsic])
    |> Map.put(:disputes, Map.from_struct(%Disputes{}))
  end

  defp format_key({namespace, subkey, _}), do: "#{namespace}.#{subkey}"
  defp format_key({namespace, subkey}), do: "#{namespace}.#{subkey}"
  defp format_key(key), do: "#{key}"
end
