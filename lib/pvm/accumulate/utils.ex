defmodule PVM.Accumulate.Utils do
  alias System.State.ServiceAccount
  alias System.DeferredTransfer
  alias System.State.Accumulation
  alias PVM.Accumulate.Context
  alias Util.Hash
  use Codec.{Encoder, Decoder}

  @hash_size 32

  # Formula (B.9) v0.5.2
  @spec initializer(Accumulation.t(), non_neg_integer(), Types.hash(), non_neg_integer()) ::
          Context.t()
  def initializer(accumulation_state, service_index, n0_, header_timeslot) do
    {service_state, remaining_services} = Map.pop(accumulation_state.services, service_index)

    new_accumulation = %{accumulation_state | services: %{service_index => service_state}}

    computed_service_index =
      e({service_index, n0_, header_timeslot})
      |> Hash.default()
      |> de_le(4)
      |> rem(0xFFFFFE00)
      |> Kernel.+(0x100)
      |> check(Map.keys(service_state.services))

    %Context{
      services: remaining_services,
      service: service_index,
      accumulation: new_accumulation,
      computed_service: computed_service_index,
      transfers: []
    }
  end

  @dialyzer {:no_return, check: 2}
  @spec check(non_neg_integer(), list(non_neg_integer())) :: non_neg_integer()
  def check(i, keys) do
    if i not in keys do
      i
    else
      # check((i - 2^8 + 1) mod (2^32 - 2^9) + 2^8)
      new_i = rem(i - 0x100 + 1, 0xFFFFFE00) + 0x100
      check(new_i, keys)
    end
  end

  # Formula (B.12) v0.5.2
  @spec collapse({non_neg_integer(), binary() | :panic | :out_of_gas, {Context.t(), Context.t()}}) ::
          {Accumulation.t(), list(DeferredTransfer.t()), Types.hash() | nil, non_neg_integer()}
  def collapse({gas, output, {x, _y}}) when is_binary(output) and byte_size(output) == @hash_size,
    do: {x.accumulation, x.transfers, output, gas}

  def collapse({gas, output, {x, _y}}) when is_binary(output),
    do: {x.accumulation, x.transfers, nil, gas}

  def collapse({gas, output, {_x, y}}) when output in [:panic, :out_of_gas],
    do: {y.accumulation, y.transfers, nil, gas}

  @spec replace_service(
          {PVM.Types.exit_reason(), PVM.Types.host_call_state(), ServiceAccount.t()},
          {Context.t(), Context.t()}
        ) :: {PVM.Types.exit_reason(), PVM.Types.host_call_state(), ServiceAccount.t()}
  def replace_service({exit_reason, state, service_account}, {x, y}) do
    new_x = put_in(x, [:accumulation, :services, x.service], service_account)
    {exit_reason, state, {new_x, y}}
  end
end
