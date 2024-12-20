defmodule PVM.Host.GeneralTest do
  use ExUnit.Case
  alias PVM.Host.General
  alias PVM.{Memory, Registers}
  alias System.State.ServiceAccount
  alias Util.Hash
  import PVM.Constants.HostCallResult
  use Codec.Encoder

  describe "gas/4" do
    setup do
      m = %Memory{}
      c = %ServiceAccount{}
      {:ok, m: m, c: c}
    end

    test "returns remaining gas when continuing", %{m: m, c: c} do
      g = 100
      default_gas = PVM.Host.Gas.default_gas()
      remaining_gas = g - default_gas
      r = %Registers{}

      assert %{
               exit_reason: :continue,
               gas: ^remaining_gas,
               registers: %{r7: ^remaining_gas},
               memory: ^m,
               context: ^c
             } = General.gas(g, r, m, c)
    end

    test "returns out of gas when gas is depleted", %{m: m, c: c} do
      r = %Registers{}

      assert %{
               exit_reason: :out_of_gas,
               gas: 0,
               registers: ^r,
               memory: ^m,
               context: ^c
             } = General.gas(0, r, m, c)
    end
  end

  describe "out of gas using" do
    setup do
      m = %Memory{} |> Memory.set_default_access(:write)
      value = "value" |> String.pad_trailing(32, "\0")
      other_value = "other_value" |> String.pad_trailing(32, "\0")
      hash = Hash.default(value)
      other_hash = Hash.default(other_value)
      c = %ServiceAccount{preimage_storage_p: %{hash => value}}
      s = %{1 => %ServiceAccount{preimage_storage_p: %{other_hash => other_value}}}

      {:ok, m: m, c: c, s: s}
    end

    test "no change when out of gas", %{m: m, c: c, s: s} do
      r = %Registers{r7: 1, r8: 0}
      m = Memory.set_access(m, 0, 32, nil)
      result = General.lookup(9, r, m, c, 0, s)
      assert result.registers == r
      assert result.memory == m
      assert result.context == c
      assert result.exit_reason == :out_of_gas
      assert result.gas == 0
    end
  end

  describe "lookup/6" do
    setup do
      m = %Memory{} |> Memory.set_default_access(:write)
      value = "value" |> String.pad_trailing(32, "\0")
      other_value = "other_value" |> String.pad_trailing(32, "\0")
      hash = Hash.default(value)
      other_hash = Hash.default(other_value)
      c = %ServiceAccount{preimage_storage_p: %{hash => value}}
      s = %{1 => %ServiceAccount{preimage_storage_p: %{other_hash => other_value}}}
      g = 100

      {:ok,
       m: m,
       c: c,
       s: s,
       g: g,
       hash: hash,
       other_hash: other_hash,
       value: value,
       other_value: other_value}
    end

    test "handles service selection", %{
      m: m,
      c: c,
      s: s,
      g: g,
      value: value,
      other_value: other_value
    } do
      {:ok, m} = Memory.write(m, 0, value)
      bo = 100
      bz = byte_size(value)
      none = none()

      # Case 1: w7 = service_index (uses c)
      r = %Registers{r7: 0, r8: 0, r9: bo, r10: bz}

      assert %{
               registers: %{r7: ^bz},
               memory: m_
             } = General.lookup(g, r, m, c, 0, s)

      assert {:ok, ^value} = Memory.read(m_, bo, bz)

      # Case 2: w7 = max_64_bit (uses c)
      r = %Registers{r7: 0xFFFF_FFFF_FFFF_FFFF, r8: 0, r9: bo, r10: bz}

      assert %{
               registers: %{r7: ^bz},
               memory: m_
             } = General.lookup(g, r, m, c, 0, s)

      assert {:ok, ^value} = Memory.read(m_, bo, bz)

      # Case 3: w7 points to different service (uses s[1])
      {:ok, m} = Memory.write(m, 0, other_value)
      r = %Registers{r7: 1, r8: 0, r9: bo, r10: bz}

      assert %{
               registers: %{r7: ^bz},
               memory: m_
             } = General.lookup(g, r, m, c, 0, s)

      assert {:ok, ^other_value} = Memory.read(m_, bo, bz)

      # Case 4: w7 points to non-existent service
      r = %Registers{r7: 999, r8: 0, r9: bo, r10: bz}
      assert %{registers: %{r7: ^none}, memory: ^m} = General.lookup(g, r, m, c, 0, s)
    end

    test "handles memory read failure", %{m: m, c: c, s: s, g: g} do
      r = %Registers{r7: 1, r8: 0}
      m = Memory.set_access(m, 0, 32, nil)
      oob = oob()
      assert %{registers: %{r7: ^oob}, memory: ^m} = General.lookup(g, r, m, c, 0, s)
    end

    test "handles memory write failure", %{m: m, c: c, s: s, g: g} do
      value = "value" |> String.pad_trailing(32, "\0")
      hash = Hash.default(value)
      oob = oob()
      c = %{c | preimage_storage_p: %{hash => value}}
      {:ok, m} = Memory.write(m, 0, value)

      r = %Registers{r7: 1, r8: 0, r9: 100, r10: byte_size(value)}
      m = Memory.set_access(m, 100, byte_size(value), :read)

      assert %{registers: %{r7: ^oob}, memory: ^m} = General.lookup(g, r, m, c, 0, s)
    end
  end

  describe "read/6" do
    setup do
      m = %Memory{} |> Memory.set_default_access(:write)
      value = "value" |> String.pad_trailing(32, "\0")
      key = "key" |> String.pad_trailing(32, "\0")
      other_value = "other_value" |> String.pad_trailing(32, "\0")
      other_key = "other_key" |> String.pad_trailing(32, "\0")

      storage_key = Hash.default(e_le(0, 4) <> key)
      other_storage_key = Hash.default(e_le(0, 4) <> other_key)

      c = %ServiceAccount{storage: %{storage_key => value}}
      s = %{1 => %ServiceAccount{storage: %{other_storage_key => other_value}}}
      g = 100

      {:ok,
       m: m,
       c: c,
       s: s,
       g: g,
       key: key,
       value: value,
       other_key: other_key,
       other_value: other_value}
    end

    test "handles service selection", %{
      m: m,
      c: c,
      s: s,
      g: g,
      key: key,
      value: value,
      other_key: other_key,
      other_value: other_value
    } do
      bo = 100
      bz = byte_size(value)

      # Case 1: w7 = service_index (uses c)
      {:ok, m} = Memory.write(m, 0, key)
      r = %Registers{r7: 0, r8: 0, r9: byte_size(key), r10: bo, r11: bz}
      result = General.read(g, r, m, c, 0, s)
      assert result.registers.r7 == bz
      assert {:ok, ^value} = Memory.read(result.memory, bo, bz)

      # Case 2: w7 = max_64_bit (uses c)
      r = %Registers{r7: 0xFFFF_FFFF_FFFF_FFFF, r8: 0, r9: byte_size(key), r10: bo, r11: bz}
      result = General.read(g, r, m, c, 0, s)
      assert result.registers.r7 == bz
      assert {:ok, ^value} = Memory.read(result.memory, bo, bz)

      # Case 3: w7 points to different service (uses s[1])
      {:ok, m} = Memory.write(m, 0, other_key)
      r = %Registers{r7: 1, r8: 0, r9: byte_size(other_key), r10: bo, r11: bz}
      result = General.read(g, r, m, c, 0, s)
      assert result.registers.r7 == byte_size(other_value)
      assert {:ok, ^other_value} = Memory.read(result.memory, bo, byte_size(other_value))

      # Case 4: w7 points to non-existent service
      r = %Registers{r7: 999, r8: 0, r9: byte_size(key), r10: bo, r11: bz}
      result = General.read(g, r, m, c, 0, s)
      assert result.registers.r7 == none()
      assert result.memory == m
    end

    test "handles key not in storage", %{m: m, c: c, s: s, g: g} do
      missing_key = "missing" |> String.pad_trailing(32, "\0")
      {:ok, m} = Memory.write(m, 0, missing_key)
      r = %Registers{r7: 0, r8: 0, r9: byte_size(missing_key), r10: 100, r11: 32}
      result = General.read(g, r, m, c, 0, s)
      assert result.registers.r7 == none()
      assert result.memory == m
    end

    test "handles memory read failure", %{m: m, c: c, s: s, g: g, key: key} do
      m = Memory.set_access(m, 0, byte_size(key), nil)
      r = %Registers{r7: 0, r8: 0, r9: byte_size(key), r10: 100, r11: 32}
      result = General.read(g, r, m, c, 0, s)
      assert result.registers.r7 == oob()
      assert result.memory == m
    end

    test "handles memory write failure", %{m: m, c: c, s: s, g: g, key: key} do
      {:ok, m} = Memory.write(m, 0, key)
      m = Memory.set_access(m, 100, 32, :read)
      r = %Registers{r7: 0, r8: 0, r9: byte_size(key), r10: 100, r11: 32}
      result = General.read(g, r, m, c, 0, s)
      assert result.registers.r7 == oob()
      assert result.memory == m
    end
  end

  describe "write/5" do
    setup do
      m = %Memory{} |> Memory.set_default_access(:write)
      value = "value" |> String.pad_trailing(32, "\0")
      key = "key" |> String.pad_trailing(32, "\0")
      storage_key = Hash.default(e_le(0, 4) <> key)
      c = %ServiceAccount{storage: %{storage_key => value}, balance: 2000}
      g = 100
      {:ok, m: m, c: c, g: g, key: key, value: value, storage_key: storage_key}
    end

    test "returns oob when key memory read fails", %{m: m, c: c, g: g} do
      m = Memory.set_access(m, 0, 32, nil)
      r = %Registers{r7: 0, r8: 0, r9: 32, r10: m.page_size + 100, r11: m.page_size + 132}

      result = General.write(g, r, m, c, 0)
      assert result.registers.r7 == oob()
      assert result.memory == m
      assert result.context == c
    end

    test "returns oob when value memory read fails", %{m: m, c: c, g: g, key: key} do
      {:ok, m} = Memory.write(m, 0, key)
      m = Memory.set_access(m, m.page_size + 100, m.page_size + 132, nil)
      r = %Registers{r7: 0, r8: 0, r9: 32, r10: m.page_size + 100, r11: m.page_size + 132}

      result = General.write(g, r, m, c, 0)
      assert result.registers.r7 == oob()
      assert result.memory == m
      assert result.context == c
    end

    test "successfully updates storage with new value", %{
      m: m,
      g: g,
      c: c,
      key: key,
      storage_key: storage_key
    } do
      new_value = "new_value" |> String.pad_trailing(32, "\0")
      {:ok, m} = Memory.write(m, 0, key)
      {:ok, m} = Memory.write(m, 100, new_value)
      r = %Registers{r7: 0, r8: 0, r9: byte_size(key), r10: 100, r11: byte_size(new_value)}

      service_account = %{c | storage: %{storage_key => "b"}}

      result = General.write(g, r, m, service_account, 0)

      assert result.registers.r7 == byte_size("b")
      assert result.memory == m
      assert get_in(result.context, [:storage, storage_key]) == new_value
    end

    test "successfully removes key when value offset is 0", %{
      m: m,
      c: c,
      g: g,
      key: key
    } do
      {:ok, m} = Memory.write(m, 0, key)
      r = %Registers{r7: 0, r8: 0, r9: byte_size(key), r10: 0, r11: 0}

      result = General.write(g, r, m, c, 0)
      storage_key = Hash.default(e_le(0, 4) <> key)
      # returns old value size
      assert result.registers.r7 == byte_size(get_in(c.storage, [storage_key]))
      assert result.memory == m
      assert get_in(result.context, [:storage, storage_key]) == nil
    end

    test "returns full when threshold exceeded", %{m: m, c: c, g: g, key: key} do
      new_value = "new_value" |> String.pad_trailing(32, "\0")
      {:ok, m} = Memory.write(m, 0, key)
      {:ok, m} = Memory.write(m, 100, new_value)
      r = %Registers{r7: 0, r8: 0, r9: byte_size(key), r10: 100, r11: byte_size(new_value)}

      service_account = %{c | balance: 50}

      result = General.write(g, r, m, service_account, 0)

      assert result.registers.r7 == full()
      assert result.memory == m
      assert result.context == service_account
    end

    test "returns full even when memory read fails", %{m: m, c: c, g: g} do
      # Make memory read fail
      m = Memory.set_access(m, 0, 32, nil)
      # Ensure threshold exceeds balance
      service_account = %{c | balance: 50}
      r = %Registers{r7: 0, r8: 0, r9: 32, r10: 100, r11: 32}

      result = General.write(g, r, m, service_account, 0)
      assert result.registers.r7 == full()
      assert result.memory == m
      assert result.context == service_account
    end

    test "returns none for non-existent key", %{m: m, c: c, g: g} do
      new_key = "new_key" |> String.pad_trailing(32, "\0")
      {:ok, m} = Memory.write(m, 0, new_key)
      {:ok, m} = Memory.write(m, 100, "value")
      r = %Registers{r7: 0, r8: 0, r9: byte_size(new_key), r10: 100, r11: 32}

      result = General.write(g, r, m, c, 0)
      assert result.registers.r7 == none()
      assert result.memory == m
      assert Map.has_key?(result.context.storage, Hash.default(e_le(0, 4) <> new_key))
    end

    test "returns full with invalid key but exceeded threshold", %{m: m, c: c, g: g} do
      # Make key read fail
      m = Memory.set_access(m, 0, 32, nil)
      # Ensure threshold exceeds balance
      service_account = %{c | balance: 50}
      r = %Registers{r7: 0, r8: 0, r9: 32, r10: 100, r11: 32}

      result = General.write(g, r, m, service_account, 0)
      assert result.registers.r7 == full()
      assert result.memory == m
      assert result.context == service_account
    end
  end

  describe "info/6" do
    setup do
      m = %Memory{} |> Memory.set_default_access(:write)

      service_account = %ServiceAccount{
        code_hash: "code_hash",
        balance: 1000,
        gas_limit_g: 100,
        gas_limit_m: 200
      }

      services = %{
        1 => service_account
      }

      g = 100
      context = %ServiceAccount{}

      {:ok, m: m, service_account: service_account, services: services, g: g, context: context}
    end

    test "returns none when service doesn't exist", %{
      m: m,
      services: services,
      g: g,
      context: context
    } do
      r = %Registers{r7: 999, r8: 0}

      result = General.info(g, r, m, context, 0, services)
      assert result.registers.r7 == none()
      assert result.memory == m
      assert result.context == context
    end

    test "returns oob when memory write fails", %{
      m: m,
      services: services,
      g: g,
      context: context
    } do
      r = %Registers{r7: 1, r8: 0}
      # Make memory write fail
      m = Memory.set_access(m, 0, 32, :read)

      result = General.info(g, r, m, context, 0, services)
      assert result.registers.r7 == oob()
      assert result.memory == m
      assert result.context == context
    end

    test "successfully writes service info using service index", %{
      m: m,
      services: services,
      g: g,
      context: context
    } do
      r = %Registers{r7: 1, r8: 0}

      result = General.info(g, r, m, context, 0, services)
      assert result.registers.r7 == ok()
      # Memory should be updated
      assert result.memory != m
      assert result.context == context
    end

    test "successfully writes service info using max 64-bit value", %{
      m: m,
      services: services,
      g: g,
      context: context
    } do
      max_64_bit = 0xFFFF_FFFF_FFFF_FFFF
      r = %Registers{r7: max_64_bit, r8: 0}
      {:ok, m} = Memory.write(m, 0, "value")
      result = General.info(g, r, m, context, 1, services)
      assert result.registers.r7 == ok()
      # Memory should be updated
      assert result.memory != m
      assert result.context == context
    end
  end
end
