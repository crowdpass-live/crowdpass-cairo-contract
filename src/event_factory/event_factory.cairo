// SPDX-License-Identifier: MIT
#[starknet::contract]
pub mod EventFactory {
    //*//////////////////////////////////////////////////////////////////////////
    //                                 IMPORTS
    //////////////////////////////////////////////////////////////////////////*//
    use core::{num::traits::zero::Zero, pedersen::PedersenTrait, hash::HashStateTrait};
    use starknet::{
        ContractAddress, class_hash::ClassHash, syscalls::deploy_syscall, SyscallResultTrait,
        storage::{Map, StoragePointerReadAccess, StoragePointerWriteAccess, StoragePathEntry},
        get_block_timestamp, get_caller_address, get_contract_address, get_tx_info,
    };
    use openzeppelin::{
        introspection::src5::SRC5Component,
        token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait},
        access::accesscontrol::{AccessControlComponent, DEFAULT_ADMIN_ROLE},
        upgrades::{interface::IUpgradeable, UpgradeableComponent},
    };
    use token_bound_accounts::{
        interfaces::{IRegistry::{IRegistryDispatcher, IRegistryLibraryDispatcher, IRegistryDispatcherTrait}},
        utils::array_ext::ArrayExt,
    };
    use crowd_pass::{
        errors::Errors,
        interfaces::{
            i_event_factory::{EventData, IEventFactory},
            i_ticket_721::{ITicket721Dispatcher, ITicket721DispatcherTrait},
        },
    };

    //*//////////////////////////////////////////////////////////////////////////
    //                                 CONSTANTS
    //////////////////////////////////////////////////////////////////////////*//
    pub const E18: u256 = 1000000000000000000;
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
        CheckedIn: CheckedIn,
        PayoutCollected: PayoutCollected,
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

    #[derive(Drop, starknet::Event)]
    struct CheckedIn {
        #[key]
        event_id: u256,
        #[key]
        attendee: ContractAddress,
        time: u64
    }

    #[derive(Drop, starknet::Event)]
    struct PayoutCollected {
        #[key]
        event_id: u256,
        #[key]
        organizer: ContractAddress,
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
        ticket_721_class_hash: felt252,
        tba_registry_class_hash: felt252,
        tba_registry_contract_address: felt252,
        tba_accountv3_class_hash: felt252,
        event_count: u256,
        events: Map<u256, EventData>,
        event_balance: Map<u256, u256>,
        crowd_pass_balance: Map<u256, u256>,
        event_attendance: Map<u256, Map<ContractAddress, bool>>,
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
        tba_registry_contract_address: felt252,
        tba_accountv3_class_hash: felt252,
    ) {
        self.accesscontrol.initializer();
        self.accesscontrol._grant_role(DEFAULT_ADMIN_ROLE, default_admin.try_into().unwrap());
        self.ticket_721_class_hash.write(ticket_721_class_hash);
        self.tba_registry_class_hash.write(tba_registry_class_hash);
        self.tba_registry_contract_address.write(tba_registry_contract_address);
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

        fn check_in(ref self: ContractState, event_id: u256, attendee: ContractAddress) -> bool {
            let event_hash = self._gen_event_hash(event_id);
            self.accesscontrol.assert_only_role(event_hash);
            self._check_in(event_id, attendee);
            true
        }

        fn collect_event_payout(ref self: ContractState, event_id: u256) {
            let main_organizer_role = self._gen_main_organizer_role(event_id);
            self.accesscontrol.assert_only_role(main_organizer_role);
            self._collect_event_payout(event_id);
        }

        fn refund_ticket (ref self : ContractState, event_id: u256, ticket_id: u256) {
            assert(self._refund_ticket(event_id, ticket_id), Errors::REFUND_FAILED);
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

        fn get_event_attendance(self: @ContractState, event_id: u256) -> bool {
            self.event_attendance.entry(event_id).entry(get_caller_address()).read()
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            ACCESS CONTROL IMPL
    //////////////////////////////////////////////////////////////////////////*//
    #[abi(embed_v0)]
    impl AccessControlImpl =
        AccessControlComponent::AccessControlImpl<ContractState>;

    //*//////////////////////////////////////////////////////////////////////////
    //                         ACCESS CONTROL CAMEL IMPL
    //////////////////////////////////////////////////////////////////////////*//
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

    //*//////////////////////////////////////////////////////////////////////////
    //                             PRIVATE FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*//
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
            let ticket = deploy_syscall(
                self.ticket_721_class_hash.read().try_into().unwrap(),
                event_hash,
                array![address_this.into(), address_this.into()].span(),
                true,
            );

            let (ticket_address, _) = ticket.unwrap_syscall();

            // initialize ticket721 contract
            ITicket721Dispatcher { contract_address: ticket_address }
                .initialize(name, symbol, uri,);

            // new event struct instance
            let event_instance = EventData {
                id: event_count,
                organizer: caller,
                ticket_address: ticket_address,
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
                        id: event_count, organizer: caller, ticket_address: ticket_address
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

            let ticket = ITicket721Dispatcher { contract_address: event_instance.ticket_address };

            // TODO: empty string or ByteArray might not equal to "".
            let empty_str = "";
            // update event ticket
            if name != empty_str || name != ticket.name() {
                ticket.update_name(name);
            }
            if symbol != empty_str || symbol != ticket.symbol() {
                ticket.update_symbol(symbol);
            }
            if uri != empty_str || uri != ticket.base_uri() {
                ticket.set_base_uri(uri);
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
            // assert event is not canceled
            assert(!event_instance.is_canceled, Errors::EVENT_CANCELED);
            // assert event has not ended
            assert(event_instance.end_date > get_block_timestamp(), Errors::EVENT_ENDED);

            // verify if caller has enough strk token for the ticket_price + 3% fee
            let ticket_price = event_instance.ticket_price;
            let ticket_price_padded = ticket_price * E18;
            let ticket_price_padded_plus_fee = ticket_price_padded
                + ((ticket_price_padded * 3) / 100);
            let ticket_price_plus_fee = ticket_price_padded_plus_fee / E18;

            let strk_token = IERC20Dispatcher {
                contract_address: STRK_TOKEN_ADDRESS.try_into().unwrap()
            };
            assert(
                strk_token.balance_of(buyer) >= ticket_price_plus_fee, Errors::INSUFFICIENT_BALANCE
            );

            let ticket_address = event_instance.ticket_address;
            let ticket = ITicket721Dispatcher { contract_address: ticket_address };
            let ticket_id = ticket.total_supply() + 1;
            assert(ticket_id <= event_instance.total_tickets, Errors::EVENT_SOLD_OUT);

            // transfer the ticket price to the contract
            strk_token.transfer_from(buyer, get_contract_address(), ticket_price_plus_fee);

            let current_event_balance = self.event_balance.entry(event_id).read();
            self.event_balance.entry(event_id).write(current_event_balance + ticket_price);

            let crowd_pass_fee = ticket_price_plus_fee - ticket_price;
            let current_crowd_pass_balance = self.crowd_pass_balance.entry(event_id).read();
            self
                .crowd_pass_balance
                .entry(event_id)
                .write(current_crowd_pass_balance + crowd_pass_fee);

            // mint the nft ticket to the user
            ticket.safe_mint(buyer);

            let tba_address = self._create_tba(ticket_address, ticket_id);

            // emit event for ticket purchase
            self
                .emit(
                    TicketPurchased {
                        event_id: event_id,
                        ticket_id: ticket_id,
                        buyer: buyer,
                        tba_address: tba_address,
                        ticket_price: ticket_price
                    }
                );

            tba_address
        }

        fn _check_in(ref self: ContractState, event_id: u256, attendee: ContractAddress) {
            let event_instance = self.events.entry(event_id).read();
            let ticket_address = event_instance.ticket_address;
            let ticket = ITicket721Dispatcher { contract_address: ticket_address };

            // assert event has started
            assert(event_instance.start_date >= get_block_timestamp(), Errors::EVENT_NOT_STARTED);

            if !ticket.is_paused() {
                ticket.pause();
            }

            // assert user has a ticket
            assert(ticket.balance_of(attendee) > 0, Errors::NOT_TICKET_HOLDER);

            // checkin attendee
            self.event_attendance.entry(event_id).entry(attendee).write(true);

            // emit event for ticket check in
            self
                .emit(
                    CheckedIn {
                        event_id: event_id, attendee: attendee, time: get_block_timestamp()
                    }
                );
        }

        fn _collect_event_payout(ref self: ContractState, event_id: u256) {
            let event_instance = self.events.entry(event_id).read();
            let organizer = get_caller_address();

            assert(event_instance.organizer == organizer, Errors::NOT_EVENT_ORGANIZER);
            assert(!event_instance.is_canceled, Errors::EVENT_CANCELED);
            assert(event_instance.end_date >= get_block_timestamp(), Errors::EVENT_NOT_ENDED);

            let event_balance = self.event_balance.entry(event_id).read();
            self.event_balance.entry(event_id).write(0);
            let event_balance_padded = event_balance * E18;
            let event_balance_padded_minus_fee = event_balance_padded
                - ((event_balance_padded * 3) / 100);
            let event_balance_minus_fee = event_balance_padded_minus_fee / E18;

            let crowd_pass_fee = event_balance - event_balance_minus_fee;
            let crowd_pass_balance = self.crowd_pass_balance.entry(event_id).read();
            self.crowd_pass_balance.entry(event_id).write(crowd_pass_balance + crowd_pass_fee);

            IERC20Dispatcher { contract_address: STRK_TOKEN_ADDRESS.try_into().unwrap() }
                .transfer(organizer, event_balance_minus_fee);

            self
                .emit(
                    PayoutCollected {
                        event_id: event_id, organizer: organizer, amount: event_balance_minus_fee
                    }
                );
        }

        fn _refund_ticket (ref self : ContractState, event_id: u256, ticket_id: u256) -> bool {
            let event_instance = self.events.entry(event_id).read();
            assert(event_instance.is_canceled, Errors::EVENT_NOT_CANCELED);
            let ticket_address = event_instance.ticket_address;
            let ticket = ITicket721Dispatcher { contract_address: ticket_address };

            let ticket_owner = ticket.owner_of(ticket_id);
            let caller = get_caller_address();
            assert(caller == ticket_owner, Errors::NOT_TICKET_OWNER);
            // ticket.burn(ticket_id);

            let tba_address = self._get_tba(ticket_address, ticket_id);

            let ticket_price = event_instance.ticket_price;

            let current_event_balance = self.event_balance.entry(event_id).read();
            self.event_balance.entry(event_id).write(current_event_balance - ticket_price);

            let success = IERC20Dispatcher { contract_address: STRK_TOKEN_ADDRESS.try_into().unwrap() }
                .transfer(tba_address, ticket_price);

            success
        }

        fn _create_tba(
            self: @ContractState, ticket_address: ContractAddress, ticket_id: u256
        ) -> ContractAddress {
            let tba_address = IRegistryLibraryDispatcher {
                class_hash: self.tba_registry_class_hash.read().try_into().unwrap()
            }
                .create_account(
                    self.tba_accountv3_class_hash.read().try_into().unwrap(),
                    ticket_address,
                    ticket_id,
                    ticket_id.try_into().unwrap(),
                    get_tx_info().chain_id
                );

            tba_address
        }

        fn _get_tba(
            self: @ContractState, ticket_address: ContractAddress, ticket_id: u256
        ) -> ContractAddress {
            let tba_address = IRegistryDispatcher {
                contract_address: self.tba_registry_contract_address.read().try_into().unwrap()
            }
                .get_account(
                    self.tba_accountv3_class_hash.read().try_into().unwrap(),
                    ticket_address,
                    ticket_id,
                    ticket_id.try_into().unwrap(),
                    get_tx_info().chain_id
                );

            tba_address
        }
    }
}
