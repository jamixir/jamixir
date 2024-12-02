defmodule Block.Extrinsic.Assurance do
  @moduledoc """
  A module representing an assurance with various attributes.

  The assurances extrinsic is a sequence of assurance values, at most one per validator.
  Each assurance is a sequence of binary values (i.e., a bitstring), one per core,
  together with a signature and the index of the validator who is assuring.
  """
  alias System.State.Validator
  alias Util.{Collections, Crypto, Hash}
  use SelectiveMock
  # Formula (124) v0.4.5
  # EA ∈ ⟦(a ∈ H, f ∈ BC, v ∈ NV, s ∈ E)⟧∶V
  defstruct hash: Hash.zero(),
            bitfield: Utils.zero_bitstring(Sizes.bitfield()),
            validator_index: 0,
            signature: Crypto.zero_sign()

  @type t :: %__MODULE__{
          # a
          hash: Types.hash(),
          # f
          bitfield: bitstring(),
          # v
          validator_index: Types.validator_index(),
          # s
          signature: Types.ed25519_signature()
        }

  mockable validate_assurances(
             assurances,
             parent_hash,
             header_timeslot,
             curr_validators_,
             core_reports_intermediate_1
           ) do
    # Formula (125) v0.4.5
    with :ok <-
           if(Enum.all?(assurances, &(&1.hash == parent_hash)),
             do: :ok,
             else: {:error, :bad_attestation_parent}
           ),
         # Formula (126) v0.4.5
         :ok <- Collections.validate_unique_and_ordered(assurances, & &1.validator_index),
         # Formula (127) v0.4.5
         :ok <- validate_signatures(assurances, parent_hash, curr_validators_),
         # Formula (11.14) v0.5
         :ok <-
           validate_core_reports_bits(assurances, core_reports_intermediate_1, header_timeslot) do
      :ok
    else
      {:error, e} -> {:error, e}
    end
  end

  def mock(:validate_assurances, _), do: :ok

  # Formula (11.14) v0.5
  defp validate_core_reports_bits(assurances, core_reports_intermediate, h_t) do
    all_ok =
      Enum.all?(assurances, fn assurance ->
        Stream.with_index(for <<bit::1 <- assurance.bitfield>>, do: bit)
        |> Enum.all?(fn {bit, index} ->
          case bit do
            0 ->
              true

            _ ->
              Enum.at(core_reports_intermediate, index) != nil and
                h_t <=
                  Enum.at(core_reports_intermediate, index).timeslot +
                    Constants.unavailability_period()
          end
        end)
      end)

    if all_ok, do: :ok, else: {:error, :core_not_engaged_or_timeout}
  end

  defp validate_signatures(assurances, parent_hash, curr_validators_) do
    Enum.reduce_while(assurances, :ok, fn a, _ ->
      case Enum.at(curr_validators_, a.validator_index) do
        nil ->
          {:halt, {:error, :bad_validator_index}}

        v ->
          case valid_signature?(a, parent_hash, v) do
            true -> {:cont, :ok}
            false -> {:halt, {:error, :bad_signature}}
          end
      end
    end)
  end

  defp valid_signature?(_, _, nil), do: false

  defp valid_signature?(
         %__MODULE__{signature: s, bitfield: f},
         parent_hash,
         %Validator{ed25519: e}
       ) do
    message = SigningContexts.jam_available() <> Hash.default(parent_hash <> f)
    Crypto.valid_signature?(s, message, e)
  end

  defimpl Encodable do
    use Sizes
    use Codec.Encoder
    alias Block.Extrinsic.Assurance

    def pad(value, size) do
      Utils.pad_binary(value, size)
    end

    # Formula (C.17) v0.5.0
    def encode(%Assurance{} = a) do
      e(a.hash) <>
        e(pad(a.bitfield, Sizes.bitfield())) <>
        e_le(a.validator_index, @validator_index_size) <>
        e(pad(a.signature, @signature_size))
    end
  end

  use Sizes
  use Codec.Decoder
  # defimpl Decodable do
  def decode(bin) do
    # this size needs to be defined in runtime because of mocked core count
    bitfield_size = Sizes.bitfield()

    <<hash::binary-size(@hash_size), bitfield::binary-size(bitfield_size),
      validator_index::binary-size(@validator_index_size),
      signature::binary-size(@signature_size), rest::binary>> = bin

    {
      %__MODULE__{
        hash: hash,
        bitfield: bitfield,
        validator_index: de_le(validator_index, 2),
        signature: signature
      },
      rest
    }
  end

  # end

  use JsonDecoder

  def json_mapping, do: %{hash: :anchor}
end
