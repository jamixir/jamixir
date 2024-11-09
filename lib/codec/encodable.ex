defprotocol Encodable do
  use Codec.Encoder
  @doc "Encodes the given value"
  @spec encode(t) :: binary
  def encode(value)
end
