defmodule Block.Extrinsic.Assurance do
  @moduledoc """
  A module representing an assurance with various attributes.

  The assurances extrinsic is a sequence of assurance values, at most one per validator.
  Each assurance is a sequence of binary values (i.e., a bitstring), one per core,
  together with a signature and the index of the validator who is assuring.
  """
  alias Util.Collections

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

  def validate_assurances(assurances, parent_hash) do
    # Formula (126) v0.3.4
    with true <- Enum.all?(assurances, &(&1.hash == parent_hash)),
         # Formula (127) v0.3.4
         :ok <- Collections.validate_unique_and_ordered(assurances, & &1.validator_index) do
      :ok
    else
      false -> {:error, "Invalid assurance"}
      {:error, e} -> {:error, e}
    end
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
