# Jamixir

<img src="logo.png" alt="Project Logo" width="200" height="200"/>

Jamixir is the Elixir implementation of the JAM Protocol, as described in the [Graypaper authored by Gavin Wood](https://graypaper.com/). For more information, read our [FAQ](./FAQ.md)

# How to Run

## Using a docker image

Currently, some of our dependencies are in private repositories. To be able to pull from there, we need enable SSH agent forwarding in local machine before issuing the docker build commands.

Ensure your SSH agent is running and has the right keys, run this command:

```
ssh-add -l
```
If it doesn’t (i.e. you don't see your keys), add them using:

```
ssh-add /path/to/your/private/key
```
Then run this command to build the container

```
# replace $HOME/.ssh/id_rsa for your ssh key PATH
docker build --secret id=ssh_key,src=$HOME/.ssh/id_rsa -t jamixir .
```

## Using docker compose
The following commands build and run a simulated network of six Jamixir nodes.
```
docker compose build
docker compose up 
```

## Using development env

```
mix jam --keys test/keys/0.json
```

## Using releases (production)

### Build the release
```bash
# Build with tiny configuration (6 validators, shorter epochs)
MIX_ENV=tiny mix release

# Build with production configuration
MIX_ENV=prod mix release
```

### Run the release
```bash
cd _build/tiny/rel/jamixir

# Show help
./jamixir --help

# Run the fuzzer
./jamixir fuzzer 

# Generate keys
./jamixir gen-keys
./jamixir gen-keys --file-name my-validator-key

# List existing keys
./jamixir list-keys

# Run a node
./jamixir run
./jamixir run --port 10001
./jamixir run --keys path/to/keys.seed --genesis path/to/genesis.json
```
## Testing
### How to Run Unit Tests
```
mix test
```

### How to Run Performance Tests
```
mix test --only perf
```


### How to Run Official Test Vectors
```
mix test.tiny  # Runs only tiny size offical test vectors
mix test.full  # Runs the full size officai test vectors 
```

### How to generate test blocks
```
mix test --only generate_blocks
```

### How to generate a bandersnatch key-pair

**Development:**
```
mix generate_keypair
```

**Release:**
```
./jamixir gen-keys
```

# Tested Elixir / OTP version
 - Elixir 1.17-otp-26
 - Erlang 26.2.5

