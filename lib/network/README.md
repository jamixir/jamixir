# Network Module Architecture

This module implements a QUIC-based peer-to-peer networking layer for Jamixir nodes. The architecture is designed around a central connection manager that orchestrates all connection lifecycle operations and directly supervises all connection processes.

## Architecture Overview

```
┌─────────────┐    ┌─────────────┐
│   Listener  │    │  Init Task  │
│ (incoming)  │    │ (outgoing)  │
└──────┬──────┘    └──────┬──────┘
       │                  │
       └─────────┬────────┘
                 │
          ┌──────▼──────┐
          │ Connection  │ ◄── Central orchestrator
          │   Manager   │     Handles lifecycle & supervision
          └──────┬──────┘
                 │       ▲
                 │       │ connection_established()
                 │       │ connection_lost()
                 │       │
       ┌─────────┼───────┼─┐
       │         │       │ │
  ┌────▼───┐ ┌───▼───┐ ┌─▼─▼───┐
  │ Conn   │ │ Conn  │ │ Conn  │ ◄── Individual peer
  │ [ALICE]│ │ [BOB] │ │ [EVE] │     connections
  └────────┘ └───────┘ └───────┘
```

## Core Components

### 1. Entry Points

#### **Listener** (`listener.ex`)

- Listens for incoming QUIC connections from remote peers
- Handles connection acceptance and initial setup
- Delegates connection management to `ConnectionManager`
- Extracts peer address information for connection tracking

#### **Init Task** (external module)

- Initiates outbound connections to known validators
- Calls `ConnectionManager.connect_to_validators()` during node startup
- Handles the bootstrap connection process

### 2. Central Control Layer

#### **ConnectionManager** (`connection_manager.ex`)

- **Central orchestrator** for all connection lifecycle operations
- **Directly supervises all connection processes**
- Maintains connection state and implements retry logic
- Handles both inbound and outbound connection strategies

**Key Responsibilities:**

- Connection lifecycle management (start, monitor, restart, shutdown)
- Duplicate connection prevention
- Retry logic with exponential backoff for failed connections
- Connection status tracking and reporting

**Public API:**

- `connect_to_validators/1` - Start connections to validator set
- `start_outbound_connection/3` - Start a single outbound connection
- `get_connections/0` - Get all active connection PIDs
- `connection_established/2` - Notification from connections (success)
- `connection_lost/1` - Notification from connections (failure)
- `handle_inbound_connection/2` - Handle new incoming connections
- `shutdown_all_connections/0` - Graceful shutdown of all connections

### 3. Individual Connections

#### **Connection** (`connection.ex`)

- **Bidirectional QUIC connection** to a single remote peer
- Maintains `ConnectionState` with connection metadata
- Implements both client and server message handling
- **Notifies ConnectionManager** of status changes

**ConnectionState Fields:**

- `remote_ed25519_key` - identifies the remote validator
- `connection_closed` - Prevents duplicate closure handling
- Stream management maps for ongoing communications

**Event Notifications:**

- `connection_established()` - Successful connection setup
- `connection_lost()` - Connection failure or closure

## Data Flow

### Outbound Connection Flow

1. **Init Task** calls `ConnectionManager.connect_to_validators()`
2. **ConnectionManager** uses `ConnectionPolicy` to determine connection strategy
3. **ConnectionManager** starts new connection processes directly
4. **Connection** establishes QUIC connection and notifies manager

### Inbound Connection Flow

1. **Listener** accepts incoming QUIC connection
2. **Listener** calls `ConnectionManager.handle_inbound_connection()`
3. **ConnectionManager** starts new inbound connection process
4. **ConnectionManager** passs ownership of the QUIC connection to to newly created connection process
5. **Connection** begins stream handling for the established connection

### Connection Loss & Recovery

1. **Connection** detects QUIC connection closure
2. **Connection** calls `ConnectionManager.connection_lost()`
3. **ConnectionManager** kills the connection process and schedules retry (outbound) or waits (inbound)
4. Retry logic uses `ConnectionPolicy` for timing and strategy

## Supporting Modules

- **ConnectionPolicy** (`connection_policy.ex`) - Connection strategy and retry logic
- **ConnectionInfo** (`connection_info.ex`) - Connection metadata structure
- **ConnectionState** (`connection_state.ex`) - Per-connection state management
- **Client/Server** (`client.ex`, `server.ex`) - Message handling logic
