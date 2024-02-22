%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.starknet.common.syscalls import call_contract, get_caller_address, replace_class
from starkware.cairo.common.uint256 import Uint256, uint256_unsigned_div_rem
from starkware.cairo.common.math import assert_le_felt, split_felt
from cairo_contracts.src.openzeppelin.upgrades.library import Proxy
from src.interface.proxy_wallet import IProxyWallet

//
// Events
//

@event
func domain_to_addr_update(domain_len: felt, domain: felt*, address: felt) {
}

//
// Storage variables
//

@storage_var
func _name_owners(name) -> (owner: felt) {
}

@storage_var
func _is_registration_open() -> (boolean: felt) {
}

@storage_var
func _blacklisted_addresses(address: felt) -> (boolean: felt) {
}

@storage_var
func _is_class_hash_wl(class_hash: felt) -> (boolean: felt) {
}

@storage_var
func _admin_address() -> (_admin_address: felt) {
}

//
// Proxy functions
//

@external
func initializer{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    admin: felt
) {
    // Can only be called if there is no admin
    let (current_admin) = _admin_address.read();
    assert current_admin = 0;

    _admin_address.write(admin);

    return ();
}

@external
func upgrade{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    new_implementation: felt
) {
    // Set contract implementation
    _check_admin();
    Proxy._set_implementation_hash(new_implementation);
    return ();
}


@external
func upgrade_regenesis{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    new_implementation: felt
) {
    // Set Cairo 2 contract implementation
    _check_admin();
    replace_class(new_implementation);
    return ();
}

//
// Admin functions
//

@external
func open_registration{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> () {
    _check_admin();
    _is_registration_open.write(1);

    return ();
}

@external
func close_registration{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> () {
    _check_admin();
    _is_registration_open.write(0);

    return ();
}

@external
func set_wl_class_hash{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    new_class_hash: felt
) -> () {
    _check_admin();
    _is_class_hash_wl.write(new_class_hash, 1);

    return ();
}

@external
func set_admin{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    new_admin: felt
) -> () {
    _check_admin();
    _admin_address.write(new_admin);

    return ();
}

//
// User functions
//

@external
func claim_name_for{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(name: felt, address: felt) -> () {
    alloc_locals;

    // Check if registration is open
    let (is_open) = _is_registration_open.read();
    with_attr error_message("The registration is closed.") {
        assert is_open = 1;
    }

    // Check if receiver is a braavos wallet
    with_attr error_message(
            "The wallet is not a Braavos wallet, change your wallet to a Braavos wallet.") {
        _check_braavos(address);
    }

    // Check if name is not taken
    let (owner) = _name_owners.read(name);
    with_attr error_message("This Braavos name is taken.") {
        assert owner = 0;
    }

    // Check if name is more than 4 letters
    let (high, low) = split_felt(name);
    let number_of_character = _get_amount_of_chars(Uint256(low, high));
    with_attr error_message("You can not register a Braavos name with less than 4 characters.") {
        assert_le_felt(4, number_of_character);
    }

    // Check if address is not blackisted
    let (is_blacklisted) = _blacklisted_addresses.read(address);
    with_attr error_message("Address already registered a Braavos name.") {
        assert is_blacklisted = 0;
    }

    // Write name to storage and blacklist the address
    domain_to_addr_update.emit(1, new (name), address);
    _name_owners.write(name, address);
    _blacklisted_addresses.write(address, 1);

    return ();
}

@external
func claim_name{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(name: felt) -> () {
    alloc_locals;

    // Check if registration is open
    let (is_open) = _is_registration_open.read();
    with_attr error_message("The registration is closed.") {
        assert is_open = 1;
    }

    // Check if caller is a braavos wallet
    let (caller) = get_caller_address();
    with_attr error_message(
            "Your wallet is not a Braavos wallet, change your wallet to a Braavos wallet.") {
        _check_braavos(caller);
    }

    // Check if name is not taken
    let (owner) = _name_owners.read(name);
    with_attr error_message("This Braavos name is taken.") {
        assert owner = 0;
    }

    // Check if name is more than 4 letters
    let (high, low) = split_felt(name);
    let number_of_character = _get_amount_of_chars(Uint256(low, high));
    with_attr error_message("You can not register a Braavos name with less than 4 characters.") {
        assert_le_felt(4, number_of_character);
    }

    // Check if address is not blackisted
    let (is_blacklisted) = _blacklisted_addresses.read(caller);
    with_attr error_message("You already registered a Braavos name.") {
        assert is_blacklisted = 0;
    }

    // Write name to storage and blacklist the address
    domain_to_addr_update.emit(1, new (name), caller);
    _name_owners.write(name, caller);
    _blacklisted_addresses.write(caller, 1);

    return ();
}

@external
func transfer_name{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    name: felt, new_owner: felt
) -> () {
    alloc_locals;

    // Check if owner is caller
    let (owner) = _name_owners.read(name);
    let (caller) = get_caller_address();
    assert owner = caller;

    // Check if new owner is a braavos wallet
    with_attr error_message(
            "The receiver wallet is not a Braavos wallet, change it to a Braavos wallet.") {
        _check_braavos(new_owner);
    }
    // Change address in storage
    domain_to_addr_update.emit(1, new (name), new_owner);
    _name_owners.write(name, new_owner);

    return ();
}

//
// View functions
//

@view
func domain_to_address{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    domain_len: felt, domain: felt*
) -> (address: felt) {
    assert domain_len = 1;
    let (owner) = _name_owners.read([domain]);

    return (owner,);
}

@view
func is_registration_open{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> (
    is_registration_open: felt
) {
    let (is_registration_open) = _is_registration_open.read();

    return (is_registration_open,);
}


@view
func is_class_hash_wl{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    class_hash: felt
) -> (is_whitelisted: felt) {
    let (is_whitelisted) = _is_class_hash_wl.read(class_hash);

    return (is_whitelisted,);
}

//
// Utils
//

const GET_SIGNERS_SELECTOR = 0x2b8faca80de28f81027b46c4f3cb534c44616e721ae9f1e96539c6b54a1d932;

func _check_braavos{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr} (
    address: felt,
) -> () {
    tempvar _empty_calldata = new ();
    call_contract(
        contract_address=address,
        function_selector=GET_SIGNERS_SELECTOR,
        calldata_size=0,
        calldata=_empty_calldata,
    );

    return ();
}

func _check_admin{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() -> () {
    let (caller) = get_caller_address();
    let (admin) = _admin_address.read();
    with_attr error_message("You can not call this function cause you are not the admin.") {
        assert caller = admin;
    }

    return ();
}

func _get_amount_of_chars{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}(
    domain: Uint256
) -> felt {
    alloc_locals;
    if (domain.low == 0 and domain.high == 0) {
        return (0);
    }
    // 38 = simple_alphabet_size
    let (local p, q) = uint256_unsigned_div_rem(domain, Uint256(38, 0));
    if (q.high == 0 and q.low == 37) {
        // 3 = complex_alphabet_size
        let (shifted_p, _) = uint256_unsigned_div_rem(p, Uint256(2, 0));
        let next = _get_amount_of_chars(shifted_p);
        return 1 + next;
    }
    let next = _get_amount_of_chars(p);
    return 1 + next;
}
