# Quick RPC Test Commands

## Test the parameters endpoint
```bash
curl -X POST http://localhost:19801/rpc \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"parameters","id":1}'
```

## Test the bestBlock endpoint  
```bash
curl -X POST http://localhost:19801/rpc \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"bestBlock","id":2}'
```

## Test an unknown method (should return error)
```bash
curl -X POST http://localhost:19801/rpc \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"unknownMethod","id":3}'
```

## Test batch request
```bash
curl -X POST http://localhost:19801/rpc \
  -H "Content-Type: application/json" \
  -d '[{"jsonrpc":"2.0","method":"parameters","id":1},{"jsonrpc":"2.0","method":"bestBlock","id":2}]'
```

## WebSocket test (using wscat if available)
```bash
# Install wscat: npm install -g wscat
wscat -c ws://localhost:19801/ws

# Then send:
{"jsonrpc":"2.0","method":"parameters","id":1}
```