use starknet::ContractAddress;

#[starknet::interface]
pub trait ITicketFactory<TContractState> {
    fn deploy_ticket(
        ref self: TContractState, pauser: ContractAddress, minter: ContractAddress, salt: felt252
    ) -> ContractAddress;
}
