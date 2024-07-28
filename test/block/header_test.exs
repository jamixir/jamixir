defmodule Block.HeaderTest do
  use ExUnit.Case
  import TestHelper

  alias Block.Header

  test "is_valid_header?/1 returns true when parent_hash is nil" do
    header = %Header{parent_hash: nil, timeslot: past_timeslot()}
    assert Header.is_valid_header?(Storage.new(), header)
  end

  test "is_valid_header?/1 returns false when parent header is not found" do
    header = %Header{parent_hash: "parent_hash", timeslot: past_timeslot()}

    assert !Header.is_valid_header?(Storage.new(), header)
  end

  test "is_valid_header?/1 returns false when timeslot is not greater than parent header's timeslot" do
    header = %Header{parent_hash: :parent, timeslot: 2}
    s1 = Storage.put(Storage.new(), :parent, %Header{timeslot: 1})
    s2 = Storage.put(s1, :header, header)

    assert Header.is_valid_header?(s2, header)
  end

  test "is_valid_header?/1 returns false when timeslot is in the future" do
    header = %Header{parent_hash: :parent, timeslot: 2}
    s1 = Storage.put(Storage.new(), :parent, %Header{timeslot: 3})
    s2 = Storage.put(s1, :header, header)

    assert !Header.is_valid_header?(s2, header)
  end

  test "is_valid_header?/1 returns false if timeslot is bigger now" do
    header = %Header{parent_hash: nil, timeslot: future_timeslot()}

    assert !Header.is_valid_header?(Storage.new(), header)
  end
end
