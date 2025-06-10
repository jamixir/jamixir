# defimpl Inspect, for: BitString do
#   def inspect(term, _) when is_binary(term) do
#     "0x" <> Base.encode16(term, case: :lower)
#   end
# end
