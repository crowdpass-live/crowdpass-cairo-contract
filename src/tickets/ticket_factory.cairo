// SPDX-License-Identifier: MIT
#[starknet::component]
pub mod TicketFactoryComponent {
    //*//////////////////////////////////////////////////////////////////////////
    //                                  IMPORTS
    //////////////////////////////////////////////////////////////////////////*//
    use crowd_pass::interfaces::i_ticket_factory::ITicketFactory;
    use starknet::{
        ContractAddress, class_hash::ClassHash, SyscallResultTrait, syscalls::deploy_syscall,
    };
    use core::traits::{TryInto, Into};

    const TICKET_NFT_CLASS_HASH: felt252 =
        0x03ba1071218d3fb88a76489f68510c7dd1c602d29fa0a9ece0a54da616a96860;

    //*//////////////////////////////////////////////////////////////////////////
    //                                  EVENTS
    //////////////////////////////////////////////////////////////////////////*//
    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        TicketDeployed: TicketDeployed,
    }

    #[derive(Drop, starknet::Event)]
    pub struct TicketDeployed {
        #[key]
        pub default_admin: ContractAddress,
        pub default_royalty_receiver: ContractAddress,
        pub ticket_address: ContractAddress,
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  STORAGE
    //////////////////////////////////////////////////////////////////////////*//
    #[storage]
    pub struct Storage {}

    //*//////////////////////////////////////////////////////////////////////////
    //                             EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*//
    #[embeddable_as(TicketFactoryImpl)]
    impl Ticket<
        TContractState, +HasComponent<TContractState>,
    > of ITicketFactory<ComponentState<TContractState>> {
        fn deploy_ticket(
            ref self: ComponentState<TContractState>,
            default_admin: ContractAddress,
            default_royalty_receiver: ContractAddress,
            salt: felt252
        ) -> ContractAddress {
            // formatting constructor arguments
            let mut constructor_calldata: Array<felt252> = array![
                default_admin.into(), default_royalty_receiver.into()
            ];
            // deploying the contract
            let class_hash: ClassHash = TICKET_NFT_CLASS_HASH.try_into().unwrap();
            let result = deploy_syscall(class_hash, salt, constructor_calldata.span(), true);
            let (ticket_address, _) = result.unwrap_syscall();

            // emitting the event
            self
                .emit(
                    TicketDeployed {
                        default_admin: default_admin,
                        default_royalty_receiver: default_royalty_receiver,
                        ticket_address: ticket_address,
                    }
                );

            ticket_address
        }
    }
}
