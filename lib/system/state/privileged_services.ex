defmodule System.State.PrivilegedServices do
  @moduledoc """
  Formula (9.9) v0.6.7
  """
  alias Codec.JsonEncoder
  import Codec.Encoder
  alias Codec.VariableSize
  use JsonDecoder

  @type t :: %__MODULE__{
          # χm
          manager: non_neg_integer(),
          # χa
          assigners: list(non_neg_integer()),
          # χv
          delegator: non_neg_integer(),
          # χg
          alwaysaccers: %{non_neg_integer() => non_neg_integer()}
        }

  defstruct manager: 0,
            assigners: List.duplicate(0, Constants.core_count()),
            delegator: 0,
            alwaysaccers: %{}

  defimpl Encodable do
    import Codec.Encoder
    alias System.State.PrivilegedServices

    def encode(%PrivilegedServices{} = v) do
      assigners_encoded = for assigner <- v.assigners, into: <<>>, do: <<assigner::m(service)>>

      <<v.manager::m(service)>> <>
        assigners_encoded <>
        <<v.delegator::m(service)>> <>
        e(v.alwaysaccers)
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

    <<delegator::m(service), rest::binary>> = rest

    {alwaysaccers, rest} = VariableSize.decode(rest, :map_int)

    {%__MODULE__{
       manager: manager,
       assigners: assigners,
       delegator: delegator,
       alwaysaccers: alwaysaccers
     }, rest}
  end

  def json_mapping do
    %{
      manager: :chi_m,
      assigners: :chi_a,
      delegator: :chi_v,
      alwaysaccers: [:chi_g, %{}]
    }
  end

  def to_json_mapping,
    do: %{
      manager: :chi_m,
      assigners: :chi_a,
      delegator: :chi_v,
      alwaysaccers: {:chi_g, &JsonEncoder.to_list(&1, :service, :gas)}
    }
end
