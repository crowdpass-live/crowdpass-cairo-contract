# CROWDPASS CONTRACT
## EventFactory Contract

A Starknet contract for creating and managing events with ERC721 tickets, integrated with Token Bound Accounts (TBA) and STRK token payments.

## Features

- **Event Management**: Create, update, and cancel events with configurable details
- **ERC721 Tickets**: Generate NFT tickets for each event
- **Token Bound Accounts**: Automatically create TBAs for ticket holders
- **Access Control**: Role-based permissions for event organizers
- **Payment Handling**: STRK token payments with 3% platform fee
- **Check-in System**: Track event attendance
- **Payouts & Refunds**: Secure fund distribution and cancellation refunds

## Key Components

### Storage Structure
- `events`: Map of event IDs to event data
- `event_balance`: Track collected funds per event
- `event_attendance`: Attendance records
- Integrated OpenZeppelin components:
  - Access Control
  - Upgradeability
  - SRC5 interface

### Core Functions

#### Event Management
- `create_event`: Initialize new event with ERC721 ticket contract
- `update_event`: Modify event details (organizers only)
- `cancel_event`: Cancel future event and enable refunds

#### Ticket Operations
- `purchase_ticket`: Buy ticket with STRK tokens (creates TBA)
- `refund_ticket`: Get refund for canceled events
- `check_in`: Verify attendee ticket ownership

#### Financial
- `collect_event_payout`: Transfer event proceeds to organizer
- Automatic 3% fee on ticket sales

### Access Control Roles
- `DEFAULT_ADMIN_ROLE`: Manage contract upgrades
- Event-specific roles:
  - Main Organizer (per event)
  - Secondary Organizers

## Events

| Event Name         | Description                          | Parameters                                      |
|---------------------|--------------------------------------|-------------------------------------------------|
| `EventCreated`      | New event created                    | Event ID, Organizer, Ticket Address            |
| `TicketPurchased`   | Ticket sold                          | Event ID, Ticket ID, Buyer, TBA Address, Price |
| `CheckedIn`         | Attendee checked in                  | Event ID, Attendee Address, Timestamp          |
| `PayoutCollected`   | Organizer withdrew funds             | Event ID, Organizer Address, Amount            |

## Usage

### Deployment
```cairo
constructor(
    default_admin: felt252  // Admin address
)
```

### Creating an Event
```cairo
create_event(
    name: ByteArray,
    symbol: ByteArray,
    uri: ByteArray,
    description: ByteArray,
    location: ByteArray,
    start_date: u64,
    end_date: u64,
    total_tickets: u256,
    ticket_price: u256
) → EventData
```

### Purchasing Tickets
```cairo
purchase_ticket(event_id: u256) → ContractAddress
// Returns created TBA address
```

## Error Handling

Common error reasons include:
- `EVENT_ENDED`: Action attempted after event conclusion
- `INSUFFICIENT_BALANCE`: Insufficient STRK for ticket purchase
- `NOT_EVENT_ORGANIZER`: Unauthorized organizer action
- `EVENT_SOLD_OUT`: No tickets remaining

## Security

- Inherits OpenZeppelin AccessControl for role management
- Upgradeable contract pattern
- STRK token transfers use ERC20 `transferFrom` with allowance checks
- Event-specific role isolation prevents cross-event interference

## Dependencies

- OpenZeppelin Cairo Contracts v0.8
- Token Bound Accounts Registry
- StarkNet SRc5 Standard

## License

MIT License - See [SPDX-License-Identifier: MIT] in contract header

---

**Note**: Address constants (TBA_REGISTRY_CLASS_HASH, STRK_TOKEN_ADDRESS etc.) should be updated according to deployment network.