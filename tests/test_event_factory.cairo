use starknet::{ContractAddress, get_block_timestamp};

use snforge_std::{
    declare, ContractClassTrait, DeclareResultTrait, start_cheat_caller_address,
    stop_cheat_caller_address
};
use core::{pedersen::PedersenTrait, hash::HashStateTrait};
use crowd_pass::{
    interfaces::{
        i_event_factory::{EventData, IEventFactoryDispatcher, IEventFactoryDispatcherTrait},
        i_ticket_721::{ITicket721Dispatcher, ITicket721DispatcherTrait}
    }
};

const STRK_TOKEN_ADDR: felt252 = 0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d;
const TICKET_NFT_CLASS_HASH: felt252 =
    0x02932c15f926119f4601b9914a38f7a9861effa19e3a7bfe3d14ce0528e6a908;
const TBA_REGISTRY_CLASS_HASH: felt252 =
    0x2cbf50931c7ec9029c5188985ea5fa8aedc728d352bde12ec889c212f0e8b3;
const TBA_REGISTRY_CONTRACT_ADDRESS: felt252 =
    0x41f87c7b00c3fb50cc7744f896f2d3438414be33912bd24f17318c9f48523a1;
const TBA_ACCOUNTV3_CLASS_HASH: felt252 =
    0x29d2a1b11dd97289e18042502f11356133a2201dd19e716813fb01fbee9e9a4;

const ACCOUNT: felt252 = 1234;
const ACCOUNT1: felt252 = 5678;

fn deploy_contract(name: ByteArray) -> ContractAddress {
    let contract = declare(name).unwrap().contract_class();
    let (contract_address, _) = contract.deploy(@ArrayTrait::new()).unwrap();
    contract_address
}

fn gen_event_hash(event_id: u256) -> felt252 {
    PedersenTrait::new(0).update('CROWD_PASS_EVENT').update(event_id.try_into().unwrap()).finalize()
}

fn gen_main_organizer_role(event_id: u256) -> felt252 {
    PedersenTrait::new(0).update('MAIN_ORGANIZER').update(gen_event_hash(event_id)).finalize()
}

fn create_event() -> (ContractAddress, EventData, ITicket721Dispatcher,) {
    let event_factory_contract = declare("EventFactory").unwrap().contract_class();
    let calldata = array![ACCOUNT];
    let (event_factory_address, _) = event_factory_contract.deploy(@calldata).unwrap();
    let event_factory = IEventFactoryDispatcher { contract_address: event_factory_address };

    start_cheat_caller_address(event_factory_address, ACCOUNT.try_into().unwrap());

    let name = "Test Event";
    let symbol = "TEST";
    let uri = "ipfs://test-uri-metadata-hash";
    let description = "Test Description";
    let location = "Test Location";
    let start_date: u64 = get_block_timestamp();
    let end_date: u64 = start_date + 86400; // 1 day later
    let total_tickets: u256 = 100;
    let ticket_price: u256 = 1000000000000000000; // 1 token 

    let event = event_factory
        .create_event(
            name,
            symbol,
            uri,
            description,
            location,
            start_date,
            end_date,
            total_tickets,
            ticket_price
        );

    let ticket_address: ContractAddress = event.ticket_address;
    let ticket = ITicket721Dispatcher { contract_address: ticket_address };
    (event_factory_address, event, ticket)
}

#[test]
#[fork("SEPOLIA_LATEST")]
fn test_create_event() {
    let (event_factory_address, event, ticket) = create_event();
    let event_factory = IEventFactoryDispatcher { contract_address: event_factory_address };

    assert(event_factory.get_event_count() == 1, 'Invalid event count');
    assert(event.id == 1, 'Invalid event id');
    assert(ticket.name() == "Test Event", 'Invalid event name');
    assert(ticket.symbol() == "TEST", 'Invalid event symbol');
    assert(ticket.base_uri() == "ipfs://test-uri-metadata-hash", 'Invalid event uri');
    assert(event.organizer == ACCOUNT.try_into().unwrap(), 'Invalid organizer');
    assert(event.description == "Test Description", 'Invalid description');
    assert(event.location == "Test Location", 'Invalid location');
    assert(event.start_date <= get_block_timestamp(), 'Invalid start date');
    assert(event.end_date == event.start_date + 86400, 'Invalid end date');
    assert(event.total_tickets == 100, 'Invalid total tickets');
    assert(event.ticket_price == 1000000000000000000, 'Invalid ticket price');
    assert(ticket.total_supply() == 0, 'Invalid total supply');
}

#[test]
#[fork("SEPOLIA_LATEST")]
fn test_cancel_event() {
    let (event_factory_address, _, _) = create_event();
    let event_factory = IEventFactoryDispatcher { contract_address: event_factory_address };

    let event_canceled = event_factory.cancel_event(1);
    let event_data: EventData = event_factory.get_event(1);

    assert(event_canceled, 'Event cancellation failed');
    assert(event_data.is_canceled == true, 'Event not canceled');
}

#[test]
#[fork("SEPOLIA_LATEST")]
#[should_panic(expected: 'Caller is missing role')]
fn should_panic_not_main_organizer_cancel_event() {
    let (event_factory_address, _, _) = create_event();
    let event_factory = IEventFactoryDispatcher { contract_address: event_factory_address };

    stop_cheat_caller_address(event_factory_address);

    start_cheat_caller_address(event_factory_address, ACCOUNT1.try_into().unwrap());

    event_factory.cancel_event(1);
}

#[test]
#[fork("SEPOLIA_LATEST")]
fn test_remove_organizer() {
    let (event_factory_address, _, _) = create_event();
    let event_factory = IEventFactoryDispatcher { contract_address: event_factory_address };

    event_factory.add_organizer(1, ACCOUNT1.try_into().unwrap());
}

#[test]
#[fork("SEPOLIA_LATEST")]
fn test_purchase_ticket() {
    let (event_factory_address, _, _) = create_event();
    let event_factory = IEventFactoryDispatcher { contract_address: event_factory_address };

    event_factory.add_organizer(1, ACCOUNT1.try_into().unwrap());
}
// #[test]
// fn test_increase_balance() {
//     let contract_address = deploy_contract("EventFactory");

//     let dispatcher = IHelloStarknetDispatcher { contract_address };

//     let balance_before = dispatcher.get_balance();
//     assert(balance_before == 0, 'Invalid balance');

//     dispatcher.increase_balance(42);

//     let balance_after = dispatcher.get_balance();
//     assert(balance_after == 42, 'Invalid balance');
// }

// #[test]
// #[feature("safe_dispatcher")]
// fn test_cannot_increase_balance_with_zero_value() {
//     let contract_address = deploy_contract("HelloStarknet");

//     let safe_dispatcher = IHelloStarknetSafeDispatcher { contract_address };

//     let balance_before = safe_dispatcher.get_balance().unwrap();
//     assert(balance_before == 0, 'Invalid balance');

//     match safe_dispatcher.increase_balance(0) {
//         Result::Ok(_) => core::panic_with_felt252('Should have panicked'),
//         Result::Err(panic_data) => {
//             assert(*panic_data.at(0) == 'Amount cannot be 0', *panic_data.at(0));
//         }
//     };
// }


