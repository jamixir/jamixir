defmodule PVM.Accumulate.Utils do
  alias System.DeferredTransfer
  alias System.State.Accumulation
  alias PVM.Host
  alias PVM.Host.Accumulate.Context
  alias Util.Hash
  import Codec.{Encoder, Decoder}

  @hash_size 32

  # Formula (B.10) v0.6.6
  @spec initializer(Types.hash(), non_neg_integer(), Accumulation.t(), non_neg_integer()) ::
          Context.t()
  def initializer(n0_, header_timeslot, accumulation_state, service_index) do
    computed_service_index =
      e(service_index) <> n0_ <> e(header_timeslot)
      |> Hash.default()
      |> de_le(4)
      |> rem(0xFFFFFE00)
      |> Kernel.+(256)
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

  # Formula (B.14) v0.6.6
  @spec check(non_neg_integer(), Accumulation.t()) :: non_neg_integer()
  def check(i, %Accumulation{services: services} = accumulation) do
    if i in Map.keys(services) do
      # check((i - 2^8 + 1) mod (2^32 - 2^9) + 2^8)
      new_i = rem(i - 0x100 + 1, 0xFFFFFE00) + 0x100
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

  # Formula (B.13) v0.6.6
  @spec collapse({Types.gas(), binary() | :panic | :out_of_gas, {Context.t(), Context.t()}}) ::
          {Accumulation.t(), list(DeferredTransfer.t()), Types.hash() | nil, Types.gas(),
           list({Types.service_index(), binary()})}
  def collapse({gas, output, {x, y}}) when output in [:panic, :out_of_gas] do
    require Logger

    # Compare the service states to see if there were any updates
    x_service = Map.get(x.accumulation.services, x.service)
    y_service = Map.get(y.accumulation.services, y.service)

    service_changed = x_service != y_service

    if service_changed do
      Logger.warning("COLLAPSE_DEBUG: #{output} occurred but service #{x.service} was modified during execution - SERVICE CHANGES WILL BE LOST!")
      Logger.warning("COLLAPSE_DEBUG: Original service storage items: #{if y_service, do: y_service.storage.items_in_storage, else: "nil"}")
      Logger.warning("COLLAPSE_DEBUG: Updated service storage items: #{if x_service, do: x_service.storage.items_in_storage, else: "nil"}")
    else
      Logger.debug("COLLAPSE_DEBUG: #{output} occurred, no service changes detected")
    end

    {y.accumulation, y.transfers, y.accumulation_trie_result, gas, MapSet.to_list(y.preimages)}
  end

  def collapse({gas, output, {x, _y}}) when is_binary(output) and byte_size(output) == @hash_size do
    require Logger
    Logger.debug("COLLAPSE_DEBUG: Success with hash output, returning updated accumulation with service #{x.service}")
    {x.accumulation, x.transfers, output, gas, MapSet.to_list(x.preimages)}
  end

  def collapse({gas, _output, {x, _y}}) do
    require Logger
    Logger.debug("COLLAPSE_DEBUG: Success with other output, returning updated accumulation with service #{x.service}")
    {x.accumulation, x.transfers, x.accumulation_trie_result, gas, MapSet.to_list(x.preimages)}
  end

  # Formula (B.12) v0.6.6
  @spec replace_service(
          Host.General.Result.t(),
          {Context.t(), Context.t()}
        ) :: Host.Accumulate.Result.t()
  def replace_service(%Host.General.Result{context: service_account} = general_result, {x, y}) do
    require Logger

    old_service = Map.get(x.accumulation.services, x.service)
    service_changed = old_service != service_account

    if service_changed do
      Logger.debug("REPLACE_SERVICE_DEBUG: Service #{x.service} updated, exit_reason=#{general_result.exit_reason}")
      if old_service && service_account do
        old_storage_size = old_service.storage.items_in_storage
        new_storage_size = service_account.storage.items_in_storage
        if old_storage_size != new_storage_size do
          Logger.debug("REPLACE_SERVICE_DEBUG: Storage size changed from #{old_storage_size} to #{new_storage_size}")
        end
      end
    end

    new_x = put_in(x, [:accumulation, :services, x.service], service_account)
    %{struct(Host.Accumulate.Result, Map.from_struct(general_result)) | context: {new_x, y}}
  end
end
