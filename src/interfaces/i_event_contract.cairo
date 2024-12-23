// SPDX-License-Identifier: MIT
use starknet::ContractAddress;

#[starknet::interface]
pub trait IEventContract<TContractState> {
    fn create_event(
        ref self: TContractState,
        _name: ByteArray,
        _description: ByteArray,
        _image: ByteArray,
        _location: ByteArray,
        _category: felt252,
        _event_type: felt252,
        _start_date: u64,
        _end_date: u64,
        _ticket_price: u256,
        _total_tickets: u256,
    ) -> bool;
    fn get_all_events(self: @TContractState) -> Array<Events>;
    fn cancel_event(ref self: TContractState, _event_id: u32);
    fn purchase_ticket(ref self: TContractState, _event_id: u32);
    fn get_event(self: @TContractState, _event_id: u32) -> Events;
    fn get_event_count(self: @TContractState) -> u32;
    // fn resale_ticket (ref self : TContractState, event_id: u32) -> bool;
// fn refund_ticket (ref self : TContractState, event_id: u32) -> bool;
}

#[derive(Drop, Serde, starknet::Store)]
pub struct Events {
    id: u32,
    name: ByteArray,
    description: ByteArray,
    image: ByteArray,
    location: ByteArray,
    organizer: ContractAddress,
    event_type: felt252,
    category: felt252,
    total_tickets: u256,
    tickets_sold: u256,
    ticket_price: u256,
    start_date: u64,
    end_date: u64,
    is_canceled: bool,
    event_ticket_addr: ContractAddress,
}

#[derive(Drop)]
pub enum EventType {
    free,
    paid,
}
