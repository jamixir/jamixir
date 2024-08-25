// src/lib.rs
mod commitment;
mod ring_context;
mod secret_ops;
mod vrf_operations;

rustler::init!("Elixir.BandersnatchRingVrf");
