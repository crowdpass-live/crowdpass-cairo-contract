// SPDX-License-Identifier: MIT
pub use starknet::{
    ContractAddress, class_hash::ClassHash, syscalls::deploy_syscall, SyscallResultTrait
};

#[starknet::interface]
pub trait ITicketFactory<TContractState> {
    fn deploy_ticket(
        ref self: TContractState, pauser: ContractAddress, minter: ContractAddress, salt: felt252
    ) -> ContractAddress;
}

#[starknet::component]
pub mod TicketFactory {
    use crowd_pass::interfaces::i_ticket_factory::ITicketFactory;
    use starknet::{
        ContractAddress, class_hash::ClassHash, syscalls::deploy_syscall, SyscallResultTrait,
        storage::{Map, StoragePointerReadAccess, StoragePointerWriteAccess,}
    };
    use core::traits::{TryInto, Into};

    const TICKET_NFT_CLASS_HASH: felt252 =
        0xdb8e966fd661153e22cd588ad816605900a06569edc47e2adcc629619b2b31;

    // storage
    #[storage]
    struct Storage {
        ticket_count: u32,
        tickets: Map::<u32, ContractAddress>, // Ticket ID to Ticket address
    }

    #[embeddable_as(Tickets)]
    impl TicketFactoryImpl<
        TContractState,
        +HasComponent<TContractState>,
        +Drop<TContractState>
    > of ITicketFactory<ComponentState<TContractState>> {
        fn deploy_ticket(
            ref self: ComponentState<TContractState>,
            pauser: ContractAddress,
            minter: ContractAddress,
            salt: felt252
        ) -> ContractAddress {
            let _ticket_count = self.ticket_count.read() + 1;

            // formatting constructor arguments
            let mut constructor_calldata: Array<felt252> = array![pauser.into(), minter.into()];
            // deploying the contract
            let class_hash: ClassHash = TICKET_NFT_CLASS_HASH.try_into().unwrap();
            let result = deploy_syscall(class_hash, salt, constructor_calldata.span(), true);
            let (ticket_address, _) = result.unwrap_syscall();

            self.tickets.entry(_ticket_count).write(ticket_address);

            self.ticket_count.write(_ticket_count);

            ticket_address
        }
    }
}