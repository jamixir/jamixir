defmodule PVM.Accumulate.Utils do
  alias System.DeferredTransfer
  alias System.State.Accumulation
  alias PVM.Host
  alias PVM.Host.Accumulate.Context
  alias Util.Hash
  use Codec.{Encoder, Decoder}

  @hash_size 32

  # Formula (B.9) v0.6.1
  # first part of the initializer function is expected to be called in the context that calls
  # the accumulate inocation, this is where n0_, and header_timeslot are known
  # the second part is called internally in accumulate.execute
  # n0_ and timeslot are needed to calculate i (computed_service_index)
  @spec initializer(Types.hash(), non_neg_integer()) ::
          (Accumulation.t(), non_neg_integer() -> Context.t())
  def initializer(n0_, header_timeslot) do
    fn accumulation_state, service_index ->
      computed_service_index =
        e({service_index, n0_, header_timeslot})
        |> Hash.default()
        |> de_le(4)
        |> rem(0xFFFFFE00)
        |> Kernel.+(0x100)
        |> check(accumulation_state)

      %Context{
        service: service_index,
        accumulation: accumulation_state,
        computed_service: computed_service_index,
        transfers: [],
        accumulation_trie_result: nil
      }
    end
  end

  @dialyzer {:no_return, check: 2}

  # Formula (B.13) v0.6.1
  @spec check(non_neg_integer(), Accumulation.t()) :: non_neg_integer()
  def check(i, %Accumulation{services: services} = accumulation) do
    if i not in Map.keys(services) do
      i
    else
      # check((i - 2^8 + 1) mod (2^32 - 2^9) + 2^8)
      new_i = rem(i - 0x100 + 1, 0xFFFFFE00) + 0x100
      check(new_i, accumulation)
    end
  end

  # Formula (B.20) v0.6.0 / new = 9 host function

  # bump(i) = 2^8 + (i - 2^8 + 42) mod (2^32 - 2^9)
  @spec bump(non_neg_integer()) :: non_neg_integer()
  def bump(i) do
    256 + rem(i - 256 + 42, 0xFFFFFE00)
  end

  # Formula (B.12) v0.6.1
  def collapse({gas, output, {_x, y}}) when output in [:panic, :out_of_gas],
    do: {y.accumulation, y.transfers, y.accumulation_trie_result, gas}

  @spec collapse({non_neg_integer(), binary() | :panic | :out_of_gas, {Context.t(), Context.t()}}) ::
          {Accumulation.t(), list(DeferredTransfer.t()), Types.hash() | nil, non_neg_integer()}
  def collapse({gas, output, {x, _y}}) when is_binary(output) and byte_size(output) == @hash_size,
    do: {x.accumulation, x.transfers, output, gas}

  def collapse({gas, _output, {x, _y}}),
    do: {x.accumulation, x.transfers, x.accumulation_trie_result, gas}

  # Formula (B.11) v0.6.0
  @spec replace_service(
          Host.General.Result.t(),
          {Context.t(), Context.t()}
        ) :: Host.Accumulate.Result.t()
  def replace_service(%Host.General.Result{context: service_account} = general_result, {x, y}) do
    new_x = put_in(x, [:accumulation, :services, x.service], service_account)
    %{struct(Host.Accumulate.Result, Map.from_struct(general_result)) | context: {new_x, y}}
  end
end
