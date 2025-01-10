use starknet::{ContractAddress, get_block_timestamp};

use snforge_std::{
    declare, ContractClassTrait, DeclareResultTrait, start_cheat_caller_address,
    stop_cheat_caller_address
};
use crowd_pass::{
    interfaces::{
        i_event_factory::{EventData, IEventFactoryDispatcher, IEventFactoryDispatcherTrait},
        i_ticket_721::{ITicket721Dispatcher, ITicket721DispatcherTrait}
    }
};

const STRK_TOKEN_ADDR: felt252 = 0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d;
const TICKET_NFT_CLASS_HASH: felt252 =
    0x03ba1071218d3fb88a76489f68510c7dd1c602d29fa0a9ece0a54da616a96860;
const TBA_REGISTRY_CLASS_HASH: felt252 =
    0x2cbf50931c7ec9029c5188985ea5fa8aedc728d352bde12ec889c212f0e8b3;
const TBA_ACCOUNTV3_CLASS_HASH: felt252 =
    0x29d2a1b11dd97289e18042502f11356133a2201dd19e716813fb01fbee9e9a4;

const ACCOUNT: felt252 = 1234;
const ACCOUNT1: felt252 = 5678;

fn deploy_contract(name: ByteArray) -> ContractAddress {
    let contract = declare(name).unwrap().contract_class();
    let (contract_address, _) = contract.deploy(@ArrayTrait::new()).unwrap();
    contract_address
}

fn deploy_event_factory() -> ContractAddress {
    let contract = declare("EventFactory").unwrap().contract_class();
    let calldata = array![
        ACCOUNT,
        STRK_TOKEN_ADDR,
        TICKET_NFT_CLASS_HASH,
        TBA_REGISTRY_CLASS_HASH,
        TBA_ACCOUNTV3_CLASS_HASH
    ];
    let (event_factory_address, _) = contract.deploy(@calldata).unwrap();

    event_factory_address
}

fn create_event() -> (ContractAddress, EventData, ITicket721Dispatcher,) {
    let event_factory_address = deploy_event_factory();
    let event_factory = IEventFactoryDispatcher { contract_address: event_factory_address };

    start_cheat_caller_address(event_factory_address, ACCOUNT.try_into().unwrap());

    let event = event_factory
        .create_event(
            "Event Name",
            "Event Symbol",
            "Event URI",
            "Event Description",
            "Event Location",
            get_block_timestamp(),
            get_block_timestamp() + 86400,
            100,
            100
        );

    let evt_addr: ContractAddress = event.ticket_addr;
    let event_ticket = ITicket721Dispatcher { contract_address: evt_addr };
    (event_factory_address, event, event_ticket)
}

#[test]
#[fork("SEPOLIA_LATEST")]
fn test_create_event() {
    let (event_factory_address, event, event_ticket) = create_event();
    let event_factory = IEventFactoryDispatcher { contract_address: event_factory_address };

    // assert(event, 'Event creation failed');
    assert_eq!(event_factory.get_event_count(), 1);
    assert_eq!(event.id, 1);
    assert_eq!(event.organizer, ACCOUNT.try_into().unwrap());
    assert_eq!(event.description, "Event Description");
    assert_eq!(event.location, "Event Location");
    assert(event.start_date <= get_block_timestamp(), 'Invalid start date');
    assert(event.end_date <= get_block_timestamp() + 86400, 'Invalid end date');
    assert_eq!(event.total_tickets, 100);
    assert_eq!(event.ticket_price, 100);
    assert_eq!(event_ticket.total_supply(), 0);
    assert_eq!(event_ticket.name(), "Event Name");
    assert_eq!(event_ticket.symbol(), "Event Symbol");
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
#[should_panic(expected: 'Caller not main organizer')]
fn test_not_main_organizer_cancel_event() {
    let (event_factory_address, _, _) = create_event();
    let event_factory = IEventFactoryDispatcher { contract_address: event_factory_address };

    event_factory.add_organizer(1, ACCOUNT1.try_into().unwrap());
    stop_cheat_caller_address(event_factory_address);

    start_cheat_caller_address(event_factory_address, ACCOUNT1.try_into().unwrap());

    let event_canceled = event_factory.cancel_event(1);
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


