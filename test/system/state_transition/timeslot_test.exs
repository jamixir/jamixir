defmodule System.StateTransition.TimeslotTest do
  use ExUnit.Case
  import Jamixir.Factory
  alias Block
  alias System.State
  import Mox
  setup :verify_on_exit!

  setup_all do
    %{state: state, key_pairs: key_pairs} = build(:genesis_state_with_safrole)
    # All `mockable` defs will be stubbed
    Application.put_env(:jamixir, :original_modules, [Util.Time])

    on_exit(fn ->
      Application.delete_env(:jamixir, :original_modules)
    end)

    {:ok, %{state: state, key_pairs: key_pairs}}
  end

  test "add_block/2 correctly sets timeslot", %{state: state, key_pairs: key_pairs} do
    state = %{
      state
      | timeslot: 6
    }

    block =
      build(:safrole_block,
        state: state,
        timeslot: 7,
        key_pairs: key_pairs,
        block_author_key_index: 1
      )

    {:ok, state_} = State.add_block(state, block)

    assert state_.timeslot === 7
  end
end
