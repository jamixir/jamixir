defmodule System.State.ReadyTest do
  use ExUnit.Case
  alias System.State.Ready
  alias Block.Extrinsic.Guarantee.WorkReport
  alias Util.Hash

  setup_all do
    base_ready = %Ready{
      work_report: %WorkReport{
        refinement_context: %RefinementContext{prerequisite: Hash.one()}
      }
    }

    ready2 = put_in(base_ready.work_report.refinement_context.prerequisite, Hash.two())
    ready_nil = put_in(base_ready.work_report.refinement_context.prerequisite, nil)

    {:ok, ready1: base_ready, ready2: ready2, ready_nil: ready_nil}
  end

  describe "q/1" do
    test "returns empty MapSet for initial state" do
      assert Ready.q(Ready.initial_state()) == MapSet.new()
    end

    test "collects unique prerequisite hashes from work reports", %{ready1: ready1, ready2: ready2} do
      assert Ready.q([[ready1, ready2], [], [ready1]]) == MapSet.new([Hash.one(), Hash.two()])
    end

    test "handles sparse lists with empty sublists", %{ready1: ready1, ready2: ready2} do
      assert Ready.q([[], [ready1], [], [ready2], []]) == MapSet.new([Hash.one(), Hash.two()])
    end

    test "filters out nil prerequisites", %{ready1: ready1, ready_nil: ready_nil} do
      assert Ready.q([[ready1, ready_nil]]) == MapSet.new([Hash.one()])
    end
  end
end
