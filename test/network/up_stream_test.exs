defmodule Network.UpStreamTest do
  use ExUnit.Case
  alias Network.UpStreamManager
  alias Network.PeerState

  @log_context "[TEST]"

  # Helper to create reliably ordered references
  # We use Process.monitor to create references with predictable ordering
  defp make_ordered_ref(n) do
    # Create a dummy process for monitoring
    pid = spawn(fn -> receive do _ -> :ok end end)
    # The n different monitors will create n different refs
    Enum.map(1..n, fn _ -> Process.monitor(pid) end) |> List.last()
  end

  # Test helper to guarantee reference ordering
  defp test_ref_ordering do
    # Higher numbers should create "greater" references
    ref1 = make_ordered_ref(1)
    ref2 = make_ordered_ref(2)
    {ref1, ref2, ref1 < ref2}
  end

  describe "manage_up_stream" do
    test "handles new UP stream correctly" do
      # Setup
      protocol_id = 42
      stream = make_ref()
      state = %PeerState{up_streams: %{}, up_stream_data: %{}}

      # Call function directly
      {{:ok, stream_data}, new_state} = UpStreamManager.manage_up_stream(protocol_id, stream, state, @log_context)

      # Verify results
      assert new_state.up_streams[protocol_id] == stream
      assert Map.has_key?(new_state.up_stream_data, stream)
      assert stream_data.protocol_id == protocol_id
      assert stream_data.buffer == <<>>
    end

    test "reuses existing UP stream with same ID" do
      # Setup
      protocol_id = 42
      stream = make_ref()
      stream_data = %{protocol_id: protocol_id, buffer: <<>>}

      state = %PeerState{
        up_streams: %{protocol_id => stream},
        up_stream_data: %{stream => stream_data}
      }

      # Call function directly
      {{:ok, returned_stream_data}, new_state} = UpStreamManager.manage_up_stream(protocol_id, stream, state, @log_context)

      # Verify results
      assert new_state.up_streams[protocol_id] == stream
      assert returned_stream_data == stream_data
      assert new_state == state  # State should be unchanged
    end

    test "replaces existing UP stream with higher reference" do
      # First verify our ref ordering helper works
      {low_ref, high_ref, true} = test_ref_ordering()

      # Setup initial state with existing stream
      protocol_id = 42
      old_stream = low_ref
      old_stream_data = %{protocol_id: protocol_id, buffer: <<"old_data">>}

      state = %PeerState{
        up_streams: %{protocol_id => old_stream},
        up_stream_data: %{old_stream => old_stream_data}
      }

      # New stream with same protocol ID but guaranteed to be higher
      new_stream = high_ref

      # Double-check our helper is working
      assert new_stream > old_stream

      # Call function directly
      {{:ok, new_stream_data}, new_state} = UpStreamManager.manage_up_stream(protocol_id, new_stream, state, @log_context)

      # Verify results
      assert new_state.up_streams[protocol_id] == new_stream
      assert Map.has_key?(new_state.up_stream_data, new_stream)
      assert new_stream_data.protocol_id == protocol_id
      assert new_stream_data.buffer == <<>>

      # Old stream data should be gone
      refute Map.has_key?(new_state.up_stream_data, old_stream)
    end

    test "rejects stream with lower reference" do
      # Generate ordered references
      {low_ref, high_ref, true} = test_ref_ordering()

      # Setup - we need the higher stream to exist first
      protocol_id = 42
      higher_stream = high_ref
      stream_data = %{protocol_id: protocol_id, buffer: <<>>}

      state = %PeerState{
        up_streams: %{protocol_id => higher_stream},
        up_stream_data: %{higher_stream => stream_data}
      }

      # Use the lower reference
      lower_stream = low_ref

      # Double-check our helper is working
      assert lower_stream < higher_stream

      # Call function directly - ensure the lower stream is rejected
      {:reject, unchanged_state} = UpStreamManager.manage_up_stream(protocol_id, lower_stream, state, @log_context)

      # Verify the state is unchanged
      assert unchanged_state == state
      assert unchanged_state.up_streams[protocol_id] == higher_stream
    end
  end
end
