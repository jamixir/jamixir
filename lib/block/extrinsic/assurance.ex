defmodule Assurance do
  @moduledoc """
  A module representing an assurance with various attributes.

  The assurances extrinsic is a sequence of assurance values, at most one per validator.
  Each assurance is a sequence of binary values (i.e., a bitstring), one per core,
  together with a signature and the index of the validator who is assuring.
  """

  # Formula (125) v0.3.4
  # EA ∈ ⟦(a ∈ H, f ∈ BC, v ∈ NV, s ∈ E)⟧∶V
  defstruct hash: <<0::256>>,
            # round 341 to fit byte size
            assurance_values: <<0::344>>,
            validator_index: 0,
            signature: <<0::512>>

  @type t :: %__MODULE__{
          hash: Types.hash(),
          assurance_values: bitstring(),
          validator_index: Types.validator_index(),
          signature: Types.ed25519_signature()
        }

  @doc """
  Creates a new assurance.

  ## Examples

      iex> %Assurances{validator_index: 1, assurance_values: <<1, 0, 1>>, signature: <<123, 45, 67>>}
      %Assurances{validator_index: 1, assurance_values: <<1, 0, 1>>, signature: <<123, 45, 67>>}

  """
  def new(validator_index, assurance_values, signature) do
    %__MODULE__{
      validator_index: validator_index,
      assurance_values: assurance_values,
      signature: signature
    }
  end

  defimpl Encodable do
    def encode(%Assurance{} = assurance) do
      Codec.Encoder.encode(assurance.hash) <>
        Codec.Encoder.encode(assurance.assurance_values) <>
        Codec.Encoder.encode_le(assurance.validator_index, 2) <>
        Codec.Encoder.encode(assurance.signature)
    end
  end
end
