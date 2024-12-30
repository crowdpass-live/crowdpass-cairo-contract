use sncast_std::{
    declare, deploy, invoke, call, DeclareResult, DeclareResultTrait, DeployResult, InvokeResult,
    CallResult, get_nonce, FeeSettings, EthFeeSettings
};
// use crowd_pass::ticket::ticket_721::Ticket721;

fn main() {
    let max_fee = 999999999999999;
    let salt = 0x3;

    let declare_nonce = get_nonce('latest');

    let declare_result = declare(
        "Ticket721",
        FeeSettings::Eth(EthFeeSettings { max_fee: Option::Some(max_fee) }),
        Option::Some(declare_nonce)
    )
        .expect('ticket declare failed');

    let class_hash = declare_result.class_hash();
    let deploy_nonce = get_nonce('pending');

    let name: ByteArray = "Ticket721";
    let symbol: ByteArray = "TKK";
    let base_uri: ByteArray = "ipfs://QmVQ4GVu7arg4k7evZfM9aNZyt12j5tBmewGsq9UvYQieh";
    let creator: felt252 = 0x03119564DDE82cc1319aEb21506f6bc9c3e3061BaAdb63ddFeC3410A69C11F86;

    // let mut name_array = array![];
    // let name_ser: felt252 = name.serialize(ref
    // name_array).try_into().unwrap();//array![84,105,99,107,101,116,55,50,49];
    // let mut symbol_array = array![];
    // let symbol_ser: felt252 = symbol.serialize(ref symbol_array).into();
    // let mut base_uri_array = array![];
    // let base_uri_ser: felt252 = base_uri.serialize(ref base_uri_array).into();

    let mut constructor_calldata: Array<felt252> = array![];
    constructor_calldata.append(name);
    constructor_calldata.append(symbol);
    constructor_calldata.append(base_uri);
    constructor_calldata.append(creator);
    constructor_calldata.append(creator);

    let deploy_result = deploy(
        *class_hash,
        constructor_calldata,
        Option::None,
        true,
        FeeSettings::Eth(EthFeeSettings { max_fee: Option::Some(max_fee) }),
        Option::Some(deploy_nonce)
    )
        .expect('ticket deploy failed');

    assert(deploy_result.transaction_hash != 0, deploy_result.transaction_hash);
    println!("Ticket721 deployed at {}", deploy_result.contract_address);

    let invoke_nonce = get_nonce('pending');

    let invoke_result = invoke(
        deploy_result.contract_address,
        selector!("initialize"),
        array![name_ser, symbol_ser, base_uri_ser, creator.into(), creator.into()],
        FeeSettings::Eth(EthFeeSettings { max_fee: Option::Some(max_fee) }),
        Option::Some(invoke_nonce)
    )
        .expect('map invoke failed');

    assert(invoke_result.transaction_hash != 0, invoke_result.transaction_hash);

    let call_result = call(deploy_result.contract_address, selector!("get"), array![0x1])
        .expect('map call failed');

    assert(call_result.data == array![0x2], *call_result.data.at(0));
}
