defprotocol Encodable do
  @doc "Encodes the given value"
  def encode(value)
end
