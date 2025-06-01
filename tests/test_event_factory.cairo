//*//////////////////////////////////////////////////////////////////////////
//                                 IMPORTS
//////////////////////////////////////////////////////////////////////////*//
use starknet::{ContractAddress, get_block_timestamp, get_tx_info};
use snforge_std::{
    declare, ContractClassTrait, DeclareResultTrait, start_cheat_caller_address,
    stop_cheat_caller_address,
};
use core::{pedersen::PedersenTrait, hash::HashStateTrait};
use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
use token_bound_accounts::interfaces::IRegistry::{
    IRegistryDispatcher, IRegistryLibraryDispatcher, IRegistryDispatcherTrait
};
use crowd_pass::{
    interfaces::{
        i_event_factory::{EventData, IEventFactoryDispatcher, IEventFactoryDispatcherTrait},
        i_ticket_721::{ITicket721Dispatcher, ITicket721DispatcherTrait}
    }
};

//*//////////////////////////////////////////////////////////////////////////
//                                 CONSTANTS
//////////////////////////////////////////////////////////////////////////*//
const STRK_TOKEN_ADDR: felt252 = 0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d;
const TICKET_NFT_CLASS_HASH: felt252 =
    0x01a6143d240fc4bfe546698326e56089d8345c790765fd190d495b3b19144074;
const TBA_REGISTRY_CLASS_HASH: felt252 =
    0x2cbf50931c7ec9029c5188985ea5fa8aedc728d352bde12ec889c212f0e8b3;
const TBA_REGISTRY_CONTRACT_ADDRESS: felt252 =
    0x41f87c7b00c3fb50cc7744f896f2d3438414be33912bd24f17318c9f48523a1;
const TBA_ACCOUNTV3_CLASS_HASH: felt252 =
    0x29d2a1b11dd97289e18042502f11356133a2201dd19e716813fb01fbee9e9a4;

const ADMIN: felt252 = 'admin';
const ORGANIZER: felt252 = 'organizer';
const ACCOUNT1: felt252 = 1234;

const STRK_WHALE: felt252 = 0x03119564DDE82cc1319aEb21506f6bc9c3e3061BaAdb63ddFeC3410A69C11F86;

//*//////////////////////////////////////////////////////////////////////////
//                                   SETUP
//////////////////////////////////////////////////////////////////////////*//
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

fn create_event() -> (ContractAddress, EventData, ITicket721Dispatcher) {
    let event_factory_contract = declare("EventFactory").unwrap().contract_class();
    let calldata = array![ADMIN];
    let (event_factory_address, _) = event_factory_contract.deploy(@calldata).unwrap();
    let event_factory = IEventFactoryDispatcher { contract_address: event_factory_address };

    start_cheat_caller_address(event_factory_address, ORGANIZER.try_into().unwrap());

    let name = "Test Event";
    let symbol = "TEST";
    let uri = "ipfs://test-uri-metadata-hash";
    let start_date: u64 = get_block_timestamp() + 86400; // 1 day later
    let end_date: u64 = start_date + 172800; // 2 days later
    let total_tickets: u256 = 100;
    let ticket_price: u256 = 1000000000000000000; // 1 token 

    let event = event_factory
        .create_event(name, symbol, uri, start_date, end_date, total_tickets, ticket_price);

    let ticket_address: ContractAddress = event.ticket_address;
    let ticket = ITicket721Dispatcher { contract_address: ticket_address };

    println!("Ticket address: {:?}", ticket_address);
    println!("Ticket total supply: {:?}", ticket.total_supply());

    (event_factory_address, event, ticket)
}

//*//////////////////////////////////////////////////////////////////////////
//                                   TESTS
//////////////////////////////////////////////////////////////////////////*//
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
    assert(event.organizer == ORGANIZER.try_into().unwrap(), 'Invalid organizer');
    assert(event.start_date <= get_block_timestamp() + 86400, 'Invalid start date');
    assert(event.end_date == event.start_date + 172800, 'Invalid end date');
    assert(event.total_tickets == 100, 'Invalid total tickets');
    assert(event.ticket_price == 1000000000000000000, 'Invalid ticket price');
    assert(ticket.total_supply() == 0, 'Invalid total supply');
}

#[test]
#[fork("SEPOLIA_LATEST")]
#[should_panic(expected: 'Allowance is not enough')]
fn should_panic_purchase_ticket_without_approval() {
    // prank organizer and create event
    let (event_factory_address, _, _) = create_event();
    let event_factory = IEventFactoryDispatcher { contract_address: event_factory_address };

    let tba_address = event_factory.purchase_ticket(1);
}

#[test]
#[fork("SEPOLIA_LATEST")]
fn test_purchase_ticket() {
    // prank organizer and create event
    let (event_factory_address, event, ticket) = create_event();
    let event_factory = IEventFactoryDispatcher { contract_address: event_factory_address };

    // stop organizer prank
    stop_cheat_caller_address(event_factory_address);

    // import strk token
    let strk_address: ContractAddress = STRK_TOKEN_ADDR.try_into().unwrap();
    let strk = IERC20Dispatcher { contract_address: strk_address };

    // approve strk token
    start_cheat_caller_address(strk_address, STRK_WHALE.try_into().unwrap());
    strk.approve(event_factory_address, 1000000000000000000 + ((1000000000000000000 * 3) / 100));
    stop_cheat_caller_address(strk_address);

    // purchase ticket
    start_cheat_caller_address(event_factory_address, STRK_WHALE.try_into().unwrap());
    let tba_address = event_factory.purchase_ticket(1);
    stop_cheat_caller_address(event_factory_address);

    let tba_registry = IRegistryLibraryDispatcher {
        class_hash: TBA_REGISTRY_CLASS_HASH.try_into().unwrap()
    };
    println!("TBA address: {:?}", tba_address);

    let derived_tba_address = tba_registry
        .get_account(
            TBA_ACCOUNTV3_CLASS_HASH.try_into().unwrap(),
            event.ticket_address,
            ticket.total_supply(),
            ticket.total_supply().try_into().unwrap(),
            get_tx_info().chain_id
        );
    println!("Ticket address: {:?}", event.ticket_address);
    println!("Token ID: {:?}", ticket.total_supply());
    println!("Chain ID: {:?}", get_tx_info().chain_id);
    println!("Derived TBA address: {:?}", derived_tba_address);

    assert(ticket.balance_of(STRK_WHALE.try_into().unwrap()) == 1, 'Invalid ticket balance');
    assert(ticket.total_supply() == 1, 'Invalid total supply');
    assert(
        strk.balance_of(event_factory_address) == 1000000000000000000
            + ((1000000000000000000 * 3) / 100),
        'Invalid contract balance'
    );
    assert(tba_address == derived_tba_address, 'Invalid TBA address');
}

#[test]
#[fork("SEPOLIA_LATEST")]
fn test_cancel_event() {
    let (event_factory_address, _, _) = create_event();
    let event_factory = IEventFactoryDispatcher { contract_address: event_factory_address };

    let event_canceled = event_factory.cancel_event(1);
    let event_data = event_factory.get_event(1);

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


