use starknet::ContractAddress;

use snforge_std::{
    declare, ContractClassTrait, DeclareResultTrait, start_cheat_caller_address,
    stop_cheat_caller_address
};
use openzeppelin::token::erc721::{
    extensions::erc721_enumerable::interface::{
        IERC721EnumerableDispatcher, IERC721EnumerableDispatcherTrait
    },
    interface::{ERC721ABIDispatcher, ERC721ABIDispatcherTrait}
};
use crowd_pass::{
    // event_factory::EventFactory, tickets::{ticket_factory::TicketFactory, ticket_721::Ticket721},
    interfaces::{
        i_event_factory::{
            IEventFactory, EventData, IEventFactoryDispatcher, IEventFactoryDispatcherTrait
        },
        i_ticket_factory::{ITicketFactoryDispatcher, ITicketFactoryDispatcherTrait},
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

fn deploy_contract(name: ByteArray) -> ContractAddress {
    let contract = declare(name).unwrap().contract_class();
    let (contract_address, _) = contract.deploy(@ArrayTrait::new()).unwrap();
    contract_address
}

fn setup() -> (ContractAddress, IEventFactoryDispatcher) {
    let contract = declare("EventFactory").unwrap().contract_class();
    let calldata = array![
        ACCOUNT,
        STRK_TOKEN_ADDR,
        TICKET_NFT_CLASS_HASH,
        TBA_REGISTRY_CLASS_HASH,
        TBA_ACCOUNTV3_CLASS_HASH
    ];
    let (event_factory_address, _) = contract.deploy(@calldata).unwrap();

    let event_factory = IEventFactoryDispatcher { contract_address: event_factory_address };
    (event_factory_address, event_factory)
}

fn setup_create_event() {
    let (event_factory_address, event_factory) = setup();

    start_cheat_caller_address(event_factory_address, ACCOUNT.try_into().unwrap());

    let event = event_factory
        .create_event(
            "Event Name",
            "Event Symbol",
            "Event URI",
            "Event Description",
            "Event Location",
            1630000000,
            1630000000,
            100,
            100
        );

    let event_data: EventData = event_factory.get_event(1);
    let evt_addr: ContractAddress = event_data.ticket_addr;
    let event_ticket = ITicket721Dispatcher { contract_address: evt_addr };
}

#[test]
#[fork("SEPOLIA_LATEST")]
fn test_create_event() {
    let (event_factory_address, event_factory) = setup();

    start_cheat_caller_address(event_factory_address, ACCOUNT.try_into().unwrap());

    let event = event_factory
        .create_event(
            "Event Name",
            "Event Symbol",
            "Event URI",
            "Event Description",
            "Event Location",
            1630000000,
            1630000000,
            100,
            100
        );

    let event_data: EventData = event_factory.get_event(1);
    let evt_addr: ContractAddress = event_data.ticket_addr;
    let event_ticket = ITicket721Dispatcher { contract_address: evt_addr };

    assert(event, 'Event creation failed');
    assert(event_factory.get_event_count() == 1, 'Invalid event count');
    assert(event_data.id == 1, 'Invalid event id');
    assert(event_data.organizer == ACCOUNT.try_into().unwrap(), 'Invalid organizer');
    assert(event_data.description == "Event Description", 'Invalid description');
    assert(event_data.location == "Event Location", 'Invalid location');
    assert(event_data.start_date == 1630000000, 'Invalid start date');
    assert(event_data.end_date == 1630000000, 'Invalid end date');
    assert(event_data.total_tickets == 100, 'Invalid total tickets');
    assert(event_data.ticket_price == 100, 'Invalid ticket price');
    assert(event_ticket.total_supply() == 0, 'Invalid total supply');
    assert(event_ticket.name() == "Event Name", 'Invalid name');
    assert(event_ticket.symbol() == "Event Symbol", 'Invalid symbol');
}

#[test]
#[fork("SEPOLIA_LATEST")]
fn test_cancel_event() {}
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


