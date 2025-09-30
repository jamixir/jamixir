defmodule System.State.PrivilegedServices do
  alias Codec.JsonEncoder
  import Codec.Encoder
  alias Codec.VariableSize
  use JsonDecoder

  @type free_accumulating_services :: %{Types.service_index() => Types.gas()}

  # Formula (9.9) v0.7.2
  @type t :: %__MODULE__{
          # Formula (9.10) v0.7.2 - χ_M
          manager: Types.service_index(),
          # Formula (9.10) v0.7.2 - χ_V
          delegator: Types.service_index(),
          # Formula (9.10) v0.7.2 - χ_R
          registrar: Types.service_index(),
          # Formula (9.11) v0.7.2 - χ_A
          assigners: list(Types.service_index()),
          # Formula (9.11) v0.7.2 - χ_Z
          always_accumulated: free_accumulating_services()
        }

  defstruct manager: 0,
            delegator: 0,
            registrar: 0,
            assigners: List.duplicate(0, Constants.core_count()),
            always_accumulated: %{}

  defimpl Encodable do
    import Codec.Encoder
    alias System.State.PrivilegedServices

    def encode(%PrivilegedServices{} = v) do
      assigners_encoded = for assigner <- v.assigners, into: <<>>, do: <<assigner::m(service)>>

      <<v.manager::m(service), assigners_encoded::binary, v.delegator::m(service),
        v.registrar::m(service)>> <>
        e(v.always_accumulated)
    end
  end

  use Sizes

  def decode(bin) do
    <<manager::m(service), rest::binary>> = bin

    # Decode assigners list using decode_list
    {assigners, rest} =
      Codec.Decoder.decode_list(rest, Constants.core_count(), fn bin ->
        <<assigner::m(service), rest::binary>> = bin
        {assigner, rest}
      end)

    <<delegator::m(service), rest::binary>> = rest
    <<registrar::m(service), rest::binary>> = rest

    {always_accumulated, rest} = VariableSize.decode(rest, :map_int)

    {%__MODULE__{
       manager: manager,
       assigners: assigners,
       delegator: delegator,
       registrar: registrar,
       always_accumulated: always_accumulated
     }, rest}
  end

  def json_mapping do
    %{
      manager: :chi_m,
      assigners: :chi_a,
      delegator: :chi_v,
      registrar: :chi_r,
      always_accumulated: [:chi_g, %{}]
    }
  end

  def to_json_mapping,
    do: %{
      manager: :chi_m,
      assigners: :chi_a,
      delegator: :chi_v,
      registrar: :chi_r,
      always_accumulated: {:chi_g, &JsonEncoder.to_list(&1, :service, :gas)}
    }
end
