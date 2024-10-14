defmodule Block do
  alias Block.Extrinsic
  alias Block.Header
  alias System.State

  @type t :: %__MODULE__{header: Block.Header.t(), extrinsic: Block.Extrinsic.t()}

  # Formula (13) v0.4.1
  defstruct [
    # Hp
    header: nil,
    # Hr
    extrinsic: nil
  ]

  @spec validate(t(), System.State.t()) :: :ok | {:error, String.t()}
  def validate(%__MODULE__{header: h, extrinsic: e}, %State{} = s) do
    with :ok <- Header.validate(h, s),
         :ok <- Extrinsic.validate(e, h, s) do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defimpl Encodable do
    def encode(%Block{extrinsic: e, header: h}) do
      # Formula (301) v0.4.1
      Codec.Encoder.encode({h, e})
    end
  end

  use JsonDecoder
  def json_mapping, do: %{header: Header, extrinsic: Extrinsic}
end
