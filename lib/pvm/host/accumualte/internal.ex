# Formula (B.22) v0.6.7

defmodule PVM.Host.Accumulate.Internal do
  alias System.State.Validator
  alias System.DeferredTransfer
  alias System.State.ServiceAccount
  alias PVM.Host.Accumulate.{Context, Result}
  alias PVM.{Memory, Registers}
  import PVM.{Constants.HostCallResult}
  import Codec.Encoder
  import PVM.Accumulate.Utils, only: [check: 2, bump: 1]

  @max_64_bit_value 0xFFFF_FFFF_FFFF_FFFF

  @spec bless_internal(Registers.t(), Memory.t(), {Context.t(), Context.t()}) ::
          Result.Internal.t()
  def bless_internal(registers, memory, {x, _y} = context_pair) do
    [m, a, v, o, n] = Registers.get(registers, [7, 8, 9, 10, 11])

    assigners_ =
      case Memory.read(memory, a, 4 * Constants.core_count()) do
        {:ok, data} ->
          for <<service::service() <- data>>, into: [], do: service

        _ ->
          :error
      end

    z =
      if n == 0,
        do: %{},
        else:
          (case Memory.read(memory, o, 12 * n) do
             {:ok, data} ->
               for <<service::service(), value::64-little <- data>>,
                 into: %{},
                 do: {service, value}

             _ ->
               :error
           end)

    {exit_reason_, w7_, context_} =
      cond do
        :error in [z, assigners_] ->
          {:panic, registers.r7, context_pair}

        x.service != x.accumulation.manager ->
          {:continue, huh(), context_pair}

        Enum.any?([m, v], &(not ServiceAccount.service_id?(&1))) ->
          {:continue, who(), context_pair}

        true ->
          x_ = %{
            x
            | accumulation: %{
                x.accumulation
                | manager: m,
                  assigners: assigners_,
                  delegator: v,
                  always_accumulated: z
              }
          }

          context_ = put_elem(context_pair, 0, x_)
          {:continue, ok(), context_}
      end

    %Result.Internal{
      exit_reason: exit_reason_,
      registers: Registers.set(registers, :r7, w7_),
      memory: memory,
      context: context_
    }
  end

  @spec assign_internal(Registers.t(), Memory.t(), {Context.t(), Context.t()}) ::
          Result.Internal.t()
  def assign_internal(registers, memory, {x, _y} = context_pair) do
    [c, o, a] = Registers.get(registers, [7, 8, 9])

    q =
      case Memory.read(memory, o, 32 * Constants.max_authorization_queue_items()) do
        {:ok, data} ->
          for <<hash::binary-size(32) <- data>>, do: hash

        _ ->
          :error
      end

    w7 = registers.r7

    {exit_reason, w7_, context_} =
      cond do
        q == :error ->
          {:panic, w7, context_pair}

        c >= Constants.core_count() ->
          {:continue, core(), context_pair}

        x.service != x.accumulation.assigners |> Enum.at(c) ->
          {:continue, huh(), context_pair}

        true ->
          queue_ =
            x.accumulation.authorizer_queue |> List.replace_at(c, q)

          assigners_ = x.accumulation.assigners |> List.replace_at(c, a)

          x_ =
            put_in(x.accumulation.authorizer_queue, queue_)

          x_ = put_in(x_.accumulation.assigners, assigners_)

          context_ = put_elem(context_pair, 0, x_)
          {:continue, ok(), context_}
      end

    %Result.Internal{
      exit_reason: exit_reason,
      registers: Registers.set(registers, :r7, w7_),
      memory: memory,
      context: context_
    }
  end

  @spec designate_internal(Registers.t(), Memory.t(), {Context.t(), Context.t()}) ::
          Result.Internal.t()
  def designate_internal(registers, memory, {x, _y} = context_pair) do
    v =
      case Memory.read(memory, registers.r7, 336 * Constants.validator_count()) do
        {:ok, data} ->
          for <<validator_data::binary-size(336) <- data>> do
            {v, _} = Validator.decode(validator_data)
            v
          end

        _ ->
          :error
      end

    {exit_reason, w7_, context_} =
      cond do
        v == :error ->
          {:panic, registers.r7, context_pair}

        x.service != x.accumulation.delegator ->
          {:continue, huh(), context_pair}

        true ->
          x_ = put_in(x, [:accumulation, :next_validators], v)
          context_ = put_elem(context_pair, 0, x_)
          {:continue, ok(), context_}
      end

    %Result.Internal{
      exit_reason: exit_reason,
      registers: Registers.set(registers, :r7, w7_),
      memory: memory,
      context: context_
    }
  end

  @spec checkpoint_internal(
          Registers.t(),
          Memory.t(),
          {Context.t(), Context.t()},
          non_neg_integer()
        ) ::
          Result.Internal.t()
  def checkpoint_internal(registers, memory, {x, _y}, gas) do
    {_exit_reason, remaining_gas} = PVM.Host.Gas.check_gas(gas)

    %Result.Internal{
      registers: Registers.set(registers, :r7, remaining_gas),
      memory: memory,
      context: {x, x}
    }
  end

  @spec new_internal(Registers.t(), Memory.t(), {Context.t(), Context.t()}, non_neg_integer()) ::
          Result.Internal.t()
  def new_internal(registers, memory, {x, _y} = context_pair, timeslot) do
    [o, l, g, m, f] = Registers.get(registers, [7, 8, 9, 10, 11])

    c =
      case Memory.read(memory, o, 32) do
        {:ok, data} ->
          if ServiceAccount.service_id?(l), do: data, else: :error

        _ ->
          :error
      end

    a =
      if c == :error do
        :error
      else
        a = %ServiceAccount{
          storage: HashedKeysMap.new(%{{c, l} => []}),
          code_hash: c,
          gas_limit_g: g,
          gas_limit_m: m,
          creation_slot: timeslot,
          deposit_offset: f,
          last_accumulation_slot: 0,
          parent_service: x.service
        }

        %{a | balance: ServiceAccount.threshold_balance(a)}
      end

    x_s = Context.accumulating_service(x)
    a_t = if a == :error, do: 0, else: ServiceAccount.threshold_balance(a)

    s = %{x_s | balance: x_s.balance - a_t}

    {exit_reason, w7_, computed_service_, accumulation_services_} =
      (
        x_i = x.computed_service
        xu_d = x.accumulation.services

        cond do
          c == :error ->
            {:panic, registers.r7, x_i, xu_d}

          f != 0 and x.service != x.accumulation.manager ->
            {:continue, huh(), x_i, xu_d}

          s.balance < ServiceAccount.threshold_balance(x_s) ->
            {:continue, cash(), x_i, xu_d}

          true ->
            {:continue, x_i, check(bump(x_i), x.accumulation),
             Map.merge(xu_d, %{x_i => a, x.service => s})}
        end
      )

    registers_ = Registers.set(registers, 7, w7_)

    x_ =
      %{
        x
        | computed_service: computed_service_,
          accumulation: %{x.accumulation | services: accumulation_services_}
      }

    context_ = put_elem(context_pair, 0, x_)

    %Result.Internal{
      exit_reason: exit_reason,
      registers: registers_,
      memory: memory,
      context: context_
    }
  end

  @spec upgrade_internal(Registers.t(), Memory.t(), {Context.t(), Context.t()}) ::
          Result.Internal.t()
  def upgrade_internal(registers, memory, {x, _y} = context_pair) do
    [o, g, m] = Registers.get(registers, [7, 8, 9])

    c =
      case Memory.read(memory, o, 32) do
        {:ok, data} -> data
        _ -> :error
      end

    {exit_reason, w7_, context_} =
      if c == :error do
        {:panic, registers.r7, context_pair}
      else
        xs_ =
          %{Context.accumulating_service(x) | code_hash: c, gas_limit_g: g, gas_limit_m: m}

        x_ = put_in(x, [:accumulation, :services, x.service], xs_)
        context_ = put_elem(context_pair, 0, x_)
        {:continue, ok(), context_}
      end

    %Result.Internal{
      exit_reason: exit_reason,
      registers: Registers.set(registers, :r7, w7_),
      memory: memory,
      context: context_
    }
  end

  @spec transfer_internal(
          Registers.t(),
          Memory.t(),
          {Context.t(), Context.t()}
        ) ::
          Result.Internal.t()
  def transfer_internal(registers, memory, {x, _y} = context_pair) do
    [d, a, l, o] = Registers.get(registers, [7, 8, 9, 10])

    services = x.accumulation.services

    t =
      case Memory.read(memory, o, Constants.memo_size()) do
        {:ok, memo} ->
          %DeferredTransfer{
            sender: x.service,
            receiver: d,
            amount: a,
            memo: memo,
            gas_limit: l,
          }

        _ ->
          :error
      end

    xs = Context.accumulating_service(x)
    b = Map.get(xs, :balance) - a

    {exit_reason, w7_, context_} =
      cond do
        t == :error ->
          {:panic, registers.r7, context_pair}

        # otherwise if d ∉ K(d)
        not Map.has_key?(services, d) ->
          {:continue, who(), context_pair}

        # otherwise if g < d[d]m
        l < get_in(services, [d, :gas_limit_m]) ->
          {:continue, low(), context_pair}

        # otherwise if b < (xs)t
        b < ServiceAccount.threshold_balance(xs) ->
          {:continue, cash(), context_pair}

        # otherwise (OK case)
        true ->
          x_ =
            Context.update_accumulating_service(x, [:balance], b)
            |> update_in([:transfers], &(&1 ++ [t]))

          context_ = put_elem(context_pair, 0, x_)
          {:continue, ok(), context_}
      end

    %Result.Internal{
      exit_reason: exit_reason,
      registers: Registers.set(registers, :r7, w7_),
      memory: memory,
      context: context_
    }
  end

  @spec eject_internal(Registers.t(), Memory.t(), {Context.t(), Context.t()}, non_neg_integer()) ::
          {:halt | :continue, Result.Internal.t()}
  def eject_internal(registers, memory, {x, _y} = context_pair, timeslot) do
    # let [d,o] = ω7..8
    [d, o] = Registers.get(registers, [7, 8])

    h =
      case Memory.read(memory, o, 32) do
        {:ok, hash} -> hash
        _ -> :error
      end

    service =
      case d != x.service do
        true -> Map.get(x.accumulation.services, d, :error)
        false -> :error
      end

    {exit_reason, w7_, x_} =
      cond do
        h == :error ->
          {:panic, registers.r7, x}

        service == :error or service.code_hash != t(x.service) ->
          {:continue, who(), x}

        true ->
          l =
            max(81, service.storage.octets_in_storage) - 81

          s_ = Context.accumulating_service(x)
          s_ = %{s_ | balance: s_.balance + service.balance}

          cond do
            service.storage.items_in_storage != 2 or
                !HashedKeysMap.has_key?(service.storage, {h, l}) ->
              {:continue, huh(), x}

            match?([_x, _y], get_in(service, [:storage, {h, l}])) and
                get_in(service, [:storage, {h, l}]) |> Enum.at(1) <
                  timeslot - Constants.forget_delay() ->
              x_u_d_ = Map.delete(x.accumulation.services, d) |> Map.merge(%{x.service => s_})
              x_ = put_in(x, [:accumulation, :services], x_u_d_)
              {:continue, ok(), x_}

            true ->
              {:continue, huh(), x}
          end
      end

    %Result.Internal{
      exit_reason: exit_reason,
      registers: Registers.set(registers, :r7, w7_),
      memory: memory,
      context: put_elem(context_pair, 0, x_)
    }
  end

  @spec query_internal(Registers.t(), Memory.t(), {Context.t(), Context.t()}) ::
          Result.Internal.t()
  def query_internal(registers, memory, {x, _y} = context_pair) do
    [o, z] = Registers.get(registers, [7, 8])

    h =
      case Memory.read(memory, o, 32) do
        {:ok, hash} -> hash
        _ -> :error
      end

    {exit_reason, w7_, w8_} =
      if h == :error do
        {:panic, registers.r7, registers.r8}
      else
        xs = Context.accumulating_service(x)
        a = get_in(xs, [:storage, {h, z}]) || :error

        two_32 = 0x1_0000_0000

        case a do
          :error -> {:continue, none(), 0}
          [] -> {:continue, 0, 0}
          [x] -> {:continue, 1 + two_32 * x, 0}
          [x, y] -> {:continue, 2 + two_32 * x, y}
          [x, y, z] -> {:continue, 3 + two_32 * x, y + two_32 * z}
        end
      end

    registers_ = Registers.set(registers, :r7, w7_) |> Registers.set(:r8, w8_)

    %Result.Internal{
      exit_reason: exit_reason,
      registers: registers_,
      memory: memory,
      context: context_pair
    }
  end

  @spec solicit_internal(Registers.t(), Memory.t(), {Context.t(), Context.t()}, non_neg_integer()) ::
          Result.Internal.t()
  def solicit_internal(registers, memory, {x, _y} = context_pair, timeslot) do
    [o, z] = Registers.get(registers, [7, 8])

    h =
      case Memory.read(memory, o, 32) do
        {:ok, hash} -> hash
        _ -> :error
      end

    xs = Context.accumulating_service(x)
    at_h_z = get_in(xs, [:storage, {h, z}])

    a =
      cond do
        h == :error ->
          :error

        # if h ≠ ∇ ∧ (h,z) ∉ (xs)l
        at_h_z == nil ->
          put_in(xs, [:storage, {h, z}], [])

        # if (xs)l[(h,z)] = [x,y]
        length(at_h_z) == 2 ->
          update_in(xs, [:storage, {h, z}], &(&1 ++ [timeslot]))

        true ->
          :error
      end

    {exit_reason, w7_, x_} =
      cond do
        # if h = ∇
        h == :error ->
          {:panic, registers.r7, x}

        # otherwise if a = ∇
        a == :error ->
          {:continue, huh(), x}

        # otherwise if ab < at
        a.balance < ServiceAccount.threshold_balance(a) ->
          {:continue, full(), x}

        # otherwise
        true ->
          {:continue, ok(), put_in(x, [:accumulation, :services, x.service], a)}
      end

    %Result.Internal{
      exit_reason: exit_reason,
      registers: Registers.set(registers, :r7, w7_),
      memory: memory,
      context: put_elem(context_pair, 0, x_)
    }
  end

  @spec forget_internal(Registers.t(), Memory.t(), {Context.t(), Context.t()}, non_neg_integer()) ::
          Result.Internal.t()
  def forget_internal(registers, memory, {x, _y} = context_pair, timeslot) do
    [o, z] = Registers.get(registers, [7, 8])

    h =
      case Memory.read(memory, o, 32) do
        {:ok, hash} -> hash
        _ -> :error
      end

    xs = Context.accumulating_service(x)
    at_h_z = get_in(xs, [:storage, {h, z}])
    d = Constants.forget_delay()

    a =
      case at_h_z do
        # if (xs)l[h,z] ∈ {[], [x,y]}, y < t-D
        [] ->
          %{
            xs
            | storage: pop_in(xs.storage, [{h, z}]) |> elem(1),
              preimage_storage_p: Map.delete(xs.preimage_storage_p, h)
          }

        [_, y] when y < timeslot - d ->
          %{
            xs
            | storage: pop_in(xs.storage, [{h, z}]) |> elem(1),
              preimage_storage_p: Map.delete(xs.preimage_storage_p, h)
          }

        [x] ->
          put_in(xs, [:storage, {h, z}], [x, timeslot])

        # if (xs)l[h,z] = [x,y,w], y < t-D
        [_x, y, w] when y < timeslot - d ->
          put_in(xs, [:storage, {h, z}], [w, timeslot])

        _ ->
          :error
      end

    {exit_reason, w7_, x_} =
      cond do
        h == :error ->
          {:panic, registers.r7, x}

        a == :error ->
          {:continue, huh(), x}

        true ->
          {:continue, ok(), put_in(x, [:accumulation, :services, x.service], a)}
      end

    %Result.Internal{
      exit_reason: exit_reason,
      registers: Registers.set(registers, :r7, w7_),
      memory: memory,
      context: put_elem(context_pair, 0, x_)
    }
  end

  @spec yield_internal(Registers.t(), Memory.t(), {Context.t(), Context.t()}) ::
          Result.Internal.t()
  def yield_internal(registers, memory, {x, _y} = context_pair) do
    o = registers.r7

    h =
      case Memory.read(memory, o, 32) do
        {:ok, hash} -> hash
        _ -> :error
      end

    {exit_reason, w7_, x_} =
      if h == :error do
        {:panic, registers.r7, x}
      else
        {:continue, ok(), %{x | accumulation_trie_result: h}}
      end

    %Result.Internal{
      exit_reason: exit_reason,
      registers: Registers.set(registers, :r7, w7_),
      memory: memory,
      context: put_elem(context_pair, 0, x_)
    }
  end

  @spec provide_internal(
          Registers.t(),
          Memory.t(),
          {Context.t(), Context.t()},
          Types.service_index()
        ) ::
          Result.Internal.t()
  def provide_internal(registers, memory, {x, _y} = context_pair, service_index) do
    [o, z] = Registers.get(registers, [8, 9])
    # d
    services = x.accumulation.services

    s_star = if registers.r7 == @max_64_bit_value, do: service_index, else: registers.r7

    i =
      case Memory.read(memory, o, z) do
        {:ok, data} -> data
        _ -> :error
      end

    # a
    service = Map.get(services, s_star, nil)

    {exit_reason, w7_, x_} =
      cond do
        i == :error ->
          {:panic, registers.r7, x}

        service == nil ->
          {:continue, who(), x}

        get_in(service, [:storage, {h(i), z}]) != nil ->
          {:continue, huh(), x}

        MapSet.member?(x.preimages, {s_star, i}) ->
          {:continue, huh(), x}

        true ->
          {:continue, ok(), put_in(x, [:preimages], MapSet.put(x.preimages, {s_star, i}))}
      end

    %Result.Internal{
      exit_reason: exit_reason,
      registers: Registers.set(registers, :r7, w7_),
      memory: memory,
      context: put_elem(context_pair, 0, x_)
    }
  end
end
