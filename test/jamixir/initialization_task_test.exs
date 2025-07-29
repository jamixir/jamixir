defmodule Jamixir.InitializationTaskTest do
  use ExUnit.Case, async: false
  alias Jamixir.Genesis
  alias Jamixir.InitializationTask

  describe "run/0" do
    test "stores jam_state in storage after initialization" do
      :ok = InitializationTask.run()
      stored_state = Storage.get_state(Genesis.genesis_block_header())
      assert stored_state != nil
      assert is_struct(stored_state, System.State)
    end
  end
end
