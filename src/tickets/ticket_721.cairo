// SPDX-License-Identifier: MIT
#[starknet::contract]
pub mod Ticket721 {
    //*//////////////////////////////////////////////////////////////////////////
    //                                 IMPORTS
    //////////////////////////////////////////////////////////////////////////*//
    use starknet::{
        ContractAddress, ClassHash, storage::{StoragePointerReadAccess, StoragePointerWriteAccess},
    };
    use openzeppelin::{
        access::accesscontrol::{AccessControlComponent, DEFAULT_ADMIN_ROLE},
        introspection::src5::SRC5Component,
        security::{pausable::PausableComponent, initializable::InitializableComponent},
        token::{
            common::erc2981::{DefaultConfig, ERC2981Component},
            erc721::{extensions::ERC721EnumerableComponent, ERC721Component},
        },
        upgrades::{interface::IUpgradeable, UpgradeableComponent},
    };
    use crowd_pass::errors::Errors;

    //*//////////////////////////////////////////////////////////////////////////
    //                                COMPONENTS
    //////////////////////////////////////////////////////////////////////////*//
    component!(path: ERC721Component, storage: erc721, event: ERC721Event);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);
    component!(path: PausableComponent, storage: pausable, event: PausableEvent);
    component!(path: AccessControlComponent, storage: accesscontrol, event: AccessControlEvent);
    component!(
        path: ERC721EnumerableComponent, storage: erc721_enumerable, event: ERC721EnumerableEvent
    );
    component!(path: ERC2981Component, storage: erc2981, event: ERC2981Event);
    component!(path: InitializableComponent, storage: initializable, event: InitializableEvent);
    component!(path: UpgradeableComponent, storage: upgradeable, event: UpgradeableEvent);

    //*//////////////////////////////////////////////////////////////////////////
    //                                  EVENTS
    //////////////////////////////////////////////////////////////////////////*//
    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        ERC721Event: ERC721Component::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
        #[flat]
        PausableEvent: PausableComponent::Event,
        #[flat]
        AccessControlEvent: AccessControlComponent::Event,
        #[flat]
        ERC721EnumerableEvent: ERC721EnumerableComponent::Event,
        #[flat]
        ERC2981Event: ERC2981Component::Event,
        #[flat]
        InitializableEvent: InitializableComponent::Event,
        #[flat]
        UpgradeableEvent: UpgradeableComponent::Event,
        NameUpdated: NameUpdated,
        SymbolUpdated: SymbolUpdated,
        UriUpdated: UriUpdated,
    }

    #[derive(Drop, starknet::Event)]
    struct NameUpdated {
        #[key]
        old_name: ByteArray,
        #[key]
        new_name: ByteArray,
    }

    #[derive(Drop, starknet::Event)]
    struct SymbolUpdated {
        #[key]
        old_symbol: ByteArray,
        #[key]
        new_symbol: ByteArray,
    }

    #[derive(Drop, starknet::Event)]
    struct UriUpdated {
        #[key]
        old_uri: ByteArray,
        #[key]
        new_uri: ByteArray,
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                 STORAGE
    //////////////////////////////////////////////////////////////////////////*//
    #[storage]
    struct Storage {
        #[substorage(v0)]
        erc721: ERC721Component::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        #[substorage(v0)]
        pausable: PausableComponent::Storage,
        #[substorage(v0)]
        accesscontrol: AccessControlComponent::Storage,
        #[substorage(v0)]
        erc721_enumerable: ERC721EnumerableComponent::Storage,
        #[substorage(v0)]
        erc2981: ERC2981Component::Storage,
        #[substorage(v0)]
        initializable: InitializableComponent::Storage,
        #[substorage(v0)]
        upgradeable: UpgradeableComponent::Storage,
        event_started: bool,
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*//
    #[constructor]
    fn constructor(
        ref self: ContractState,
        default_admin: ContractAddress,
        default_royalty_receiver: ContractAddress,
        // royalty_admin: ContractAddress
    ) {
        self.accesscontrol.initializer();
        self.erc721_enumerable.initializer();
        self.erc2981.initializer(default_royalty_receiver, 500);

        self.accesscontrol._grant_role(DEFAULT_ADMIN_ROLE, default_admin);
        // self.accesscontrol._grant_role(ERC2981Component::ROYALTY_ADMIN_ROLE, royalty_admin);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*//
    #[generate_trait]
    #[abi(per_item)]
    impl ExternalImpl of ExternalTrait {
        #[external(v0)]
        fn initialize(
            ref self: ContractState, name: ByteArray, symbol: ByteArray, uri: ByteArray,
        ) {
            self.accesscontrol.assert_only_role(DEFAULT_ADMIN_ROLE);
            self.initializable.initialize();
            self.erc721.initializer(name, symbol, uri);
        }

        #[external(v0)]
        fn pause(ref self: ContractState) {
            self.accesscontrol.assert_only_role(DEFAULT_ADMIN_ROLE);
            self.pausable.pause();
        }

        #[external(v0)]
        fn unpause(ref self: ContractState) {
            self.accesscontrol.assert_only_role(DEFAULT_ADMIN_ROLE);
            self.pausable.unpause();
        }

        #[external(v0)]
        fn safe_mint(ref self: ContractState, recipient: ContractAddress,) {
            self.accesscontrol.assert_only_role(DEFAULT_ADMIN_ROLE);
            let index = self.total_supply() + 1;
            self.erc721.safe_mint(recipient, index, [''].span());
        }

        #[external(v0)]
        fn update_name(ref self: ContractState, new_name: ByteArray) {
            self.accesscontrol.assert_only_role(DEFAULT_ADMIN_ROLE);
            let old_name = self.erc721.name();
            self.erc721.ERC721_name.write(new_name);
            self.emit(NameUpdated { old_name: old_name, new_name: self.erc721.name() });
        }

        #[external(v0)]
        fn update_symbol(ref self: ContractState, new_symbol: ByteArray) {
            self.accesscontrol.assert_only_role(DEFAULT_ADMIN_ROLE);
            let old_symbol = self.erc721.symbol();
            self.erc721.ERC721_symbol.write(new_symbol);
            self.emit(SymbolUpdated { old_symbol: old_symbol, new_symbol: self.erc721.symbol() });
        }

        #[external(v0)]
        fn set_base_uri(ref self: ContractState, base_uri: ByteArray) {
            self.accesscontrol.assert_only_role(DEFAULT_ADMIN_ROLE);
            let old_uri = self.erc721._base_uri();
            self.erc721._set_base_uri(base_uri);
            self.emit(UriUpdated { old_uri: old_uri, new_uri: self.erc721._base_uri() });
        }

        #[external(v0)]
        fn start_event(ref self: ContractState) {
            self.accesscontrol.assert_only_role(DEFAULT_ADMIN_ROLE);
            self.event_started.write(true);
        }

        #[external(v0)]
        fn has_event_started(self: @ContractState) -> bool {
            self.event_started.read()
        }

        // ERC721 Functions

        #[external(v0)]
        fn balance_of(self: @ContractState, account: ContractAddress) -> u256 {
            self.erc721.balance_of(account)
        }

        #[external(v0)]
        fn owner_of(self: @ContractState, token_id: u256) -> ContractAddress {
            self.erc721.owner_of(token_id)
        }

        #[external(v0)]
        fn safe_transfer_from(
            ref self: ContractState,
            from: ContractAddress,
            to: ContractAddress,
            token_id: u256,
            data: Span<felt252>,
        ) {
            assert(!self.event_started.read(), Errors::EVENT_STARTED);
            self.erc721.safe_transfer_from(from, to, token_id, data);
        }

        #[external(v0)]
        fn transfer_from(
            ref self: ContractState, from: ContractAddress, to: ContractAddress, token_id: u256,
        ) {
            assert(!self.event_started.read(), Errors::EVENT_STARTED);
            self.erc721.transfer_from(from, to, token_id);
        }

        #[external(v0)]
        fn approve(ref self: ContractState, to: ContractAddress, token_id: u256) {
            self.erc721.approve(to, token_id);
        }

        #[external(v0)]
        fn set_approval_for_all(
            ref self: ContractState, operator: ContractAddress, approved: bool,
        ) {
            self.erc721.set_approval_for_all(operator, approved);
        }

        #[external(v0)]
        fn get_approved(self: @ContractState, token_id: u256) -> ContractAddress {
            self.erc721.get_approved(token_id)
        }

        #[external(v0)]
        fn is_approved_for_all(
            self: @ContractState, owner: ContractAddress, operator: ContractAddress,
        ) -> bool {
            self.erc721.is_approved_for_all(owner, operator)
        }

        // ERC721 Metadata Functions

        #[external(v0)]
        fn name(self: @ContractState) -> ByteArray {
            self.erc721.name()
        }

        #[external(v0)]
        fn symbol(self: @ContractState) -> ByteArray {
            self.erc721.symbol()
        }

        #[external(v0)]
        fn token_uri(self: @ContractState, token_id: u256) -> ByteArray {
            self.erc721._base_uri()
        }
    }

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
    //                           ERC721 CAMEL ONLY IMPL
    //////////////////////////////////////////////////////////////////////////*//
    #[abi(embed_v0)]
    impl ERC721CamelOnlyImpl = ERC721Component::ERC721CamelOnlyImpl<ContractState>;

    //*//////////////////////////////////////////////////////////////////////////
    //                           ERC721 ENUMERABLE IMPL
    //////////////////////////////////////////////////////////////////////////*//
    #[abi(embed_v0)]
    impl ERC721EnumerableImpl =
        ERC721EnumerableComponent::ERC721EnumerableImpl<ContractState>;

    //*//////////////////////////////////////////////////////////////////////////
    //                               PAUSABLE IMPL
    //////////////////////////////////////////////////////////////////////////*//
    #[abi(embed_v0)]
    impl PausableImpl = PausableComponent::PausableImpl<ContractState>;

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
    //                                ERC2981 IMPL
    //////////////////////////////////////////////////////////////////////////*//
    #[abi(embed_v0)]
    impl ERC2981Impl = ERC2981Component::ERC2981Impl<ContractState>;

    //*//////////////////////////////////////////////////////////////////////////
    //                             INITIALIZABLE IMPL
    //////////////////////////////////////////////////////////////////////////*//
    #[abi(embed_v0)]
    impl InitializableImpl =
        InitializableComponent::InitializableImpl<ContractState>;

    //*//////////////////////////////////////////////////////////////////////////
    //                             ERC2981 INFO IMPL
    //////////////////////////////////////////////////////////////////////////*//
    // #[abi(embed_v0)]
    // impl ERC2981InfoImpl = ERC2981Component::ERC2981InfoImpl<ContractState>;

    //*//////////////////////////////////////////////////////////////////////////
    //                     ERC2981 ADMIN ACCESS CONTROL IMPL
    //////////////////////////////////////////////////////////////////////////*//
    // #[abi(embed_v0)]
    // impl ERC2981AdminAccessControlImpl =
    // ERC2981Component::ERC2981AdminAccessControlImpl<ContractState>;

    //*//////////////////////////////////////////////////////////////////////////
    //                             INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*//
    /// ERC721 Hooks Impl
    impl ERC721HooksImpl of ERC721Component::ERC721HooksTrait<ContractState> {
        fn before_update(
            ref self: ERC721Component::ComponentState<ContractState>,
            to: ContractAddress,
            token_id: u256,
            auth: ContractAddress,
        ) {
            let mut contract_state = self.get_contract_mut();
            contract_state.pausable.assert_not_paused();
            contract_state.erc721_enumerable.before_update(to, token_id);
        }
    }

    /// Internal Component Functions
    impl ERC721Impl = ERC721Component::ERC721Impl<ContractState>;
    impl ERC721MetadataImpl = ERC721Component::ERC721MetadataImpl<ContractState>;
    impl ERC721InternalImpl = ERC721Component::InternalImpl<ContractState>;
    impl PausableInternalImpl = PausableComponent::InternalImpl<ContractState>;
    impl AccessControlInternalImpl = AccessControlComponent::InternalImpl<ContractState>;
    impl ERC721EnumerableInternalImpl = ERC721EnumerableComponent::InternalImpl<ContractState>;
    impl ERC2981InternalImpl = ERC2981Component::InternalImpl<ContractState>;
    impl InitializableInternalImpl = InitializableComponent::InternalImpl<ContractState>;
    impl UpgradeableInternalImpl = UpgradeableComponent::InternalImpl<ContractState>;
}
