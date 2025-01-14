// SPDX-License-Identifier: MIT
#[starknet::contract]
pub mod EventFactory {
    //*//////////////////////////////////////////////////////////////////////////
    //                                 IMPORTS
    //////////////////////////////////////////////////////////////////////////*//
    use core::{num::traits::zero::Zero, pedersen::PedersenTrait, hash::HashStateTrait};
    use starknet::{
        ContractAddress, SyscallResultTrait, class_hash::ClassHash, get_block_timestamp,
        get_caller_address, get_contract_address, get_tx_info, syscalls::deploy_syscall,
        storage::{Map, StoragePointerReadAccess, StoragePointerWriteAccess, StoragePathEntry},
    };
    use openzeppelin::{
        introspection::src5::SRC5Component,
        token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait},
        access::accesscontrol::{AccessControlComponent, DEFAULT_ADMIN_ROLE},
        upgrades::{interface::IUpgradeable, UpgradeableComponent},
    };
    use token_bound_accounts::{
        interfaces::{IRegistry::{IRegistryLibraryDispatcher, IRegistryDispatcherTrait}},
        utils::array_ext::ArrayExt,
    };
    use crowd_pass::{
        errors::Errors,
        interfaces::{
            i_event_factory::{EventData, IEventFactory},
            i_ticket_721::{ITicket721Dispatcher, ITicket721DispatcherTrait},
        },
    };

    pub const STRK_TOKEN_ADDRESS: felt252 =
        0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d;

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
        #[flat]
        SRC5Event: SRC5Component::Event,
        #[flat]
        AccessControlEvent: AccessControlComponent::Event,
        #[flat]
        UpgradeableEvent: UpgradeableComponent::Event,
        EventCreated: EventCreated,
        EventUpdated: EventUpdated,
        EventCanceled: EventCanceled,
        TicketPurchased: TicketPurchased,
        TicketRecliamed: TicketRecliamed,
    }

    #[derive(Drop, starknet::Event)]
    struct EventCreated {
        #[key]
        id: u256,
        #[key]
        organizer: ContractAddress,
        ticket_address: ContractAddress
    }

    #[derive(Drop, starknet::Event)]
    struct EventUpdated {
        #[key]
        id: u256,
        start_date: u64,
        end_date: u64
    }

    #[derive(Drop, starknet::Event)]
    struct EventCanceled {
        #[key]
        id: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct TicketPurchased {
        #[key]
        event_id: u256,
        ticket_id: u256,
        #[key]
        buyer: ContractAddress,
        tba_address: ContractAddress,
        ticket_price: u256
    }

    #[derive(Drop, starknet::Event)]
    struct TicketRecliamed {
        #[key]
        event_id: u256,
        tba_acct: ContractAddress,
        amount: u256
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  STORAGE
    //////////////////////////////////////////////////////////////////////////*//
    #[storage]
    struct Storage {
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        #[substorage(v0)]
        accesscontrol: AccessControlComponent::Storage,
        #[substorage(v0)]
        upgradeable: UpgradeableComponent::Storage,
        event_count: u256,
        events: Map<u256, EventData>,
        event_ticket_balance: Map<u256, u256>,
        ticket_721_class_hash: felt252,
        tba_registry_class_hash: felt252,
        tba_accountv3_class_hash: felt252,
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*//
    #[constructor]
    fn constructor(
        ref self: ContractState,
        default_admin: felt252,
        ticket_721_class_hash: felt252,
        tba_registry_class_hash: felt252,
        tba_accountv3_class_hash: felt252,
    ) {
        self.accesscontrol.initializer();
        self.accesscontrol._grant_role(DEFAULT_ADMIN_ROLE, default_admin.try_into().unwrap());
        self.ticket_721_class_hash.write(ticket_721_class_hash);
        self.tba_registry_class_hash.write(tba_registry_class_hash);
        self.tba_accountv3_class_hash.write(tba_accountv3_class_hash);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                             EVENT FACTORY IMPL
    //////////////////////////////////////////////////////////////////////////*//
    #[abi(embed_v0)]
    impl EventFactoryImpl of IEventFactory<ContractState> {
        // ------------------ WRITE FUNCTIONS -----------------------
        fn create_event(
            ref self: ContractState,
            name: ByteArray,
            symbol: ByteArray,
            uri: ByteArray,
            description: ByteArray,
            location: ByteArray,
            start_date: u64,
            end_date: u64,
            total_tickets: u256,
            ticket_price: u256,
        ) -> EventData {
            let event = self
                ._create_event(
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

            event
        }

        fn update_event(
            ref self: ContractState,
            event_id: u256,
            name: ByteArray,
            symbol: ByteArray,
            uri: ByteArray,
            description: ByteArray,
            location: ByteArray,
            start_date: u64,
            end_date: u64,
            total_tickets: u256,
            ticket_price: u256,
        ) -> EventData {
            let main_organizer_role = self._gen_main_organizer_role(event_id);
            // assert caller has main organizer role
            self.accesscontrol.assert_only_role(main_organizer_role);

            let event = self
                ._update_event(
                    event_id,
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

            event
        }

        fn cancel_event(ref self: ContractState, event_id: u256) -> bool {
            let main_organizer_role = self._gen_main_organizer_role(event_id);
            // assert caller has main organizer role
            self.accesscontrol.assert_only_role(main_organizer_role);

            let event_canceled = self._cancel_event(event_id);

            event_canceled
        }

        fn add_organizer(ref self: ContractState, event_id: u256, organizer: ContractAddress) {
            let main_organizer_role = self._gen_main_organizer_role(event_id);
            // assert caller has main organizer role
            self.accesscontrol.assert_only_role(main_organizer_role);
            let event_hash = self._gen_event_hash(event_id);
            self._add_organizer(event_hash, organizer);
        }
        fn remove_organizer(ref self: ContractState, event_id: u256, organizer: ContractAddress) {
            let main_organizer_role = self._gen_main_organizer_role(event_id);
            // assert caller has main organizer role
            self.accesscontrol.assert_only_role(main_organizer_role);
            let event_hash = self._gen_event_hash(event_id);
            self._remove_organizer(event_hash, organizer);
        }

        fn purchase_ticket(ref self: ContractState, event_id: u256) -> ContractAddress {
            let tba_address = self._purchase_ticket(event_id);
            tba_address
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

    #[generate_trait]
    impl PrivateImpl of PrivateTrait {
        fn _gen_event_hash(self: @ContractState, event_id: u256) -> felt252 {
            PedersenTrait::new(0)
                .update('CROWD_PASS_EVENT')
                .update(event_id.try_into().unwrap())
                .finalize()
        }

        fn _gen_main_organizer_role(self: @ContractState, event_id: u256) -> felt252 {
            PedersenTrait::new(0)
                .update('MAIN_ORGANIZER')
                .update(self._gen_event_hash(event_id))
                .finalize()
        }

        fn _create_event(
            ref self: ContractState,
            name: ByteArray,
            symbol: ByteArray,
            uri: ByteArray,
            description: ByteArray,
            location: ByteArray,
            start_date: u64,
            end_date: u64,
            total_tickets: u256,
            ticket_price: u256,
        ) -> EventData {
            let caller = get_caller_address();
            let event_count = self.event_count.read() + 1;
            let address_this = get_contract_address();

            // create event role
            let event_hash = self._gen_event_hash(event_count);
            let main_organizer_role = self._gen_main_organizer_role(event_count);
            // grant caller main organizer role
            self.accesscontrol._grant_role(main_organizer_role, caller);
            // set main organizer role as the admin role for this event role
            self.accesscontrol.set_role_admin(event_hash, main_organizer_role);

            // deploy ticket721 contract
            let event_ticket = deploy_syscall(
                self.ticket_721_class_hash.read().try_into().unwrap(),
                event_hash,
                array![address_this.into(), address_this.into()].span(),
                true,
            );

            let (event_ticket_addr, _) = event_ticket.unwrap_syscall();

            // initialize ticket721 contract
            ITicket721Dispatcher { contract_address: event_ticket_addr }
                .initialize(name, symbol, uri,);

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
                total_tickets: total_tickets,
                ticket_price: ticket_price,
                is_canceled: false,
            };

            // Map event_id to new_event
            self.events.entry(event_count).write(event_instance);

            // Update event count
            self.event_count.write(event_count);

            // emit event for event creation
            self
                .emit(
                    EventCreated {
                        id: event_count, organizer: caller, ticket_address: event_ticket_addr
                    }
                );

            self.events.entry(event_count).read()
        }

        fn _update_event(
            ref self: ContractState,
            event_id: u256,
            name: ByteArray,
            symbol: ByteArray,
            uri: ByteArray,
            description: ByteArray,
            location: ByteArray,
            start_date: u64,
            end_date: u64,
            total_tickets: u256,
            ticket_price: u256,
        ) -> EventData {
            let mut event_instance = self.events.entry(event_id).read();
            // assert event has not ended
            assert(event_instance.end_date > get_block_timestamp(), Errors::EVENT_ENDED);
            // assert caller is the main organizer
            assert(get_caller_address() == event_instance.organizer, Errors::NOT_EVENT_ORGANIZER);

            let event_ticket = ITicket721Dispatcher {
                contract_address: event_instance.ticket_addr
            };

            // TODO: empty string or ByteArray might not equal to "".
            let empty_str = "";
            // update event ticket
            if name != empty_str || name != event_ticket.name() {
                event_ticket.update_name(name);
            }
            if symbol != empty_str || symbol != event_ticket.symbol() {
                event_ticket.update_symbol(symbol);
            }
            if uri != empty_str || uri != event_ticket.base_uri() {
                event_ticket.set_base_uri(uri);
            }
            // update event instance
            event_instance.description = description;
            event_instance.location = location;
            event_instance.updated_at = get_block_timestamp();
            event_instance.start_date = start_date;
            event_instance.end_date = end_date;
            event_instance.total_tickets = total_tickets;
            event_instance.ticket_price = ticket_price;

            self.events.entry(event_id).write(event_instance);

            self.emit(EventUpdated { id: event_id, start_date: start_date, end_date: end_date });

            self.events.entry(event_id).read()
        }

        fn _cancel_event(ref self: ContractState, event_id: u256) -> bool {
            // assert event has been created
            let event_count = self.event_count.read();
            assert(event_id <= event_count, Errors::EVENT_NOT_CREATED);

            let mut event_instance = self.events.entry(event_id).read();
            // assert caller is the main event organizer
            assert(get_caller_address() == event_instance.organizer, Errors::NOT_EVENT_ORGANIZER);
            // assert event has not ended
            assert(event_instance.end_date > get_block_timestamp(), Errors::EVENT_ENDED);

            // cancel event here
            event_instance.is_canceled = true;
            self.events.entry(event_id).write(event_instance);

            self.emit(EventCanceled { id: event_id });

            true
        }

        fn _add_organizer(
            ref self: ContractState, event_hash: felt252, organizer: ContractAddress
        ) {
            // grant role to caller
            self.accesscontrol.grant_role(event_hash, organizer);
        }

        fn _remove_organizer(
            ref self: ContractState, event_hash: felt252, organizer: ContractAddress
        ) {
            // revoke role from caller
            self.accesscontrol.revoke_role(event_hash, organizer);
        }

        fn _purchase_ticket(ref self: ContractState, event_id: u256) -> ContractAddress {
            let buyer: ContractAddress = get_caller_address();
            // assert caller is not address 0
            assert(buyer.is_non_zero(), Errors::ZERO_ADDRESS_CALLER);

            let event_count: u256 = self.event_count.read();
            // assert is_valid event
            assert(event_id <= event_count, Errors::EVENT_NOT_CREATED);

            let mut event_instance: EventData = self.events.entry(event_id).read();
            assert(!event_instance.is_canceled, Errors::EVENT_CANCELED);
            assert(event_instance.end_date > get_block_timestamp(), Errors::EVENT_ENDED);

            let strk_token = IERC20Dispatcher {
                contract_address: STRK_TOKEN_ADDRESS.try_into().unwrap()
            };
            // verify if caller has enough strk token for the ticket_price
            assert(
                strk_token.balance_of(buyer) > event_instance.ticket_price,
                Errors::INSUFFICIENT_BALANCE
            );

            let event_ticket_address = event_instance.ticket_addr;
            let event_ticket = ITicket721Dispatcher { contract_address: event_ticket_address };
            let ticket_id = event_ticket.total_supply() + 1;
            assert(event_instance.total_tickets <= ticket_id, Errors::EVENT_SOLD_OUT);

            let event_ticket_price = event_instance.ticket_price;

            // transfer the ticket price to the contract
            strk_token.transfer_from(buyer, get_contract_address(), event_ticket_price);

            let current_ticket_balance = self.event_ticket_balance.entry(event_id).read();
            self
                .event_ticket_balance
                .entry(event_id)
                .write(current_ticket_balance + event_ticket_price);

            // mint the nft ticket to the user
            event_ticket.safe_mint(buyer);

            let tba_address = self._deploy_tba(event_ticket_address, ticket_id);

            // emit event for ticket purchase
            self
                .emit(
                    TicketPurchased {
                        event_id: event_id,
                        ticket_id: ticket_id,
                        buyer: buyer,
                        tba_address: tba_address,
                        ticket_price: event_ticket_price
                    }
                );

            tba_address
        }

        fn _deploy_tba(
            self: @ContractState, event_ticket_address: ContractAddress, ticket_id: u256
        ) -> ContractAddress {
            let tba_address = IRegistryLibraryDispatcher {
                class_hash: self.tba_registry_class_hash.read().try_into().unwrap()
            }
                .create_account(
                    self.tba_accountv3_class_hash.read().try_into().unwrap(),
                    event_ticket_address,
                    ticket_id,
                    ticket_id.try_into().unwrap(),
                    get_tx_info().chain_id
                );
            tba_address
        }
    }
}
