// SPDX-License-Identifier: MIT
use starknet::ContractAddress;

#[starknet::interface]
pub trait ITicket721<TContractState> {
    fn initialize(ref self: TContractState, name: ByteArray, symbol: ByteArray, uri: ByteArray);
    fn pause(ref self: TContractState);
    fn unpause(ref self: TContractState);
    fn safe_mint(ref self: TContractState, recipient: ContractAddress,);
    fn set_base_uri(ref self: TContractState, base_uri: ByteArray);
}
