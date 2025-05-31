defmodule System.State.PrivilegedServices do
  @moduledoc """
  Formula (9.9) v0.6.6
  """
  alias Codec.JsonEncoder
  import Codec.Encoder
  alias Codec.VariableSize
  use JsonDecoder

  @type t :: %__MODULE__{
          # m
          manager: non_neg_integer(),
          # a
          assigners: list(non_neg_integer()),
          # v
          next_validators_service: non_neg_integer(),
          # g
          services_gas: %{non_neg_integer() => non_neg_integer()}
        }

  defstruct manager: 0,
            assigners: List.duplicate(0, Constants.core_count()),
            next_validators_service: 0,
            services_gas: %{}

  defimpl Encodable do
    import Codec.Encoder
    alias System.State.PrivilegedServices

    def encode(%PrivilegedServices{} = v) do
      assigners_encoded = for assigner <- v.assigners, into: <<>>, do: <<assigner::m(service)>>

      <<v.manager::m(service)>> <>
        assigners_encoded <>
        <<v.next_validators_service::m(service)>> <>
        e(v.services_gas)
    end
  end

  use Sizes

  def decode(bin) do
    <<manager::m(service), rest::binary>> = bin

    # Decode assigners list using decode_list
    {assigners, rest} = Codec.Decoder.decode_list(rest, Constants.core_count(), fn bin ->
      <<assigner::m(service), rest::binary>> = bin
      {assigner, rest}
    end)

    <<next_validators_service::m(service), rest::binary>> = rest

    {services_gas, rest} = VariableSize.decode(rest, :map_int)

    {%__MODULE__{
       manager: manager,
       assigners: assigners,
       next_validators_service: next_validators_service,
       services_gas: services_gas
     }, rest}
  end

  def json_mapping do
    %{
      manager: :chi_m,
      assigners: :chi_a,
      next_validators_service: :chi_v,
      services_gas: [:chi_g, %{}]
    }
  end

  def to_json_mapping,
    do: %{
      manager: :chi_m,
      assigners: :chi_a,
      next_validators_service: :chi_v,
      services_gas: {:chi_g, &JsonEncoder.to_list(&1, :service, :gas)}
    }
end
