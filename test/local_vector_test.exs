defmodule LocalVectorTest do
  use ExUnit.Case
  alias Block.Header
  import Mox
  setup :verify_on_exit!

  @vector_dir "test/test_vectors"

  describe "test vectors" do
    setup do
      Application.put_env(:jamixir, :header_seal, HeaderSealMock)

      on_exit(fn ->
        Application.put_env(:jamixir, :header_seal, System.HeaderSeal)
      end)

      :ok
    end

    @tag :test_vectors_local
    test "verify test vector for enact-epoch-change-with-no-tickets-1.json" do
      file_name = "enact-epoch-change-with-no-tickets-1.json"
      {:ok, json_data} = read_local_json(file_name)

      HeaderSealMock
      |> expect(:do_validate_header_seals, fn _, _, _, _ ->
        {:ok, %{vrf_signature_output: json_data["input"]["entropy"] |> Utils.hex_to_binary()}}
      end)

      assert_expected_results(json_data, [
        :timeslot,
        :entropy_pool,
        :prev_validators,
        :curr_validators,
        :safrole
      ])
    end
  end

  defp read_local_json(file_name) do
    file_path = Path.join(@vector_dir, file_name)

    case File.read(file_path) do
      {:ok, contents} ->
        {:ok, Jason.decode!(contents)}

      {:error, reason} ->
        IO.puts("Failed to read file: #{reason}")
        {:error, :failed_to_read}
    end
  end

  defp assert_expected_results(json_data, tested_keys) do
    # Translate JSON data into your system modules and run assertions
    # Example:
    pre_state = System.State.from_json(json_data["pre_state"])
    header = %Header{timeslot: json_data["input"]["slot"]}

    new_state =
      System.State.add_block(pre_state, %Block{header: header, extrinsic: %Block.Extrinsic{}})

    expected_state = System.State.from_json(json_data["post_state"])

    Enum.each(tested_keys, fn key ->
      assert Map.get(new_state, key) == Map.get(expected_state, key),
             "Mismatch for key: #{key}"
    end)
  end
end
