# Network Module Architecture

This module implements a QUIC-based peer-to-peer networking layer for Jamixir nodes. The architecture is designed around a central connection manager that orchestrates all connection lifecycle operations.

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
          │   Manager   │     Handles lifecycle
          └──────┬──────┘
                 │       ▲
                 │       │ connection_established()
                 │       │ connection_lost()
                 │       │
          ┌──────▼──────┐│
          │ Connection  ││ ◄── Process supervisor
          │ Supervisor  ││     Prevents duplicates
          └──────┬──────┘│
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
- **Only component** that directly interacts with `ConnectionSupervisor`
- Maintains connection state and implements retry logic
- Handles both inbound and outbound connection strategies

**Key Responsibilities:**
- Connection lifecycle management (start, monitor, restart)
- Duplicate connection prevention via supervisor coordination
- Retry logic with exponential backoff for failed connections
- Connection status tracking and reporting

**Public API:**
- `connect_to_validators/1` - Start connections to validator set
- `get_connections/0` - Get all active connection PIDs
- `connection_established/2` - Notification from connections (success)
- `connection_lost/1` - Notification from connections (failure)
- `handle_inbound_connection/4` - Handle new incoming connections

### 3. Process Management

#### **ConnectionSupervisor** (`connection_supervisor.ex`)
- **Process supervisor** for individual connection processes
- **Connection registry** - prevents duplicate connections
- Uses connection address (`ip:port`) as unique identifier
- Handles both inbound and outbound connection process creation

**Key Features:**
- Duplicate prevention: Checks existing connections before starting new ones
- Process lifecycle: Starts, monitors, and terminates connection processes
- Connection lookup: Maps addresses to process PIDs
- Clean shutdown: Properly closes QUIC connections on errors

### 4. Individual Connections

#### **Connection** (`connection.ex`)
- **Bidirectional QUIC connection** to a single remote peer
- Maintains `PeerState` with connection metadata
- Implements both client and server message handling
- **Notifies ConnectionManager** of status changes

**PeerState Fields:**
- `remote_address` / `remote_port` - Peer identification
- `local_port` - Local service port (for inbound connections)
- `connection_closed` - Prevents duplicate closure handling
- Stream management maps for ongoing communications

**Event Notifications:**
- `connection_established()` - Successful connection setup
- `connection_lost()` - Connection failure or closure

## Data Flow

### Outbound Connection Flow
1. **Init Task** calls `ConnectionManager.connect_to_validators()`
2. **ConnectionManager** uses `ConnectionPolicy` to determine connection strategy
3. **ConnectionManager** calls `ConnectionSupervisor.start_outbound_connection()`
4. **ConnectionSupervisor** creates new `Connection` process
5. **Connection** establishes QUIC connection and notifies manager

### Inbound Connection Flow
1. **Listener** accepts incoming QUIC connection
2. **Listener** calls `ConnectionManager.handle_inbound_connection()`
3. **ConnectionManager** calls `ConnectionSupervisor.start_inbound_connection()`
4. **ConnectionSupervisor** checks for duplicates and creates `Connection` process
5. **Connection** begins stream handling for the established connection

### Connection Loss & Recovery
1. **Connection** detects QUIC connection closure
2. **Connection** calls `ConnectionManager.connection_lost()`
3. **ConnectionManager** kills the connection process via supervisor
4. **ConnectionManager** schedules retry (outbound) or waits (inbound)
5. Retry logic uses `ConnectionPolicy` for timing and strategy

## Key Design Principles

### Single Point of Control
- Only `ConnectionManager` talks to `ConnectionSupervisor`
- Centralized connection state and policy decisions
- Simplified debugging and monitoring

### Bidirectional Communication
- **Downward**: Manager controls connection lifecycle
- **Upward**: Connections report status changes
- **Event-driven**: Reactive to connection state changes

### Duplicate Prevention
- Address-based connection registry in supervisor
- Prevents multiple connections to same peer
- Handles race conditions in connection establishment

### Resilient Connection Management
- Automatic retry with exponential backoff
- Different strategies for inbound vs outbound connections
- Graceful handling of network failures

## Supporting Modules

- **ConnectionPolicy** (`connection_policy.ex`) - Connection strategy and retry logic
- **ConnectionInfo** (`connection_info.ex`) - Connection metadata structure
- **PeerState** (`peer_state.ex`) - Per-connection state management
- **Client/Server** (`client.ex`, `server.ex`) - Message handling logic


## Node Identity Integration

Connections are identified using friendly names (ALICE, BOB, etc.) based on port mappings defined in `Util.NodeIdentity`. This makes logging and debugging much more intuitive than using raw IP addresses and process IDs. 