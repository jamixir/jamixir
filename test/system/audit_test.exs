defmodule System.AuditTest do
  alias Block.Extrinsic.Guarantee.WorkReport
  import System.Audit
  import Jamixir.Factory
  use ExUnit.Case
  alias Util.{Crypto, Hash}

  setup_all do
    keypair =
      {<<158, 164, 60, 192, 49, 61, 243, 121, 24, 219, 121, 54, 103, 44, 248, 14, 226, 104, 117,
         205, 136, 74, 59, 224, 23, 37, 120, 6, 215, 36, 243, 4>>,
       <<79, 146, 78, 23, 36, 189, 99, 204, 43, 246, 90, 63, 70, 189, 152, 159, 186, 226, 147,
         146, 202, 123, 3, 231, 73, 140, 132, 177, 126, 105, 49, 187>>}

    {:ok, keypair: keypair}
  end

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

  describe "initial_items_to_audit/3" do
    test "build a list of work reports to audit", %{keypair: keypair} do
      work_reports = build_list(20, :work_report)

      list = initial_items_to_audit(keypair, Hash.one(), work_reports)
      assert length(list) == 10
    end

    test "ignore nil reports on list", %{keypair: keypair} do
      work_reports = build_list(3, :work_report) ++ List.duplicate(nil, 10)

      list = initial_items_to_audit(keypair, Hash.one(), work_reports)
      assert length(list) == 3
      assert Enum.all?(list, fn {_, w} -> w != nil end)
    end
  end

  describe "random_selection/3" do
    test "build a random list of work reports", %{keypair: keypair} do
      work_reports = build_list(10, :work_report)

      # Random selection of work reports
      [{core, %WorkReport{}} | _] = list = random_selection(keypair, Hash.one(), work_reports)

      assert length(list) == 10
      assert core == 2

      # Random selection of work reports with different s0 - different core selected
      [{core, %WorkReport{}} | _] = random_selection(keypair, Hash.two(), work_reports)

      assert core == 3
    end
  end

  describe "announcement_signature/3" do
    test "check announcement signature" do
      {pub, priv} = :crypto.generate_key(:eddsa, :ed25519)
      header = build(:decodable_header)
      n = Hash.zero()

      sign = announcements_signature(priv, header, n)
      assert Crypto.valid_signature?(sign, sign_payload(header, n), pub)
    end
  end
end
