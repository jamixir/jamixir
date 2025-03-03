# Jamixir

![Project Logo](logo.png)

Jamixir is the Elixir implementation of the JAM Protocol, as described in the [Graypaper authored by Gavin Wood](https://graypaper.com/). For more information, read our [FAQ](./FAQ.md)

## How to Run

### Using a docker image (cli)

### Using development env

```shell
mix jam --keys test/keys/0.json
```

#### How to Run Unit Tests

```shell
mix test
```

#### How to Run Official Test Vectors

```shell
mix test.tiny  # Runs only tiny size offical test vectors
mix test.full  # Runs the full size officai test vectors 
```

#### How to generate test blocks

```shell
mix test --only generate_blocks
```

#### How to generate a bandersnatch key-pair

```shell
mix generate_keypair
```

## Tested Elixir / OTP version

- Elixir 1.17-otp-26
- Erlang 26.2.5
