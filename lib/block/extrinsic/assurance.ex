defmodule Block.Extrinsic.Assurance do
  @moduledoc """
  A module representing an assurance with various attributes.

  The assurances extrinsic is a sequence of assurance values, at most one per validator.
  Each assurance is a sequence of binary values (i.e., a bitstring), one per core,
  together with a signature and the index of the validator who is assuring.
  """
  alias Block.Extrinsic.Guarantee.WorkReport
  alias System.State.CoreReport
  alias System.State.Validator
  alias Util.{Collections, Crypto, Hash}
  use SelectiveMock
  # Formula (124) v0.4.1
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
             curr_validators_,
             core_reports_intermediate_1
           ) do
    # Formula (125) v0.4.1
    with true <- Enum.all?(assurances, &(&1.hash == parent_hash)),
         # Formula (126) v0.4.1
         :ok <- Collections.validate_unique_and_ordered(assurances, & &1.validator_index),
         # Formula (127) v0.4.1
         :ok <- validate_signatures(assurances, parent_hash, curr_validators_),
         # Formula (129) v0.4.1
         :ok <- validate_core_reports_bits(assurances, core_reports_intermediate_1) do
      :ok
    else
      false -> {:error, "Invalid assurance"}
      {:error, e} -> {:error, e}
    end
  end

  def mock(:validate_assurances, _), do: :ok

  def mock(:available_work_reports, _) do
    0..(Constants.core_count() - 1)
    |> Enum.map(fn i -> %WorkReport{core_index: i} end)
  end

  # Formula (130) v0.4.1 W ≡ [ ρ†[c]w | c <− NC, ∑a∈EA av[c] > 2/3V ]
  @spec available_work_reports(list(__MODULE__.t()), list(CoreReport.t())) :: list(WorkReport.t())
  mockable available_work_reports(assurances, core_reports_intermediate_1) do
    threshold = 2 * Constants.validator_count() / 3

    0..(Constants.core_count() - 1)
    |> Stream.filter(fn c ->
      Stream.map(assurances, &Utils.get_bit(&1.bitfield, c))
      |> Enum.sum() > threshold
    end)
    |> Stream.map(&Enum.at(core_reports_intermediate_1, &1).work_report)
    |> Enum.to_list()
  end

  # Formula (129) v0.4.1
  defp validate_core_reports_bits(assurances, core_reports_intermediate) do
    all_ok =
      Enum.all?(assurances, fn assurance ->
        Stream.with_index(for <<bit::1 <- assurance.bitfield>>, do: bit)
        |> Enum.all?(fn {bit, index} ->
          bit == 0 or Enum.at(core_reports_intermediate, index) != nil
        end)
      end)

    if all_ok, do: :ok, else: {:error, "Invalid core reports bits"}
  end

  defp validate_signatures(assurances, parent_hash, curr_validators_) do
    if(
      Enum.all?(assurances, fn a ->
        valid_signature?(a, parent_hash, Enum.at(curr_validators_, a.validator_index))
      end),
      do: :ok,
      else: {:error, :invalid_signature}
    )
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

    def encode(%Assurance{} = assurance) do
      e(assurance.hash) <>
        e(pad(assurance.bitfield, Sizes.bitfield())) <>
        e_le(assurance.validator_index, @validator_size) <>
        e(pad(assurance.signature, @signature_size))
    end
  end

  use Sizes
  # defimpl Decodable do
  def decode(blob) do
    # this size needs to be defined in runtime because of mocked core count
    bitfield_size = Sizes.bitfield()

    <<hash::binary-size(@hash_size), bitfield::binary-size(bitfield_size),
      validator_index::binary-size(@validator_size), signature::binary-size(@signature_size),
      rest::binary>> = blob

    {
      %Block.Extrinsic.Assurance{
        hash: hash,
        bitfield: bitfield,
        validator_index: Codec.Decoder.decode_le(validator_index, 2),
        signature: signature
      },
      rest
    }
  end

  # end

  use JsonDecoder

  def json_mapping, do: %{hash: :anchor}
end
