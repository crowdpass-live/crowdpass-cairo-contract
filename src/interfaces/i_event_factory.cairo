// SPDX-License-Identifier: MIT
use starknet::ContractAddress;

#[starknet::interface]
pub trait IEventFactory<TContractState> {
    fn create_event(
        ref self: TContractState,
        name: ByteArray,
        symbol: ByteArray,
        uri: ByteArray,
        description: ByteArray,
        location: ByteArray,
        category: felt252,
        event_type: felt252,
        start_date: u64,
        end_date: u64,
        total_tickets: u256,
        ticket_price: u256,
    ) -> bool;
    fn update_event(
        ref self: TContractState,
        event_id: u256,
        name: ByteArray,
        symbol: ByteArray,
        uri: ByteArray,
        description: ByteArray,
        location: ByteArray,
        category: felt252,
        event_type: felt252,
        start_date: u64,
        end_date: u64,
        total_tickets: u256,
        ticket_price: u256,
    ) -> bool;
    fn cancel_event(ref self: TContractState, event_id: u256) -> bool;
    fn purchase_ticket(ref self: TContractState, event_id: u256);
    fn get_all_events(self: @TContractState) -> Array<EventData>;
    fn get_event(self: @TContractState, event_id: u256) -> EventData;
    fn get_event_count(self: @TContractState) -> u256;
    // fn resale_ticket (ref self : TContractState, event_id: u32) -> bool;
// fn refund_ticket (ref self : TContractState, event_id: u32) -> bool;
}

#[derive(Drop, Serde, starknet::Store)]
pub struct EventData {
    pub id: u256,
    pub organizer: ContractAddress,
    pub description: ByteArray,
    pub ticket_addr: ContractAddress,
    pub location: ByteArray,
    pub created_at: u64,
    pub updated_at: u64,
    pub start_date: u64,
    pub end_date: u64,
    pub category: felt252,
    pub total_tickets: u256,
    pub tickets_sold: u256,
    pub ticket_price: u256,
    pub is_canceled: bool,
}
// #[derive(Drop)]
// pub enum EventType {
//     free,
//     paid,
// }


