defmodule System.AuditTest do
  import System.Audit
  use ExUnit.Case

  describe "current_trench/2" do
    # ⌊ (t - P * Ht) / A ⌋
    test "correct trench calculation" do
      assert current_trench(0, 0) == 0
      assert current_trench(1, 6) == 0
      assert current_trench(1, 7) == 0
      assert current_trench(1, 12) == 0
      assert current_trench(1, 14) == 1
    end
  end
end
