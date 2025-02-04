# Formula (B.20) v0.6.0

defmodule PVM.Host.Accumulate.Internal do
  alias System.DeferredTransfer
  alias System.State.PrivilegedServices
  alias System.State.ServiceAccount
  alias PVM.Host.Accumulate.{Context, Result}
  alias PVM.{Memory, Registers}
  import PVM.{Constants.HostCallResult}
  use Codec.{Encoder, Decoder}
  import PVM.Accumulate.Utils, only: [check: 2, bump: 1]

  @spec bless_internal(Registers.t(), Memory.t(), {Context.t(), Context.t()}) ::
          Result.Internal.t()
  def bless_internal(registers, memory, {x, _y} = context_pair) do
    [m, a, v, o, n] = Registers.get(registers, [8, 9, 10, 11, 12])

    g =
      case Memory.read(memory, o, 12 * n) do
        {:ok, data} ->
          for <<service::binary-size(4), value::binary-size(8) <- data>>, into: %{} do
            {de_le(service, 4), de_le(value, 8)}
          end

        _ ->
          :error
      end

    {registers_, context_} =
      cond do
        g == :error ->
          {Registers.set(registers, :r7, oob()), context_pair}

        Enum.any?([m, a, v], &(&1 < 0 or &1 > 0x100000000)) ->
          {Registers.set(registers, :r7, who()), context_pair}

        true ->
          privileged_service = %PrivilegedServices{
            manager_service: m,
            alter_authorizer_service: a,
            alter_validator_service: v,
            services_gas: g
          }

          x_ = put_in(x, [:accumulation, :privileged_services], privileged_service)
          {Registers.set(registers, :r7, ok()), put_elem(context_pair, 0, x_)}
      end

    %Result.Internal{
      registers: registers_,
      memory: memory,
      context: context_
    }
  end

  @spec assign_internal(Registers.t(), Memory.t(), {Context.t(), Context.t()}) ::
          Result.Internal.t()
  def assign_internal(registers, memory, {x, _y} = context_pair) do
    q = Constants.max_authorization_queue_items()

    c =
      case Memory.read(memory, registers.r8, 32 * q) do
        {:ok, data} ->
          for <<chunk::binary-size(32) <- data>>, do: chunk

        _ ->
          :error
      end

    {registers_, context_} =
      cond do
        c == :error ->
          {Registers.set(registers, :r7, oob()), context_pair}

        registers.r7 >= Constants.core_count() ->
          {Registers.set(registers, :r7, core()), context_pair}

        true ->
          queue_ =
            x.accumulation.authorizer_queue |> List.insert_at(registers.r7, c)

          x_ = put_in(x.accumulation.authorizer_queue, queue_)
          {Registers.set(registers, :r7, ok()), put_elem(context_pair, 0, x_)}
      end

    %Result.Internal{
      registers: registers_,
      memory: memory,
      context: context_
    }
  end

  @spec designate_internal(Registers.t(), Memory.t(), {Context.t(), Context.t()}) ::
          Result.Internal.t()
  def designate_internal(registers, memory, {x, _y} = context_pair) do
    v = Constants.validator_count()

    i =
      case Memory.read(memory, registers.r7, 336 * v) do
        {:ok, data} ->
          for <<validator_data::binary-size(336) <- data>> do
            <<bandersnatch::binary-size(32), ed25519::binary-size(32), bls::binary-size(144),
              metadata::binary-size(128)>> = validator_data

            %System.State.Validator{
              bandersnatch: bandersnatch,
              ed25519: ed25519,
              bls: bls,
              metadata: metadata
            }
          end

        _ ->
          :error
      end

    {registers_, context_} =
      cond do
        i == :error ->
          {Registers.set(registers, :r7, oob()), context_pair}

        true ->
          x_ = put_in(x, [:accumulation, :next_validators], i)
          {Registers.set(registers, :r7, ok()), put_elem(context_pair, 0, x_)}
      end

    %Result.Internal{
      registers: registers_,
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

  @spec new_internal(Registers.t(), Memory.t(), {Context.t(), Context.t()}) ::
          Result.Internal.t()
  def new_internal(registers, memory, {x, _y} = context_pair) do
    [o, l, g, m] = Registers.get(registers, [7, 8, 9, 10])

    c =
      case Memory.read(memory, o, 32) do
        {:ok, data} -> data
        _ -> :error
      end

    a =
      if c == :error do
        :error
      else
        a = %ServiceAccount{
          preimage_storage_l: %{{c, l} => []},
          code_hash: c,
          gas_limit_g: g,
          gas_limit_m: m
        }

        %{a | balance: ServiceAccount.threshold_balance(a)}
      end

    x_s = Context.accumulating_service(x)
    a_t = if a == :error, do: 0, else: ServiceAccount.threshold_balance(a)

    s = Map.put(x_s, :balance, Map.get(x_s, :balance) - a_t)

    {w7_, computed_service, accumulation_services_} =
      (
        x_i = x.computed_service
        xu_d = x.accumulation.services

        cond do
          c == :error ->
            {oob(), x_i, xu_d}

          a != :error and s.balance >= ServiceAccount.threshold_balance(x_s) ->
            {x_i, check(bump(x_i), x.accumulation), Map.merge(xu_d, %{x_i => a, x.service => s})}

          true ->
            {cash(), x_i, xu_d}
        end
      )

    registers_ = Registers.set(registers, 7, w7_)

    x_ =
      Map.merge(x, %{
        computed_service: computed_service,
        accumulation: Map.merge(x.accumulation, %{services: accumulation_services_})
      })

    context_ = put_elem(context_pair, 0, x_)

    %Result.Internal{
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

    {registers_, context_} =
      cond do
        c == :error ->
          {Registers.set(registers, :r7, oob()), context_pair}

        true ->
          xs_ =
            %{Context.accumulating_service(x) | code_hash: c, gas_limit_g: g, gas_limit_m: m}

          x_ = put_in(x, [:accumulation, :services, x.service], xs_)
          {Registers.set(registers, :r7, ok()), put_elem(context_pair, 0, x_)}
      end

    %Result.Internal{
      registers: registers_,
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
    # let [d,a,l,o] = ω7..11
    [d, a, l, o] = Registers.get(registers, [7, 8, 9, 10])

    # let d = xd ∪ (xu)d
    all_services = Map.merge(x.services, x.accumulation.services)

    # Read transfer data for memo
    # otherwise if No...+WT ∈ Vμ
    t =
      case Memory.read(memory, o, Constants.memo_size()) do
        {:ok, memo} ->
          %DeferredTransfer{
            sender: x.service,
            receiver: d,
            amount: a,
            memo: memo,
            gas_limit: l
          }

        _ ->
          :error
      end

    # let b = (xs)b - a
    xs = Context.accumulating_service(x)
    b = Map.get(xs, :balance) - a

    {registers_, context_} =
      cond do
        # if t = ∇
        t == :error ->
          {Registers.set(registers, :r7, oob()), context_pair}

        # otherwise if d ∉ K(d)
        all_services[d] == nil ->
          {Registers.set(registers, :r7, who()), context_pair}

        # otherwise if g < d[d]m
        l < all_services[d][:gas_limit_m] ->
          {Registers.set(registers, :r7, low()), context_pair}

        # otherwise if b < (xs)t
        b < ServiceAccount.threshold_balance(xs) ->
          {Registers.set(registers, :r7, cash()), context_pair}

        # otherwise (OK case)
        true ->
          x_ =
            Context.update_accumulating_service(x, [:balance], b)
            |> update_in([:transfers], &(&1 ++ [t]))

          {Registers.set(registers, :r7, ok()), put_elem(context_pair, 0, x_)}
      end

    %Result.Internal{
      registers: registers_,
      memory: memory,
      context: context_
    }
  end

  @spec quit_internal(Registers.t(), Memory.t(), {Context.t(), Context.t()}, non_neg_integer()) ::
          {:halt | :continue, Result.Internal.t()}
  def quit_internal(registers, memory, {x, _y} = context_pair, gas) do
    # let [d,o] = ω7..8
    [d, o] = Registers.get(registers, [7, 8])

    # let a = (xs)b - (xs)t + BS
    xs = Context.accumulating_service(x)
    a = xs.balance - ServiceAccount.threshold_balance(xs) + Constants.service_minimum_balance()

    # let d = xd ∪ (xu)d
    all_services = Map.merge(x.services, x.accumulation.services)

    # Read transfer data for memo
    t =
      if d in [x.service, 0xFFFFFFFFFFFFFFFF] do
        # if d ∈ {xs, 2^64 - 1}
        nil
      else
        # otherwise if No...+WT ∈ Vμ
        case Memory.read(memory, o, Constants.memo_size()) do
          {:ok, memo} ->
            %DeferredTransfer{
              sender: x.service,
              receiver: d,
              amount: a,
              memo: memo,
              gas_limit: gas
            }

          _ ->
            :error
        end
      end

    {exit_reason, registers_, x_} =
      (
        x_u_d = x.accumulation.services

        x_s = x.service

        cond do
          # if t = ∅
          t == nil ->
            {:halt, Registers.set(registers, :r7, ok()),
             put_in(x, [:accumulation, :services], Map.delete(x_u_d, x_s))}

          # otherwise if t = ∇
          t == :error ->
            {:continue, Registers.set(registers, :r7, oob()), x}

          # otherwise if d ∉ K(d)
          not Map.has_key?(all_services, d) ->
            {:continue, Registers.set(registers, :r7, who()), x}

          # otherwise if g < d[d]m
          gas < get_in(all_services, [d, :gas_limit_m]) ->
            {:continue, Registers.set(registers, :r7, low()), x}

          # otherwise (OK case)
          true ->
            x_ =
              update_in(x, [:transfers], &(&1 ++ [t]))
              |> put_in([:accumulation, :services], Map.delete(x_u_d, x_s))

            {:halt, Registers.set(registers, :r7, ok()), x_}
        end
      )

    {exit_reason,
     %Result.Internal{
       registers: registers_,
       memory: memory,
       context: put_elem(context_pair, 0, x_)
     }}
  end

  @spec solicit_internal(Registers.t(), Memory.t(), {Context.t(), Context.t()}, non_neg_integer()) ::
          Result.Internal.t()
  def solicit_internal(registers, memory, {x, _y} = context_pair, timeslot) do
    # let [o,z] = ω7,8
    [o, z] = Registers.get(registers, [7, 8])

    # let h = μo...+32 if Zo...+32 ⊂ Vμ
    h =
      case Memory.read(memory, o, 32) do
        {:ok, hash} -> hash
        _ -> :error
      end

    xs = Context.accumulating_service(x)
    at_h_z = get_in(xs, [:preimage_storage_l, {h, z}])

    a =
      cond do
        h == :error ->
          :error

        # if h ≠ ∇ ∧ (h,z) ∉ (xs)l
        at_h_z == nil ->
          put_in(xs, [:preimage_storage_l, {h, z}], [])

        # if (xs)l[(h,z)] = [x,y]
        length(at_h_z) == 2 ->
          update_in(xs, [:preimage_storage_l, {h, z}], &(&1 ++ [timeslot]))

        true ->
          :error
      end

    {registers_, x_} =
      cond do
        # if h = ∇
        h == :error ->
          {Registers.set(registers, :r7, oob()), x}

        # otherwise if a = ∇
        a == :error ->
          {Registers.set(registers, :r7, huh()), x}

        # otherwise if ab < at
        a.balance < ServiceAccount.threshold_balance(a) ->
          {Registers.set(registers, :r7, full()), x}

        # otherwise
        true ->
          {Registers.set(registers, :r7, ok()),
           put_in(x, [:accumulation, :services, x.service], a)}
      end

    %Result.Internal{
      registers: registers_,
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
    at_h_z = get_in(xs, [:preimage_storage_l, {h, z}])
    d = Constants.forget_delay()

    a =
      case at_h_z do
        # if (xs)l[h,z] ∈ {[], [x,y]}, y < t-D
        [] ->
          %{
            xs
            | preimage_storage_l: Map.delete(xs.preimage_storage_l, {h, z}),
              preimage_storage_p: Map.delete(xs.preimage_storage_p, h)
          }

        [_, y] when y < timeslot - d ->
          %{
            xs
            | preimage_storage_l: Map.delete(xs.preimage_storage_l, {h, z}),
              preimage_storage_p: Map.delete(xs.preimage_storage_p, h)
          }

        # if |(xs)l[h,z]| = 1
        [x] ->
          put_in(xs, [:preimage_storage_l, {h, z}], [x, timeslot])

        # if (xs)l[h,z] = [x,y,w], y < t-D
        [_x, y, w] when y < timeslot - d ->
          put_in(xs, [:preimage_storage_l, {h, z}], [w, timeslot])

        _ ->
          :error
      end

    {registers_, x_} =
      cond do
        h == :error ->
          {Registers.set(registers, :r7, oob()), x}

        a == :error ->
          {Registers.set(registers, :r7, huh()), x}

        true ->
          {Registers.set(registers, :r7, ok()),
           put_in(x, [:accumulation, :services, x.service], a)}
      end

    %Result.Internal{
      registers: registers_,
      memory: memory,
      context: put_elem(context_pair, 0, x_)
    }
  end
end
