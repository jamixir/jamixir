defmodule Block.HeaderTest do
  use ExUnit.Case

  alias Block.Header

  test "is_valid_header?/1 returns true when parent_hash is nil" do
    header = %Header{parent_hash: nil}

    assert Header.is_valid_header?(Storage.new, header)
  end

  test "is_valid_header?/1 returns false when parent header is not found" do
    header = %Header{parent_hash: "parent_hash"}

    assert !Header.is_valid_header?(Storage.new, header)
  end

  test "is_valid_header?/1 returns false when timeslot_index is not greater than parent header's timeslot_index" do
    header = %Header{parent_hash: :parent, timeslot_index: 2}
    s1 = Storage.put(Storage.new, :parent, %Header{timeslot_index: 1})
    s2 = Storage.put(s1, :header, header)

    assert Header.is_valid_header?(s2, header)
  end

  test "is_valid_header?/1 returns false when timeslot_index is in the future" do
    header = %Header{parent_hash: :parent, timeslot_index: 2}
    s1 = Storage.put(Storage.new, :parent, %Header{timeslot_index: 3})
    s2 = Storage.put(s1, :header, header)

    assert !Header.is_valid_header?(s2, header)
  end
end
