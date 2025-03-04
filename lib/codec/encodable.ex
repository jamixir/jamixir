defprotocol Encodable do
  use Codec.Encoder

  @spec encode(t) :: binary
  def encode(value)
end
