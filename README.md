# Jamixir

<img src="logo.png" alt="Project Logo" width="200" height="200"/>

Jamixir is the Elixir implementation of the JAM Protocol, as described in the [Graypaper authored by Gavin Wood](https://graypaper.com/). For more information, read our [FAQ](./FAQ.md)

# How to Run

## Using a docker image

Currently, some of our dependencies are in private repositories. To be able to pull from there, we need to enable SSH agent forwarding in local machine before issuing the docker build commands.

Ensure your SSH agent is running and has the right keys, run this command:

```bash
ssh-add -l
```
If it doesn’t (i.e. you don't see your keys), add them using:

```bash
ssh-add /path/to/your/private/key
```
Then run this command to enable Docker's buildkit in your terminal session:

```bash
export DOCKER_BUILDKIT=1
```
Then run these commands:

```bash
docker build --ssh default -t jamixir .
docker run -p 9000:9000 jamixir
```

## Using docker compose
The following commands build and run a simulated network of six Jamixir nodes.
```bash
docker compose build
docker compose up 
```


## Using development env

```bash
mix jam --keys test/keys/0.json --genesis genesis/genesis.json --port 9900
```

### How to Run Unit Tests

```bash
mix test
```

### How to Run Official Test Vectors
```bash
mix test.tiny  # Runs only tiny size official test vectors
mix test.full  # Runs the full size official test vectors 
```

### How to generate test blocks
```bash
mix test --only generate_blocks
```

### How to generate a bandersnatch key-pair
```bash
mix generate_keypair
```

# Tested Elixir / OTP version
 - Elixir 1.17-otp-26
 - Erlang 26.2.5

# MacOS build issues

If you are having MacOS issues to build quicer, try this:
```bash
cd deps/quicer
export CMAKE_OSX_ARCHITECTURES="$(uname -m)"
export MSQUIC_PLATFORM_OVERRIDE="darwin"
./build.sh v2.3.5
```
