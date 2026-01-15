defmodule Pvm.Native.MemoryTest do
  import Pvm.Native
  import PVM.Memory.Constants
  use ExUnit.Case, async: true

  def a_0, do: min_allowed_address()

  setup do
    {:ok, memory_ref: build_memory()}
  end

  describe "memory_read/3 and set_memory_access/4" do
    test "read", %{memory_ref: memory_ref} do
      set_memory_access(memory_ref, a_0(), 5, 1)
      {:ok, <<0::40>>} = memory_read(memory_ref, a_0(), 5)
    end

    test "write and read back", %{memory_ref: memory_ref} do
      set_memory_access(memory_ref, a_0(), 7, 3)
      memory_write(memory_ref, a_0(), <<1, 2, 3, 4, 5>>)
      {:ok, <<1, 2, 3, 4, 5>>} = memory_read(memory_ref, a_0(), 5)
    end

    test "access violation on write", %{memory_ref: memory_ref} do
      set_memory_access(memory_ref, a_0(), 4, 3)
      size = page_size() + 1
      {:error, _} = memory_write(memory_ref, a_0(), <<1::size*8>>)
    end
  end

  describe "memory_access?/4" do
    test "default to no access", %{memory_ref: memory_ref} do
      refute memory_access?(memory_ref, a_0(), 5, 1)
      refute memory_access?(memory_ref, a_0(), 5, 3)
    end

    test "read access", %{memory_ref: memory_ref} do
      set_memory_access(memory_ref, a_0(), 10, 1)
      refute memory_access?(memory_ref, a_0(), 5, 3)
      assert memory_access?(memory_ref, a_0(), 5, 1)
    end

    test "read and write access", %{memory_ref: memory_ref} do
      set_memory_access(memory_ref, a_0(), 10, 3)
      assert memory_access?(memory_ref, a_0(), 5, 1)
      assert memory_access?(memory_ref, a_0(), 5, 3)

      set_memory_access(memory_ref, a_0(), 10, 0)
      refute memory_access?(memory_ref, a_0(), 5, 1)
      refute memory_access?(memory_ref, a_0(), 5, 3)
    end
  end
end
