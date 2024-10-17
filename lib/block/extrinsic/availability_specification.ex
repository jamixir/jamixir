defmodule Block.Extrinsic.AvailabilitySpecification do
  alias Util.Hash

  @type t :: %__MODULE__{
          # h: hash of the work-package
          work_package_hash: Types.hash(),
          # l: auditable work bundle length
          len: Types.max_age_timeslot_lookup_anchor(),
          # u: erasure-root
          erasure_root: Types.hash(),
          # e: segment-root
          exports_root: Types.hash()
        }

  # Formula (121) v0.4.1
  # h
  defstruct work_package_hash: Hash.zero(),
            # l
            len: 0,
            # u
            erasure_root: Hash.zero(),
            # e
            exports_root: Hash.zero()

  defimpl Encodable do
    use Codec.Encoder
    # Formula (305) v0.4.1
    def encode(%Block.Extrinsic.AvailabilitySpecification{} = availability) do
      e(availability.work_package_hash) <>
        e_le(availability.len, 4) <>
        e({availability.erasure_root, availability.exports_root})
    end
  end

  use JsonDecoder

  use Sizes
  use Codec.Decoder

  def decode(blob) do
    <<work_package_hash::binary-size(@hash_size), len::binary-size(4),
      erasure_root::binary-size(@hash_size), exports_root::binary-size(@hash_size),
      rest::binary>> = blob

    {%__MODULE__{
       work_package_hash: work_package_hash,
       len: de_le(len, 4),
       erasure_root: erasure_root,
       exports_root: exports_root
     }, rest}
  end

  def json_mapping, do: %{work_package_hash: :hash}
end
