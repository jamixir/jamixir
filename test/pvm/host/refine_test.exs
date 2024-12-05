defmodule PVM.Host.RefineTest do
  use ExUnit.Case
  alias PVM.{Memory, RefineContext, Registers}
  alias PVM.Host.{Refine, Wrapper}

  describe "wrapped host calls" do
    setup do
      memory = %Memory{}
      context = %RefineContext{}
      registers = %Registers{}
      gas = 1000

      {:ok, memory: memory, context: context, registers: registers, gas: gas}
    end

    @host_calls [
      {:historical_lookup, [1, %{}, 123]},
      {:import, [["test_segment"]]},
      {:export, [0]},
      {:machine, []},
      {:peek, []},
      {:poke, []},
      {:zero, []},
      {:void, []},
      {:invoke, []},
      {:expunge, []}
    ]

    for {function, extra_args} <- @host_calls do
      test "#{function}/#{length(extra_args) + 4} wraps internal implementation", %{
        memory: memory,
        context: context,
        registers: registers,
        gas: gas
      } do
        function = unquote(function)
        extra_args = unquote(Macro.escape(extra_args))

        # Call with sufficient gas
        {exit_reason, %{gas: new_gas}, _new_context} =
          apply(Refine, function, [gas, registers, memory, context] ++ extra_args)

        # Basic verification that the call went through
        assert exit_reason == :continue
        assert new_gas == gas - Wrapper.default_gas()

        # Call with insufficient gas
        {exit_reason, _new_state, _new_context} =
          apply(Refine, function, [8, registers, memory, context] ++ extra_args)

        assert exit_reason == :out_of_gas
      end
    end
  end
end
