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
    use alexandria_data_structures::span_ext::SpanTraitExt;
    use token_bound_accounts::{
        interfaces::IRegistry::{
            IRegistryDispatcher, IRegistryLibraryDispatcher, IRegistryDispatcherTrait
        },
    };
    use crowd_pass::{
        errors::Errors,
        interfaces::{
            i_event_factory::{EventData, EventMetadata, IEventFactory},
            i_ticket_721::{ITicket721Dispatcher, ITicket721DispatcherTrait},
        },
    };

    //*//////////////////////////////////////////////////////////////////////////
    //                                 CONSTANTS
    //////////////////////////////////////////////////////////////////////////*//
    const E18: u256 = 1000000000000000000;
    const STRK_TOKEN_ADDRESS: felt252 =
        0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d;
    const TICKET_721_CLASS_HASH: felt252 =
        0x01a6143d240fc4bfe546698326e56089d8345c790765fd190d495b3b19144074;
    const TBA_REGISTRY_CLASS_HASH: felt252 =
        0x2cbf50931c7ec9029c5188985ea5fa8aedc728d352bde12ec889c212f0e8b3;
    const TBA_REGISTRY_CONTRACT_ADDRESS: felt252 =
        0x41f87c7b00c3fb50cc7744f896f2d3438414be33912bd24f17318c9f48523a1;
    const TBA_ACCOUNTV3_CLASS_HASH: felt252 =
        0x29d2a1b11dd97289e18042502f11356133a2201dd19e716813fb01fbee9e9a4;

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
        Refunded: Refunded,
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

    #[derive(Drop, starknet::Event)]
    struct Refunded {
        #[key]
        event_id: u256,
        #[key]
        attendee: ContractAddress,
        tba: ContractAddress,
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
        event_balance: Map<u256, u256>,
        crowd_pass_balance: Map<u256, u256>,
        event_ticket_holder: Map<u256, Map<ContractAddress, bool>>,
        event_attendance: Map<u256, Map<ContractAddress, bool>>,
        event_organizer_count: Map<u256, u32>,
        event_organizers: Map<u256, Map<u32, ContractAddress>>,
        organizer_event_count: Map<ContractAddress, u256>,
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*//
    #[constructor]
    fn constructor(ref self: ContractState, default_admin: felt252,) {
        self.accesscontrol.initializer();
        self.accesscontrol._grant_role(DEFAULT_ADMIN_ROLE, default_admin.try_into().unwrap());
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
            start_date: u64,
            end_date: u64,
            total_tickets: u256,
            ticket_price: u256,
        ) -> EventData {
            let event = self
                ._create_event(
                    name, symbol, uri, start_date, end_date, total_tickets, ticket_price
                );

            event
        }

        fn update_event(
            ref self: ContractState,
            event_id: u256,
            name: ByteArray,
            symbol: ByteArray,
            uri: ByteArray,
            start_date: u64,
            end_date: u64,
            total_tickets: u256,
            ticket_price: u256,
        ) -> EventData {
            let main_organizer_role = self._gen_main_organizer_role(event_id);
            // assert caller has main organizer role
            self.accesscontrol.assert_only_role(main_organizer_role);

            let mut event_instance = self.events.entry(event_id).read();
            // assert event has not ended
            assert(event_instance.end_date > get_block_timestamp(), Errors::EVENT_ENDED);
            // assert caller is the main organizer
            assert(get_caller_address() == event_instance.organizer, Errors::NOT_EVENT_ORGANIZER);

            let ticket = ITicket721Dispatcher { contract_address: event_instance.ticket_address };

            // update event ticket
            if name.len().is_non_zero() || name != ticket.name() {
                ticket.set_name(name);
            }
            if symbol.len().is_non_zero() || symbol != ticket.symbol() {
                ticket.set_symbol(symbol);
            }
            if uri.len().is_non_zero() || uri != ticket.base_uri() {
                ticket.set_base_uri(uri);
            }

            // update event instance
            event_instance.updated_at = get_block_timestamp();
            event_instance.start_date = start_date;
            event_instance.end_date = end_date;
            event_instance.total_tickets = total_tickets;
            event_instance.ticket_price = ticket_price;

            // Take a snapshot of `event_instance`
            let event_snapshot = @event_instance;

            self.events.entry(event_id).write(*event_snapshot);

            self.emit(EventUpdated { id: event_id, start_date: start_date, end_date: end_date });

            *event_snapshot
        }

        fn cancel_event(ref self: ContractState, event_id: u256) -> bool {
            let main_organizer_role = self._gen_main_organizer_role(event_id);
            // assert caller has main organizer role
            self.accesscontrol.assert_only_role(main_organizer_role);

            // assert event has been created
            let event_count = self.event_count.read();
            assert(event_id <= event_count, Errors::EVENT_NOT_CREATED);

            let mut event_instance = self.events.entry(event_id).read();
            // assert caller is the main event organizer
            assert(get_caller_address() == event_instance.organizer, Errors::NOT_EVENT_ORGANIZER);
            // assert event has not started
            assert(get_block_timestamp() < event_instance.start_date, Errors::EVENT_STARTED);

            // cancel event here
            event_instance.is_canceled = true;
            self.events.entry(event_id).write(event_instance);

            self.emit(EventCanceled { id: event_id });

            true
        }

        fn add_organizer(ref self: ContractState, event_id: u256, organizer: ContractAddress) {
            let main_organizer_role = self._gen_main_organizer_role(event_id);
            // assert caller has main organizer role
            self.accesscontrol.assert_only_role(main_organizer_role);
            let event_role = self._gen_event_role(event_id);

            if !self.accesscontrol.has_role(event_role, organizer) {
                self.accesscontrol.grant_role(event_role, organizer);
                let event_organizers_count = self.event_organizer_count.entry(event_id).read();
                self.event_organizer_count.entry(event_id).write(event_organizers_count + 1);
                self
                    .event_organizers
                    .entry(event_id)
                    .entry(event_organizers_count + 1)
                    .write(organizer);
            }
        }

        fn add_organizers(
            ref self: ContractState, event_id: u256, organizers: Span<ContractAddress>
        ) {
            let main_organizer_role = self._gen_main_organizer_role(event_id);
            // assert caller has main organizer role
            self.accesscontrol.assert_only_role(main_organizer_role);

            let mut index = 0;

            loop {
                if organizers.len() < index + 1 {
                    break;
                }

                self.add_organizer(event_id, *organizers.at(index));

                index += 1;
            };
        }

        fn remove_organizer(ref self: ContractState, event_id: u256, organizer: ContractAddress) {
            let main_organizer_role = self._gen_main_organizer_role(event_id);
            // assert caller has main organizer role
            self.accesscontrol.assert_only_role(main_organizer_role);
            let event_role = self._gen_event_role(event_id);

            if self.accesscontrol.has_role(event_role, organizer) {
                self.accesscontrol.revoke_role(event_role, organizer);
                let event_organizers_count = self.event_organizer_count.entry(event_id).read();
                // Get last organizer
                let last_organizer = self
                    .event_organizers
                    .entry(event_id)
                    .entry(event_organizers_count)
                    .read();

                let organizers = self.get_event_organizers(event_id);
                let organizer_position: u32 = organizers.position(@organizer).unwrap_or_default();

                self
                    .event_organizers
                    .entry(event_id)
                    .entry(organizer_position)
                    .write(last_organizer);
                self.event_organizers.entry(event_id).entry(1).write(Zero::zero());
                self.event_organizer_count.entry(event_id).write(event_organizers_count - 1);
            }
        }

        fn remove_organizers(
            ref self: ContractState, event_id: u256, organizers: Span<ContractAddress>
        ) {
            let main_organizer_role = self._gen_main_organizer_role(event_id);
            // assert caller has main organizer role
            self.accesscontrol.assert_only_role(main_organizer_role);
            let mut index = 0;

            loop {
                if organizers.len() < index + 1 {
                    break;
                }

                self.remove_organizer(event_id, *organizers.at(index));

                index += 1;
            };
        }

        fn purchase_ticket(ref self: ContractState, event_id: u256) -> ContractAddress {
            let tba_address = self._purchase_ticket(event_id);
            tba_address
        }

        fn check_in(ref self: ContractState, event_id: u256, attendee: ContractAddress) -> bool {
            let event_role = self._gen_event_role(event_id);
            self.accesscontrol.assert_only_role(event_role);
            self._check_in(event_id, attendee);
            true
        }

        fn collect_event_payout(ref self: ContractState, event_id: u256) {
            let main_organizer_role = self._gen_main_organizer_role(event_id);
            self.accesscontrol.assert_only_role(main_organizer_role);
            self._collect_event_payout(event_id);
        }

        fn refund_ticket(ref self: ContractState, event_id: u256, ticket_id: u256) {
            let event_instance = self.events.entry(event_id).read();
            assert(event_instance.is_canceled, Errors::EVENT_NOT_CANCELED);
            let ticket_address = event_instance.ticket_address;
            let ticket = ITicket721Dispatcher { contract_address: ticket_address };

            let caller = get_caller_address();
            let tba_address = self._get_tba(ticket_address, ticket_id);
            assert(caller == tba_address, Errors::CALLER_NOT_TBA);

            let ticket_owner = ticket.owner_of(ticket_id);
            assert(
                self.event_attendance.entry(event_id).entry(ticket_owner).read(),
                Errors::NOT_TICKET_OWNER
            );

            let ticket_price = event_instance.ticket_price;

            let current_event_balance = self.event_balance.entry(event_id).read();
            self.event_balance.entry(event_id).write(current_event_balance - ticket_price);

            let success = IERC20Dispatcher {
                contract_address: STRK_TOKEN_ADDRESS.try_into().unwrap()
            }
                .transfer(tba_address, ticket_price);

            assert(success, Errors::REFUND_FAILED);
        }

        // -------------- GETTER FUNCTIONS -----------------------

        fn get_all_events(self: @ContractState) -> Span<EventMetadata> {
            let mut events = array![];
            let count = self.event_count.read();
            let mut i: u256 = 1;

            while i < count + 1 {
                let event: EventData = self.events.entry(i).read();
                let ticket_address = event.ticket_address;
                let ticket = ITicket721Dispatcher { contract_address: ticket_address };
                let metadata = EventMetadata {
                    id: event.id,
                    organizer: event.organizer,
                    ticket_address: ticket_address,
                    name: ticket.name(),
                    symbol: ticket.symbol(),
                    uri: ticket.base_uri(),
                    created_at: event.created_at,
                    updated_at: event.updated_at,
                    start_date: event.start_date,
                    end_date: event.end_date,
                    total_tickets: event.total_tickets,
                    ticket_price: event.ticket_price,
                    is_canceled: event.is_canceled,
                };
                events.append(metadata);
                i = i + 1;
            };

            events.span()
        }

        fn get_event(self: @ContractState, event_id: u256) -> EventMetadata {
            let event_instance = self.events.entry(event_id).read();
            let ticket_address = event_instance.ticket_address;
            let ticket = ITicket721Dispatcher { contract_address: ticket_address };
            let event = EventMetadata {
                id: event_instance.id,
                organizer: event_instance.organizer,
                ticket_address: ticket_address,
                name: ticket.name(),
                symbol: ticket.symbol(),
                uri: ticket.base_uri(),
                created_at: event_instance.created_at,
                updated_at: event_instance.updated_at,
                start_date: event_instance.start_date,
                end_date: event_instance.end_date,
                total_tickets: event_instance.total_tickets,
                ticket_price: event_instance.ticket_price,
                is_canceled: event_instance.is_canceled,
            };

            event
        }

        fn get_event_count(self: @ContractState) -> u256 {
            self.event_count.read()
        }

        fn get_organizer_event_count(self: @ContractState, organizer: ContractAddress) -> u256 {
            self.organizer_event_count.entry(organizer).read()
        }

        fn get_event_balance(self: @ContractState, event_id: u256) -> u256 {
            self.event_balance.entry(event_id).read()
        }

        fn get_event_organizers(self: @ContractState, event_id: u256) -> Span<ContractAddress> {
            let organizers = array![];
            let event_organizers_count = self.event_organizer_count.entry(event_id).read();
            let mut index = 1;

            loop {
                if event_organizers_count < index + 1 {
                    break;
                }

                self.event_organizers.entry(event_id).entry(index).read();
            };

            organizers.span()
        }

        fn get_available_tickets(self: @ContractState, event_id: u256) -> u256 {
            let event_instance = self.events.entry(event_id).read();
            let ticket = ITicket721Dispatcher { contract_address: event_instance.ticket_address };
            event_instance.total_tickets - ticket.total_supply()
        }

        fn get_ticket_price_plus_fee(self: @ContractState, event_id: u256) -> u256 {
            let event_instance = self.events.entry(event_id).read();
            self._get_ticket_price_plus_fee(event_instance.ticket_price)
        }

        fn is_ticket_holder(
            self: @ContractState, event_id: u256, attendee: ContractAddress
        ) -> bool {
            self.event_ticket_holder.entry(event_id).entry(attendee).read()
        }

        fn is_event_attendee(
            self: @ContractState, event_id: u256, attendee: ContractAddress
        ) -> bool {
            self.event_attendance.entry(event_id).entry(attendee).read()
        }

        fn gen_event_role(self: @ContractState, event_id: u256) -> felt252 {
            PedersenTrait::new(0)
                .update('CROWD_PASS_EVENT')
                .update(event_id.try_into().unwrap())
                .finalize()
        }

        fn gen_main_organizer_role(self: @ContractState, event_id: u256) -> felt252 {
            PedersenTrait::new(0)
                .update('MAIN_ORGANIZER')
                .update(self._gen_event_role(event_id))
                .finalize()
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
        fn _gen_event_role(self: @ContractState, event_id: u256) -> felt252 {
            PedersenTrait::new(0)
                .update('CROWD_PASS_EVENT')
                .update(event_id.try_into().unwrap())
                .finalize()
        }

        fn _gen_main_organizer_role(self: @ContractState, event_id: u256) -> felt252 {
            PedersenTrait::new(0)
                .update('MAIN_ORGANIZER')
                .update(self._gen_event_role(event_id))
                .finalize()
        }

        fn _get_ticket_price_plus_fee(self: @ContractState, price: u256) -> u256 {
            let padded_price = price * E18;
            let padded_price_plus_fee = padded_price + ((padded_price * 3) / 100);
            let price_plus_fee = padded_price_plus_fee / E18;
            price_plus_fee
        }

        fn _create_event(
            ref self: ContractState,
            name: ByteArray,
            symbol: ByteArray,
            uri: ByteArray,
            start_date: u64,
            end_date: u64,
            total_tickets: u256,
            ticket_price: u256,
        ) -> EventData {
            assert(end_date > start_date + 86399, Errors::INVALID_EVENT_DURATION); // 1 day

            let organizer = get_caller_address();
            let event_count = self.event_count.read() + 1;
            let address_this = get_contract_address();

            // create event role
            let event_role = self._gen_event_role(event_count);
            let main_organizer_role = self._gen_main_organizer_role(event_count);
            // grant main organizer role
            self.accesscontrol._grant_role(main_organizer_role, organizer);
            // set main organizer role as the admin role for this event role
            self.accesscontrol.set_role_admin(event_role, main_organizer_role);

            // deploy ticket721 contract
            let ticket = deploy_syscall(
                TICKET_721_CLASS_HASH.try_into().unwrap(),
                event_role,
                array![address_this.into(), address_this.into()].span(),
                true,
            );

            let (ticket_address, _) = ticket.unwrap_syscall();

            // initialize ticket721 contract
            ITicket721Dispatcher { contract_address: ticket_address }.initialize(name, symbol, uri);

            // new event struct instance
            let event_instance = EventData {
                id: event_count,
                organizer: organizer,
                ticket_address: ticket_address,
                created_at: get_block_timestamp(),
                updated_at: 0,
                start_date: start_date,
                end_date: end_date,
                total_tickets: total_tickets,
                ticket_price: ticket_price,
                is_canceled: false,
            };

            // Take a snapshot of `event_instance`
            let event_snapshot = @event_instance;

            // Map event_id to new_event
            self.events.entry(event_count).write(*event_snapshot);

            // Update event count
            self.event_count.write(event_count);

            self
                .organizer_event_count
                .entry(organizer)
                .write(self.organizer_event_count.entry(organizer).read() + 1);

            // emit event for event creation
            self
                .emit(
                    EventCreated {
                        id: event_count, organizer: organizer, ticket_address: ticket_address
                    }
                );

            *event_snapshot
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

            let ticket_address = event_instance.ticket_address;
            let ticket = ITicket721Dispatcher { contract_address: ticket_address };

            let ticket_id = ticket.total_supply() + 1;
            assert(ticket_id <= event_instance.total_tickets, Errors::EVENT_SOLD_OUT);

            // assert buyer does not have a ticket to mitigate scalping
            assert(ticket.balance_of(buyer) == 0, Errors::ALREADY_MINTED);

            let strk_token = IERC20Dispatcher {
                contract_address: STRK_TOKEN_ADDRESS.try_into().unwrap()
            };

            // verify if caller has enough strk token for the ticket_price + 3% fee
            let ticket_price = event_instance.ticket_price;
            let ticket_price_plus_fee = self._get_ticket_price_plus_fee(ticket_price);

            let event_factory_address = get_contract_address();
            assert(
                strk_token.allowance(buyer, event_factory_address) == ticket_price_plus_fee,
                Errors::INSUFFICIENT_ALLOWANCE
            );

            assert(
                strk_token.balance_of(buyer) >= ticket_price_plus_fee, Errors::INSUFFICIENT_BALANCE
            );

            // transfer the ticket price to the contract
            assert(
                strk_token.transfer_from(buyer, event_factory_address, ticket_price_plus_fee),
                Errors::TRANSFER_FAILED
            );

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

            if !self.event_ticket_holder.entry(event_id).entry(buyer).read() {
                self.event_ticket_holder.entry(event_id).entry(buyer).write(true);
            }

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

            // assert event has started
            assert(event_instance.start_date >= get_block_timestamp(), Errors::EVENT_NOT_STARTED);
            assert(event_instance.end_date <= get_block_timestamp(), Errors::EVENT_ENDED);

            let ticket_address = event_instance.ticket_address;
            let ticket = ITicket721Dispatcher { contract_address: ticket_address };

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

            assert(
                IERC20Dispatcher { contract_address: STRK_TOKEN_ADDRESS.try_into().unwrap() }
                    .transfer(organizer, event_balance_minus_fee),
                Errors::TRANSFER_FAILED
            );

            self
                .emit(
                    PayoutCollected {
                        event_id: event_id, organizer: organizer, amount: event_balance_minus_fee
                    }
                );
        }

        fn _create_tba(
            self: @ContractState, ticket_address: ContractAddress, ticket_id: u256
        ) -> ContractAddress {
            let tba_address = IRegistryLibraryDispatcher {
                class_hash: TBA_REGISTRY_CLASS_HASH.try_into().unwrap()
            }
                .create_account(
                    TBA_ACCOUNTV3_CLASS_HASH.try_into().unwrap(),
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
                contract_address: TBA_REGISTRY_CONTRACT_ADDRESS.try_into().unwrap()
            }
                .get_account(
                    TBA_ACCOUNTV3_CLASS_HASH.try_into().unwrap(),
                    ticket_address,
                    ticket_id,
                    ticket_id.try_into().unwrap(),
                    get_tx_info().chain_id
                );

            tba_address
        }
    }
}

#[cfg(test)]
mod tests {}
