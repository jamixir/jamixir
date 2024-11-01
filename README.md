# Jamixir

<img src="logo.png" alt="Project Logo" width="200" height="200"/>

Jamixir is the Elixir implementation of the JAM Protocol, as described in the [Graypaper authored by Gavin Wood](https://graypaper.com/). For more information, read our [FAQ](./FAQ.md)

# How to Run

## Using a docker image (cli)
```
docker build -t jamixir .
docker run jamixir
```


## Using development env

```
mix jam
```

### How to Run Unit Tests

```
mix test
```

### How to Run Official Test Vectors
```
mix test --only test_vectors
```

### How to generate a bandersnatch key-pair
```
mix generate_keypair
```

# Tested Elixir / OTP version
 - Elixir 1.17-otp-26
 - Erlang 26.2.5

