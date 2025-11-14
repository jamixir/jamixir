defmodule Block.Extrinsic.Assurance do
  @moduledoc """
  A module representing an assurance with various attributes.

  The assurances extrinsic is a sequence of assurance values, at most one per validator.
  Each assurance is a sequence of binary values (i.e., a bitstring), one per core,
  together with a signature and the index of the validator who is assuring.
  """
  alias Util.{Collections, Crypto, Hash}
  use SelectiveMock
  use Sizes
  import Codec.Encoder
  # Formula (11.10) v0.7.2
  # EA ∈ ⟦(a ∈ H, f ∈ bC, v ∈ ℕ_V, s ∈ ¯V¯)⟧∶V
  defstruct hash: Hash.zero(),
            bitfield: <<0::@bitfield_size*8>>,
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
             curr_validators,
             core_reports_intermediate_1
           ) do
    # Formula (11.11) v0.7.2
    with :ok <-
           if(Enum.all?(assurances, &(&1.hash == parent_hash)),
             do: :ok,
             else: {:error, :bad_attestation_parent}
           ),
         # Formula (11.12) v0.7.2
         :ok <- Collections.validate_unique_and_ordered(assurances, & &1.validator_index),
         # Formula (11.13) v0.7.2
         :ok <- validate_signatures(assurances, parent_hash, curr_validators),
         # Formula (11.15) v0.7.2
         :ok <-
           validate_core_reports_bits(assurances, core_reports_intermediate_1) do
      :ok
    else
      {:error, e} -> {:error, e}
    end
  end

  def mock(:validate_assurances, _), do: :ok

  # Formula (11.15) v0.7.2
  defp validate_core_reports_bits(assurances, core_reports_intermediate) do
    all_ok =
      Enum.all?(assurances, fn assurance ->
        bits = core_bits(assurance)

        Enum.all?(0..(Constants.core_count() - 1), fn c ->
          case elem(bits, c) do
            0 -> true
            _ -> Enum.at(core_reports_intermediate, c) != nil
          end
        end)
      end)

    if all_ok, do: :ok, else: {:error, :core_not_engaged}
  end

  defp validate_signatures(assurances, parent_hash, curr_validators_) do
    if Enum.any?(assurances, &(Enum.at(curr_validators_, &1.validator_index) == nil)) do
      {:error, :bad_validator_index}
    else
      case Crypto.batch_verify(
             for a <- assurances do
               v = Enum.at(curr_validators_, a.validator_index)
               message = SigningContexts.jam_available() <> h(parent_hash <> a.bitfield)
               {a.signature, message, v.ed25519}
             end
           ) do
        :ok -> :ok
        _ -> {:error, :bad_signature}
      end
    end
  end

  defimpl Encodable do
    use Sizes
    import Codec.Encoder
    alias Block.Extrinsic.Assurance

    # Formula (C.20) v0.7.2
    def encode(%Assurance{} = a) do
      e(a.hash) <>
        e(a.bitfield) <>
        t(a.validator_index) <>
        e(a.signature)
    end
  end

  use Sizes
  # defimpl Decodable do
  def decode(bin) do
    # this size needs to be defined in runtime because of mocked core count
    <<hash::b(hash), bitfield::b(bitfield), validator_index::m(validator_index),
      signature::b(signature), rest::binary>> = bin

    {
      %__MODULE__{
        hash: hash,
        bitfield: bitfield,
        validator_index: validator_index,
        signature: signature
      },
      rest
    }
  end

  # end

  use JsonDecoder

  def json_mapping, do: %{hash: :anchor}

  def core_bits(%__MODULE__{bitfield: b}) do
    Util.Merklization.bits(b)
    |> Enum.chunk_every(8)
    |> Enum.map(&Enum.reverse/1)
    |> List.flatten()
    |> Enum.take(Constants.core_count())
    |> List.to_tuple()
  end
end
