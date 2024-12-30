// SPDX-License-Identifier: MIT
#[starknet::contract]
pub mod EventFactory {
    //*//////////////////////////////////////////////////////////////////////////
    //                                 IMPORTS
    //////////////////////////////////////////////////////////////////////////*//
    use core::num::traits::zero::Zero;
    use starknet::{
        ContractAddress, SyscallResultTrait, get_block_timestamp, get_caller_address,
        get_contract_address, class_hash::ClassHash, account::Call,
        syscalls::{deploy_syscall, call_contract_syscall},
        storage::{
            Map, StoragePointerReadAccess, StoragePointerWriteAccess, StorageMapReadAccess,
            StorageMapWriteAccess, StoragePathEntry,
        },
    };
    use token_bound_accounts::{
        interfaces::IAccountV3::{IAccountV3LibraryDispatcher, IAccountV3DispatcherTrait},
        utils::array_ext::ArrayExt,
    };
    use openzeppelin::{
        introspection::src5::SRC5Component,
        token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait},
        access::accesscontrol::{AccessControlComponent, DEFAULT_ADMIN_ROLE},
        upgrades::{interface::IUpgradeable, UpgradeableComponent},
    };
    use crowd_pass::{
        errors::Errors,
        interfaces::{
            i_event_factory::{EventData, IEventFactory},
            i_ticket_721::{ITicket721Dispatcher, ITicket721DispatcherTrait},
            // i_multicall::IMultiCall,
        },
    };

    //*//////////////////////////////////////////////////////////////////////////
    //                                COMPONENTS
    //////////////////////////////////////////////////////////////////////////*//
    component!(path: SRC5Component, storage: src5, event: SRC5Event);
    component!(path: AccessControlComponent, storage: accesscontrol, event: AccessControlEvent);
    component!(path: UpgradeableComponent, storage: upgradeable, event: UpgradeableEvent);

    //*//////////////////////////////////////////////////////////////////////////
    //                                  EVENTS
    //////////////////////////////////////////////////////////////////////////*//
    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        EventCreated: EventCreated,
        EventUpdated: EventUpdated,
        EventCanceled: EventCanceled,
        TicketPurchased: TicketPurchased,
        TicketRecliamed: TicketRecliamed,
        #[flat]
        SRC5Event: SRC5Component::Event,
        #[flat]
        AccessControlEvent: AccessControlComponent::Event,
        #[flat]
        UpgradeableEvent: UpgradeableComponent::Event,
    }

    #[derive(Drop, starknet::Event)]
    struct EventCreated {
        id: u256,
        organizer: ContractAddress
    }

    #[derive(Drop, starknet::Event)]
    struct EventUpdated {
        id: u256,
        start_date: u64,
        end_date: u64
    }

    #[derive(Drop, starknet::Event)]
    struct EventCanceled {
        id: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct TicketPurchased {
        event_id: u256,
        buyer: ContractAddress,
        amount: u256
    }

    #[derive(Drop, starknet::Event)]
    struct TicketRecliamed {
        event_id: u256,
        tba_acct: ContractAddress,
        amount: u256
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  STORAGE
    //////////////////////////////////////////////////////////////////////////*//
    #[storage]
    struct Storage {
        event_count: u256,
        events: Map<u256, EventData>,
        user_event_token_id: Map<u256, Map<ContractAddress, u256>>,
        strk_token_address: ContractAddress,
        ticket_721_class_hash: ClassHash,
        tba_registry_address: ContractAddress,
        tba_accountv3_class_hash: ClassHash,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        #[substorage(v0)]
        accesscontrol: AccessControlComponent::Storage,
        #[substorage(v0)]
        upgradeable: UpgradeableComponent::Storage,
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*//
    #[constructor]
    fn constructor(
        ref self: ContractState,
        strk_token_address: ContractAddress,
        ticket_721_class_hash: ClassHash,
        tba_registry_address: ContractAddress,
        tba_accountv3_class_hash: ClassHash,
    ) {
        self.strk_token_address.write(strk_token_address);
        self.ticket_721_class_hash.write(ticket_721_class_hash);
        self.tba_registry_address.write(tba_registry_address);
        self.tba_accountv3_class_hash.write(tba_accountv3_class_hash);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                             EVENT FACTORY IMPL
    //////////////////////////////////////////////////////////////////////////*//
    #[abi(embed_v0)]
    impl EventContractImpl of IEventFactory<ContractState> {
        // ------------------ WRITE FUNCTIONS -----------------------
        fn create_event(
            ref self: ContractState,
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
        ) -> bool {
            let caller = get_caller_address();
            let event_count = self.event_count.read() + 1;
            let address_this = get_contract_address();

            // assert not zero ContractAddress
            assert(caller.is_non_zero(), Errors::ZERO_ADDRESS_CALLER);

            // deploy ticket721 contract
            let event_ticket = deploy_syscall(
                self.ticket_721_class_hash.read(),
                0,
                array![address_this.into(), address_this.into()].span(),
                true,
            );

            let (event_ticket_addr, _) = event_ticket.unwrap_syscall();

            // initialize ticket721 contract
            let ticket721_contract = ITicket721Dispatcher { contract_address: event_ticket_addr };

            ticket721_contract.initialize(name, symbol, uri,);

            // new event struct instance
            let event_instance = EventData {
                id: event_count,
                organizer: caller,
                ticket_addr: event_ticket_addr,
                description: description,
                location: location,
                created_at: get_block_timestamp(),
                updated_at: 0,
                start_date: start_date,
                end_date: end_date,
                category: category,
                total_tickets: total_tickets,
                tickets_sold: 0,
                ticket_price: ticket_price,
                is_canceled: false,
            };

            // Map event_id to new_event
            self.events.entry(event_count).write(event_instance);

            // Update event count
            self.event_count.write(event_count);

            // emit event for event creation
            self.emit(EventCreated { id: event_count, organizer: caller });

            true
        }

        fn update_event(
            ref self: ContractState,
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
        ) -> bool {
            let caller = get_caller_address();
            let event_count = self.event_count.read();
            let mut event_instance = self.events.entry(event_id).read();

            assert(event_id <= event_count, Errors::NOT_CREATED);
            // assert not zeroAddr caller
            assert(caller.is_non_zero(), Errors::ZERO_ADDRESS_CALLER);
            // assert caller is event organizer
            assert(caller == event_instance.organizer, Errors::NOT_ORGANIZER);
            // assert event has not ended
            assert(event_instance.end_date > get_block_timestamp(), Errors::EVENT_ENDED);

            // update event here
            event_instance.start_date = start_date;
            event_instance.end_date = end_date;
            event_instance.total_tickets = total_tickets;
            event_instance.ticket_price = ticket_price;
            event_instance.updated_at = get_block_timestamp();

            self.events.entry(event_id).write(event_instance);

            self.emit(EventUpdated { id: event_id, start_date: start_date, end_date: end_date });

            true
        }

        fn cancel_event(ref self: ContractState, event_id: u256) -> bool {
            let caller = get_caller_address();
            let event_count = self.event_count.read();
            let organizer = self.events.entry(event_id).read().organizer;
            let mut event_instance = self.events.entry(event_id).read();

            assert(event_id <= event_count, Errors::NOT_CREATED);
            // assert not zeroAddr caller
            assert(caller.is_non_zero(), Errors::ZERO_ADDRESS_CALLER);
            // assert caller is event organizer
            assert(caller == organizer, Errors::NOT_ORGANIZER);
            // assert event has not ended
            assert(event_instance.end_date > get_block_timestamp(), Errors::EVENT_ENDED);

            // cancel event here
            event_instance.is_canceled = true;
            self.events.entry(event_id).write(event_instance);

            self.emit(EventCanceled { id: event_id });

            true
        }

        fn purchase_ticket(ref self: ContractState, event_id: u256) {
            let caller: ContractAddress = get_caller_address();
            let event_count: u256 = self.event_count.read();
            let address_this: ContractAddress = get_contract_address();

            let mut event_instance = self.events.entry(event_id).read();

            let strk_erc20_address = self.strk_token_address.read();

            let strk_erc20_contract = IERC20Dispatcher { contract_address: strk_erc20_address };

            // assert caler is nit addr 0
            assert(caller.is_non_zero(), Errors::ZERO_ADDRESS_CALLER);

            // assert is_valid event
            assert(event_id < event_count, Errors::NOT_CREATED);

            // verify if token caller has enough strk for the ticket_price
            assert(
                strk_erc20_contract.balance_of(caller) >= event_instance.ticket_price,
                Errors::INSUFFICIENT_BALANCE
            );

            let event_ticket_price: u256 = event_instance.ticket_price;

            let approve_calldata_array: Array<felt252> = array![
                address_this.into(), event_ticket_price.try_into().unwrap()
            ];

            // Approve STRK token to this contract
            let approve_call = Call {
                to: strk_erc20_address,
                selector: selector!("approve"), //strk_erc20_contract.approve().selector,
                calldata: approve_calldata_array.span(),
            };

            let transfer_calldata_array: Array<felt252> = array![
                caller.into(), address_this.into(), event_ticket_price.try_into().unwrap()
            ];

            // Transfer STRK from caller to this contract
            let transfer_call = Call {
                to: strk_erc20_address,
                selector: selector!("transfer_from"), //strk_erc20_contract.transfer_from.selector,
                calldata: transfer_calldata_array.span(),
            };

            let calls = array![approve_call, transfer_call];

            // execute multiple calls
            let mut result: Array<Span<felt252>> = ArrayTrait::new();
            let mut calls = calls;
            let mut index = 0;

            loop {
                match calls.pop_front() {
                    Option::Some(call) => {
                        match call_contract_syscall(call.to, call.selector, call.calldata) {
                            Result::Ok(mut retdata) => {
                                result.append(retdata);
                                index += 1;
                            },
                            Result::Err(err) => {
                                let mut data = array!['multicall-failed', index];
                                data.append_all(err.span());
                                panic(data);
                            }
                        }
                    },
                    Option::None(_) => { break (); }
                };
            };

            // transfer strk from callers address to  smart contract
            // strk_erc20_contract.transfer_from(caller, address_this, event_ticket_price);

            // mint the nft ticket to the user
            let event_ticket_address = event_instance.ticket_addr;
            let ticket_nft = ITicket721Dispatcher { contract_address: event_ticket_address };
            ticket_nft.safe_mint(caller);

            // deploy the ticket721 tokenbound account
            // let tba_account = IAccountV3LibraryDispatcher {
            //     class_hash: self.tba_accountv3_class_hash.read()
            // };

            let tba_constructor_calldata: Array<felt252> = array![
                event_ticket_address.into(),
                event_id.try_into().unwrap(),
                self.tba_registry_address.read().into(),
                self.tba_accountv3_class_hash.read().into(),
                event_id.try_into().unwrap(),
            ];

            let tba_account = deploy_syscall(
                self.tba_accountv3_class_hash.read(), 0, tba_constructor_calldata.span(), true,
            );

            // update tickets sold
            let tickets_sold = event_instance.tickets_sold + 1;
            event_instance.tickets_sold = tickets_sold;

            // update legacymap with user token_id
            self.user_event_token_id.entry(event_id).entry(caller).write(tickets_sold);

            // event_instance.tickets_sold = tickets_sold;

            // increase ticket_sold count from event instance
            self.events.entry(event_id).write(event_instance);

            // emit event for ticket purchase
            self
                .emit(
                    TicketPurchased {
                        event_id: event_id, buyer: caller, amount: event_ticket_price
                    }
                );
        }

        // -------------- GETTER FUNCTIONS -----------------------

        fn get_all_events(self: @ContractState) -> Array<EventData> {
            let mut events = array![];
            let _count = self.event_count.read();
            let mut i: u256 = 1;

            while i < _count + 1 {
                let event: EventData = self.events.entry(i).read();
                events.append(event);
                i += 1;
            };

            events
        }

        fn get_event(self: @ContractState, event_id: u256) -> EventData {
            self.events.entry(event_id).read()
        }

        fn get_event_count(self: @ContractState) -> u256 {
            self.event_count.read()
        }
    }

    #[abi(embed_v0)]
    impl AccessControlImpl =
        AccessControlComponent::AccessControlImpl<ContractState>;
    #[abi(embed_v0)]
    impl AccessControlCamelImpl =
        AccessControlComponent::AccessControlCamelImpl<ContractState>;

    //*//////////////////////////////////////////////////////////////////////////
    //                              UPGRADEABLE IMPL
    //////////////////////////////////////////////////////////////////////////*//
    #[abi(embed_v0)]
    impl UpgradeableImpl of IUpgradeable<ContractState> {
        fn upgrade(ref self: ContractState, new_class_hash: ClassHash) {
            self.accesscontrol.assert_only_role(DEFAULT_ADMIN_ROLE);
            self.upgradeable.upgrade(new_class_hash);
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                             INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*//
    impl AccessControlInternalImpl = AccessControlComponent::InternalImpl<ContractState>;
    impl UpgradeableInternalImpl = UpgradeableComponent::InternalImpl<ContractState>;
    // #[generate_trait]
// pub impl MultiCallImpl of IMultiCallTrait<ContractState> {
//     // Internal function to execute multiple calls
//     fn _multicalls(ref self: ContractState, mut calls: Array<Call>) -> Array<Span<felt252>> {
//         let mut result: Array<Span<felt252>> = ArrayTrait::new();
//         let mut calls = calls;
//         let mut index = 0;

    //         loop {
//             match calls.pop_front() {
//                 Option::Some(call) => {
//                     match call_contract_syscall(call.to, call.selector, call.calldata) {
//                         Result::Ok(mut retdata) => {
//                             result.append(retdata);
//                             index += 1;
//                         },
//                         Result::Err(err) => {
//                             let mut data = array!['multicall-failed', index];
//                             data.append_all(err.span());
//                             panic(data);
//                         }
//                     }
//                 },
//                 Option::None(_) => { break (); }
//             };
//         };
//         result
//     }
// }
}
