defmodule PVM.Accumulate.Utils do
  alias PVM.Host
  alias PVM.Host.Accumulate.Context
  alias System.AccumulationResult
  alias System.State.Accumulation
  alias Util.Hash
  import Codec.{Encoder, Decoder}

  @hash_size 32

  # Formula (B.10) v0.7.2
  @spec initializer(Types.hash(), non_neg_integer(), Accumulation.t(), non_neg_integer()) ::
          Context.t()
  def initializer(n0_, header_timeslot, accumulation_state, service_index) do
    computed_service_index =
      (e(service_index) <> n0_ <> e(header_timeslot))
      |> Hash.default()
      |> de_le(4)
      |> rem(0xFFFFFF00 - Constants.minimum_service_id())
      |> Kernel.+(Constants.minimum_service_id())
      |> check(accumulation_state)

    %Context{
      service: service_index,
      accumulation: accumulation_state,
      computed_service: computed_service_index,
      transfers: [],
      accumulation_trie_result: nil
    }
  end

  @dialyzer {:no_return, check: 2}

  # Formula (B.14) v0.7.2
  @spec check(non_neg_integer(), Accumulation.t()) :: non_neg_integer()
  def check(i, %Accumulation{services: services} = accumulation) do
    if Map.has_key?(services, i) do
      # check((i - S + 1) mod (2^32 - 2^8) + S)
      new_i =
        rem(i - Constants.minimum_service_id() + 1, 0xFFFFFF00) + Constants.minimum_service_id()

      check(new_i, accumulation)
    else
      i
    end
  end

  # inlined defintion in section B.8 (Accumulate function) => new = 9 host function
  # where i = 2^8 + (i - 2^8 + 42) mod (2^32 - 2^9)
  @spec bump(non_neg_integer()) :: non_neg_integer()
  def bump(i) do
    256 + rem(i - 256 + 42, 0xFFFFFE00)
  end

  # Formula (B.13) v0.7.2
  @spec collapse({Types.gas(), binary() | :panic | :out_of_gas, {Context.t(), Context.t()}}) ::
          AccumulationResult.t()

  def collapse({gas, output, {_x, y}}) when output in [:panic, :out_of_gas],
    do: %AccumulationResult{
      state: y.accumulation,
      transfers: y.transfers,
      output: y.accumulation_trie_result,
      gas_used: gas,
      preimages: y.preimages
    }

  def collapse({gas, output, {x, _y}}) when is_binary(output) and byte_size(output) == @hash_size,
    do: %AccumulationResult{
      state: x.accumulation,
      transfers: x.transfers,
      output: output,
      gas_used: gas,
      preimages: x.preimages
    }

  def collapse({gas, _output, {x, _y}}),
    do: %AccumulationResult{
      state: x.accumulation,
      transfers: x.transfers,
      output: x.accumulation_trie_result,
      gas_used: gas,
      preimages: x.preimages
    }

  # Formula (B.12) v0.7.2
  @spec replace_service(
          Host.General.Result.t(),
          {Context.t(), Context.t()}
        ) :: Host.Accumulate.Result.t()
  def replace_service(%Host.General.Result{context: service_account} = general_result, {x, y}) do
    new_x = put_in(x, [:accumulation, :services, x.service], service_account)
    %{struct(Host.Accumulate.Result, Map.from_struct(general_result)) | context: {new_x, y}}
  end
end
