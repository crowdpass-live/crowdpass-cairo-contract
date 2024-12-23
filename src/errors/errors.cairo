pub mod Errors {
    pub const ZERO_AMOUNT: felt252 = 'amount cannot be zero';
    pub const ZERO_ADDRESS_CALLER: felt252 = 'Caller cannot be zero addr';
    pub const ZERO_ADDRESS_OWNER: felt252 = 'Owner cannot be zero addr';
    pub const NOT_ORGANIZER: felt252 = 'Caller not organizer';
    pub const NOT_CREATED: felt252 = 'event not yet registered';
    pub const EVENT_ENDED: felt252 = 'event has ended';
    pub const EVENT_NOT_CANCELED: felt252 = 'event not canceled';
    pub const INSUFFICIENT_AMOUNT: felt252 = 'balance is low';
    pub const LOW_TOKEN_ALLOWANCE: felt252 = 'token allowance too low';
    pub const NOT_TICKET_HOLDER: felt252 = 'balance_of less than 1';
    pub const NOT_TICKET_OWNER: felt252 = 'not ticket owner';
    pub const ALREADY_MINTED: felt252 = 'recipient already has a ticket';
    pub const REFUND_CLIAMED: felt252 = 'refund cliamed';
}
