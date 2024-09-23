defprotocol Encodable do
  @doc "Encodes the given value"
  @spec encode(t) :: binary
  def encode(value)
end
