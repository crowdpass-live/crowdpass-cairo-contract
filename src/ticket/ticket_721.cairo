// SPDX-License-Identifier: MIT

// CLASS_HASH: 0x05ae886b92b49fadf3445f638e91ccadd39dffaa7c29dd1c641f130a23468473
#[starknet::contract]
mod Ticket721 {
    //*//////////////////////////////////////////////////////////////////////////
    //                                 IMPORTS
    //////////////////////////////////////////////////////////////////////////*//
    use starknet::ContractAddress;
    use openzeppelin::{
        access::accesscontrol::{AccessControlComponent, DEFAULT_ADMIN_ROLE},
        introspection::src5::SRC5Component, security::pausable::PausableComponent,
        token::{
            common::erc2981::{DefaultConfig, ERC2981Component},
            erc721::{ERC721Component, extensions::ERC721EnumerableComponent}
        },
    };

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

    // External
    #[abi(embed_v0)]
    impl ERC721MixinImpl = ERC721Component::ERC721MixinImpl<ContractState>;
    #[abi(embed_v0)]
    impl PausableImpl = PausableComponent::PausableImpl<ContractState>;
    #[abi(embed_v0)]
    impl AccessControlImpl =
        AccessControlComponent::AccessControlImpl<ContractState>;
    #[abi(embed_v0)]
    impl AccessControlCamelImpl =
        AccessControlComponent::AccessControlCamelImpl<ContractState>;
    #[abi(embed_v0)]
    impl ERC721EnumerableImpl =
        ERC721EnumerableComponent::ERC721EnumerableImpl<ContractState>;
    #[abi(embed_v0)]
    impl ERC2981Impl = ERC2981Component::ERC2981Impl<ContractState>;
    // #[abi(embed_v0)]
    // impl ERC2981InfoImpl = ERC2981Component::ERC2981InfoImpl<ContractState>;
    // #[abi(embed_v0)]
    // impl ERC2981AdminAccessControlImpl =
    // ERC2981Component::ERC2981AdminAccessControlImpl<ContractState>;

    // Internal
    impl ERC721InternalImpl = ERC721Component::InternalImpl<ContractState>;
    impl PausableInternalImpl = PausableComponent::InternalImpl<ContractState>;
    impl AccessControlInternalImpl = AccessControlComponent::InternalImpl<ContractState>;
    impl ERC721EnumerableInternalImpl = ERC721EnumerableComponent::InternalImpl<ContractState>;
    impl ERC2981InternalImpl = ERC2981Component::InternalImpl<ContractState>;

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
    }

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
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*//
    #[constructor]
    fn constructor(
        ref self: ContractState,
        name: ByteArray,
        symbol: ByteArray,
        uri: ByteArray,
        default_admin: ContractAddress,
        default_royalty_receiver: ContractAddress,
    ) {
        self.erc721.initializer(name, symbol, uri);
        self.accesscontrol.initializer();
        self.erc721_enumerable.initializer();
        self.erc2981.initializer(default_royalty_receiver, 500);

        self.accesscontrol._grant_role(DEFAULT_ADMIN_ROLE, default_admin);
        // self.accesscontrol._grant_role(ERC2981Component::ROYALTY_ADMIN_ROLE, royalty_admin);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                             ERC721 HOOKS IMPL
    //////////////////////////////////////////////////////////////////////////*//
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

    // impl ERC721MetadataImp of ERC721Component::ERC721MetadataImpl<ContractState> {
    //     fn token_uri(ref self: ContractState, token_id: u256) -> ByteArray {
    //         self.erc721._require_owned(token_id);
    //         let base_uri = self.erc721._base_uri();
    //         base_uri
    //     }
    // }

    //*//////////////////////////////////////////////////////////////////////////
    //                            EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*//
    #[generate_trait]
    #[abi(per_item)]
    impl ExternalImpl of ExternalTrait {
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
        fn safe_mint(
            ref self: ContractState,
            recipient: ContractAddress,
            token_id: u256,
            data: Span<felt252>,
        ) {
            self.accesscontrol.assert_only_role(DEFAULT_ADMIN_ROLE);
            self.erc721.safe_mint(recipient, token_id, data);
        }

        #[external(v0)]
        fn set_base_uri(ref self: ContractState, base_uri: ByteArray) {
            self.accesscontrol.assert_only_role(DEFAULT_ADMIN_ROLE);
            self.erc721._set_base_uri(base_uri);
        }
        // #[external(v0)]
    // fn token_uri(ref self: ContractState, token_id: u256) -> ByteArray {
    //     self.erc721._require_owned(token_id);
    //     let base_uri = self.erc721._base_uri();
    //     base_uri
    // }
    }
}
