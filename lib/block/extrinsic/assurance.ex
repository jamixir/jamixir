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

  # Formula (125) v0.3.4
  # EA ∈ ⟦(a ∈ H, f ∈ BC, v ∈ NV, s ∈ E)⟧∶V
  defstruct hash: <<0::256>>,
            # round 341 to fit byte size
            assurance_values: <<0::344>>,
            validator_index: 0,
            signature: <<0::512>>

  @type t :: %__MODULE__{
          # a
          hash: Types.hash(),
          # f
          assurance_values: bitstring(),
          # v
          validator_index: Types.validator_index(),
          # s
          signature: Types.ed25519_signature()
        }

  def validate_assurances(assurances, parent_hash, curr_validators_, core_reports_intermediate_1) do
    # Formula (126) v0.3.4
    with true <- Enum.all?(assurances, &(&1.hash == parent_hash)),
         # Formula (127) v0.3.4
         :ok <- Collections.validate_unique_and_ordered(assurances, & &1.validator_index),
         # Formula (128) v0.3.4
         :ok <- validate_signatures(assurances, parent_hash, curr_validators_),
         # Formula (130) v0.3.4
         :ok <- validate_core_reports_bits(assurances, core_reports_intermediate_1) do
      :ok
    else
      false -> {:error, "Invalid assurance"}
      {:error, e} -> {:error, e}
    end
  end

  # Formula (131) W ≡ [ ρ†[c]w | c <− NC, ∑a∈EA av[c] > 2/3V ]
  @spec available_work_reports(list(__MODULE__.t()), list(CoreReport.t())) :: list(WorkReport.t())
  def available_work_reports(assurances, core_reports_intermediate_1) do
    0..(Constants.core_count() - 1)
    |> Enum.filter(fn c ->
      Enum.sum(for a <- assurances, do: Utils.get_bit(a.assurance_values, c)) >
        2 * Constants.validator_count() / 3
    end)
    |> Enum.map(fn c -> Enum.at(core_reports_intermediate_1, c).work_report end)
  end

  # Formula (130) v0.3.4
  defp validate_core_reports_bits(assurances, core_reports_intermediate) do
    all_ok =
      Enum.all?(assurances, fn assurance ->
        Stream.with_index(for <<bit::1 <- assurance.assurance_values>>, do: bit)
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
         %__MODULE__{signature: s, assurance_values: f},
         parent_hash,
         %Validator{ed25519: e}
       ) do
    message = SigningContexts.jam_available() <> Hash.default(parent_hash <> f)
    Crypto.valid_signature?(s, message, e)
  end

  defimpl Encodable do
    def encode(%Block.Extrinsic.Assurance{} = assurance) do
      Codec.Encoder.encode(assurance.hash) <>
        Codec.Encoder.encode(assurance.assurance_values) <>
        Codec.Encoder.encode_le(assurance.validator_index, 2) <>
        Codec.Encoder.encode(assurance.signature)
    end
  end
end
