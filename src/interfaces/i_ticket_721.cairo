// SPDX-License-Identifier: MIT
use starknet::ContractAddress;

#[starknet::interface]
pub trait ITicket721<TContractState> {
    fn initialize(ref self: TContractState, name: ByteArray, symbol: ByteArray, uri: ByteArray);
    fn pause(ref self: TContractState);
    fn unpause(ref self: TContractState);
    fn safe_mint(ref self: TContractState, recipient: ContractAddress);
    fn update_name(ref self: TContractState, new_name: ByteArray);
    fn update_symbol(ref self: TContractState, new_symbol: ByteArray);
    fn set_base_uri(ref self: TContractState, base_uri: ByteArray);
    // IERC721Enumerable
    fn total_supply(self: @TContractState) -> u256;
    fn token_by_index(self: @TContractState, index: u256) -> u256;
    fn token_of_owner_by_index(self: @TContractState, owner: ContractAddress, index: u256) -> u256;
    /// ERC721ABI
    // IERC721
    fn balance_of(self: @TContractState, account: ContractAddress) -> u256;
    fn owner_of(self: @TContractState, token_id: u256) -> ContractAddress;
    fn safe_transfer_from(
        ref self: TContractState,
        from: ContractAddress,
        to: ContractAddress,
        token_id: u256,
        data: Span<felt252>
    );
    fn transfer_from(
        ref self: TContractState, from: ContractAddress, to: ContractAddress, token_id: u256
    );
    fn approve(ref self: TContractState, to: ContractAddress, token_id: u256);
    fn set_approval_for_all(ref self: TContractState, operator: ContractAddress, approved: bool);
    fn get_approved(self: @TContractState, token_id: u256) -> ContractAddress;
    fn is_approved_for_all(
        self: @TContractState, owner: ContractAddress, operator: ContractAddress
    ) -> bool;

    // ISRC5
    fn supports_interface(self: @TContractState, interface_id: felt252) -> bool;

    // IERC721Metadata
    fn name(self: @TContractState) -> ByteArray;
    fn symbol(self: @TContractState) -> ByteArray;
    fn token_uri(self: @TContractState, token_id: u256) -> ByteArray;

    // IERC721CamelOnly
    fn balanceOf(self: @TContractState, account: ContractAddress) -> u256;
    fn ownerOf(self: @TContractState, tokenId: u256) -> ContractAddress;
    fn safeTransferFrom(
        ref self: TContractState,
        from: ContractAddress,
        to: ContractAddress,
        tokenId: u256,
        data: Span<felt252>
    );
    fn transferFrom(
        ref self: TContractState, from: ContractAddress, to: ContractAddress, tokenId: u256
    );
    fn setApprovalForAll(ref self: TContractState, operator: ContractAddress, approved: bool);
    fn getApproved(self: @TContractState, tokenId: u256) -> ContractAddress;
    fn isApprovedForAll(
        self: @TContractState, owner: ContractAddress, operator: ContractAddress
    ) -> bool;

    // IERC721MetadataCamelOnly
    fn tokenURI(self: @TContractState, tokenId: u256) -> ByteArray;
}
