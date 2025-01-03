defmodule Block do
  alias Block.Extrinsic
  alias Block.Header
  alias System.State
  use SelectiveMock

  @type t :: %__MODULE__{header: Block.Header.t(), extrinsic: Block.Extrinsic.t()}

  # Formula (13) v0.4.5
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
         :ok <- validate_refinement_context(h, e),
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
  def mock(:validate_refinement_context, _), do: :ok

  use Codec.Encoder
  # Formula (149) v0.4.5
  mockable validate_refinement_context(%Header{} = header, %Extrinsic{guarantees: guarantees}) do
    Enum.reduce_while(guarantees, :ok, fn g, _ ->
      x = g.work_report.refinement_context

      case Enum.any?(Header.ancestors(header), fn h ->
             h.timeslot == x.timeslot and h(e(h)) == x.lookup_anchor
           end) do
        true -> {:cont, :ok}
        false -> {:halt, {:error, "Refinement context is invalid"}}
      end
    end)
  end

  defimpl Encodable do
    use Codec.Encoder

    # Formula (C.13) v0.5.0
    def encode(%Block{extrinsic: e, header: h}), do: e({h, e})
  end

  def decode(bin) do
    {header, bin} = Header.decode(bin)
    {extrinsic, bin} = Extrinsic.decode(bin)
    {%__MODULE__{header: header, extrinsic: extrinsic}, bin}
  end

  def decode_list(<<>>), do: []

  def decode_list(bin) do
    {block, rest} = decode(bin)
    [block | decode_list(rest)]
  end

  use JsonDecoder
  def json_mapping, do: %{header: Header, extrinsic: Extrinsic}
end
