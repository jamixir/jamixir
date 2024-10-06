defmodule System.PVM.MemoryTest do
  alias System.PVM.Memory
  use ExUnit.Case

  describe "readable_indexes/1" do
    test "returns indexes of non-nil access elements" do
      memory = %Memory{access: [:read, nil, :write, :read, nil]}
      assert Memory.readable_indexes(memory) == MapSet.new([0, 2, 3])
    end

    test "returns an empty set when all access elements are nil" do
      memory = %Memory{access: [nil, nil, nil]}
      assert Memory.readable_indexes(memory) == MapSet.new()
    end

    test "returns an empty set when access list is empty" do
      memory = %Memory{access: []}
      assert Memory.readable_indexes(memory) == MapSet.new()
    end
  end

  describe "writable_indexes/1" do
    test "returns indexes of :write access elements" do
      memory = %Memory{access: [:read, :write, :write, :read, :write]}
      assert Memory.writable_indexes(memory) == MapSet.new([1, 2, 4])
    end

    test "returns an empty set when there are no :write access elements" do
      memory = %Memory{access: [:read, nil, :read]}
      assert Memory.writable_indexes(memory) == MapSet.new()
    end

    test "returns an empty set when access list is empty" do
      memory = %Memory{access: []}
      assert Memory.writable_indexes(memory) == MapSet.new()
    end
  end
end
