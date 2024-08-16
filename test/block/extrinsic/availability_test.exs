defmodule Block.Extrinsic.AvailabilityTest do
  use ExUnit.Case

  setup do
    {:ok,
     availability: %Block.Extrinsic.Availability{
       work_package_hash: <<1::256>>,
       work_bundle_length: 2,
       erasure_root: <<3::256>>,
       segment_root: <<4::256>>
     }}
  end

  test "encode/1", %{availability: availability} do
    assert Codec.Encoder.encode(availability) ==
             "\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x01\x02\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x03\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\x04"
  end
end
