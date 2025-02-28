//*//////////////////////////////////////////////////////////////////////////
//                                  ERRORS
//////////////////////////////////////////////////////////////////////////*//
pub mod Errors {
    // EventFactory
    pub const ZERO_AMOUNT: felt252 = 'Amount cannot be zero';
    pub const ZERO_ADDRESS_CALLER: felt252 = 'Caller cannot be zero address';
    pub const ZERO_ADDRESS_OWNER: felt252 = 'Owner cannot be zero address';
    pub const NOT_EVENT_ORGANIZER: felt252 = 'Caller not main organizer';
    pub const EVENT_NOT_CREATED: felt252 = 'Event not yet created';
    pub const EVENT_STARTED: felt252 = 'Event has started';
    pub const EVENT_ENDED: felt252 = 'Event has ended';
    pub const EVENT_CANCELED: felt252 = 'Event is canceled';
    pub const EVENT_NOT_CANCELED: felt252 = 'Event is not canceled';
    pub const EVENT_NOT_ENDED: felt252 = 'Event is not ended';
    pub const EVENT_NOT_STARTED: felt252 = 'Event is not started';
    pub const EVENT_SOLD_OUT: felt252 = 'Event is sold out';
    pub const INSUFFICIENT_BALANCE: felt252 = 'Balance is low';
    pub const LOW_TOKEN_ALLOWANCE: felt252 = 'Token allowance too low';
    pub const NOT_TICKET_HOLDER: felt252 = 'Balance_of less than 1';
    pub const NOT_TICKET_OWNER: felt252 = 'Not ticket owner';
    pub const ALREADY_MINTED: felt252 = 'Recipient already has a ticket';
    pub const REFUND_CLIAMED: felt252 = 'Refund cliamed';
    pub const REFUND_FAILED: felt252 = 'Refund failed';
    pub const CALLER_NOT_TBA: felt252 = 'Caller not TBA address';
    // TicketNFT
    pub const NOT_NFT_OWNER: felt252 = 'Not nft owner';
    pub const ALREADY_INITIALIZED: felt252 = 'Already initialized';
}
