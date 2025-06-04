defprotocol Encodable do

  @spec encode(t) :: binary
  def encode(value)
end
