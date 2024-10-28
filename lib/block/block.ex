defmodule Block do
  alias Block.Extrinsic
  alias Block.Header
  alias System.State
  use SelectiveMock

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
         :ok <- validate_extrinsic_hash(h, e),
         :ok <- Extrinsic.validate(e, h, s) do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  mockable validate_extrinsic_hash(header, extrinsic) do
    if Header.valid_extrinsic_hash?(header, extrinsic) do
      :ok
    else
      {:error, "Invalid extrinsic hash"}
    end
  end

  def mock(:validate_extrinsic_hash, _), do: :ok

  defimpl Encodable do
    use Codec.Encoder

    def encode(%Block{extrinsic: e, header: h}) do
      # Formula (301) v0.4.1
      e({h, e})
    end
  end

  def decode(bin) do
    {header, bin} = Header.decode(bin)
    {extrinsic, bin} = Extrinsic.decode(bin)
    {%__MODULE__{header: header, extrinsic: extrinsic}, bin}
  end

  use JsonDecoder
  def json_mapping, do: %{header: Header, extrinsic: Extrinsic}
end
