# NIF for Elixir.ErasureCoding

A Rust-based Native Implemented Function (NIF) for Elixir providing Reed-Solomon erasure coding functionality.

## Project Structure

- `src/lib.rs` - NIF interface layer for Elixir integration
- `src/erasure_codec.rs` - Core Reed-Solomon encoding/decoding logic

## To build the NIF module:

- Your NIF will now build along with your project.

## To run tests:

The core logic can be tested independently of the Elixir/NIF runtime:

```bash
# Run tests for the core erasure coding logic
cargo test --no-default-features

# Build the full NIF library (requires Elixir environment for full testing)
cargo build
```

## To load the NIF:

```elixir
defmodule ErasureCoding do
  use Rustler, otp_app: :jamixir, crate: "erasure_coding"

  # When your NIF is loaded, it will override this function.
  def encode(_data, _c), do: :erlang.nif_error(:nif_not_loaded)
  def decode(_shards, _indexes, _original_size, _c), do: :erlang.nif_error(:nif_not_loaded)
end
```

## Examples

[This](https://github.com/rusterlium/NifIo) is a complete example of a NIF written in Rust.
