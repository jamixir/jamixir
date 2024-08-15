defmodule Block.Extrinsic.Availability do
  @type t :: %__MODULE__{
          work_package_hash: Types.hash(), # h
          work_bundle_length: Types.max_age_timeslot_lookup_anchor(), # l
          erasure_root: Types.hash(), # u
          segment_root: Types.hash() # e
        }

  # Formula (122) v0.3.4
  # h
  defstruct work_package_hash: <<0::256>>,
            # l
            work_bundle_length: 0,
            # u
            erasure_root: <<0::256>>,
            # e
            segment_root: <<0::256>>
  defimpl Encodable do
    def encode(%Block.Extrinsic.Availability{} = availability) do
      Codec.Encoder.encode(availability.work_package_hash) <>
        Codec.Encoder.encode_le(availability.work_bundle_length,4) <>
        Codec.Encoder.encode({availability.erasure_root,availability.segment_root})
    end
  end
end
