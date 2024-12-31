use starknet::ContractAddress;

#[starknet::interface]
pub trait ITicketFactory<TContractState> {
    fn deploy_ticket(
        ref self: TContractState,
        default_admin: ContractAddress,
        default_royalty_receiver: ContractAddress,
        salt: felt252
    ) -> ContractAddress;
}
