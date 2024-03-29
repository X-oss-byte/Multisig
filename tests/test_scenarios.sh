#!/bin/bash

setup() {
    load "$HOME/bats-support/load"
    load "$HOME/bats-assert/load"

    test_addr_1=$(gaiad keys show test_key_1 --keyring-backend test --output json | jq -r ".address")
    multisig_addr_2_of_3=$(gaiad keys show multisig_test_2_of_3 --keyring-backend test --output json | jq -r ".address")
    multisig_addr_3_of_4=$(gaiad keys show multisig_test_3_of_4 --keyring-backend test --output json | jq -r ".address")
    denom="uatom"
}

wait_till_next_block() {
    prev_latest_block_hash=$(gaiad status 2>&1 | jq -r ".SyncInfo.latest_block_hash")
    for _ in {1..10}
    do
        latest_block_hash=$(gaiad status 2>&1 | jq -r ".SyncInfo.latest_block_hash")
        if [ "$latest_block_hash" != "$prev_latest_block_hash" ]
        then
            echo "Next block appeared"
            break
        fi
        echo "Waiting for next block"
        sleep 1
    done
}

get_balance(){
    gaiad query bank balances "$1" --output json  \
        | jq -r ".balances[] | select(.denom == \"$denom\") | .amount"
}

@test "Basic sending" {
    prev_balance=$(get_balance "$test_addr_1")

    gaiad tx bank send \
        "$multisig_addr_2_of_3" \
        "$test_addr_1" \
        "1$denom" \
        --gas=200000 \
        --fees="1$denom" \
        --chain-id=testhub \
        --generate-only > unsignedTx.json

    multisig tx push unsignedTx.json cosmos test_multisig_2_of_3 \
        --config "$HOME/multisig/tests/user1_config.toml"
    multisig sign cosmos test_multisig_2_of_3 --from test_key_1 \
        --config "$HOME/multisig/tests/user1_config.toml"

    multisig sign cosmos test_multisig_2_of_3 --from test_key_2 \
        --config "$HOME/multisig/tests/user2_config.toml"

    multisig broadcast cosmos test_multisig_2_of_3\
        --config "$HOME/multisig/tests/user2_config.toml"

    wait_till_next_block

    new_balance=$(get_balance "$test_addr_1")

    assert bash -c "(( $new_balance > $prev_balance ))"
}

@test "Lower than threshold (2/3)" {
    gaiad tx bank send \
        "$multisig_addr_2_of_3" \
        "$test_addr_1" \
        "1$denom" \
        --gas=200000 \
        --fees="1$denom" \
        --chain-id=testhub \
        --generate-only > unsignedTx.json

    multisig tx push unsignedTx.json cosmos test_multisig_2_of_3 \
        --config "$HOME/multisig/tests/user1_config.toml"
    multisig sign cosmos test_multisig_2_of_3 --from test_key_1 \
        --config "$HOME/multisig/tests/user1_config.toml"

    # multisig should fail and return "Insufficient signatures for broadcast"
    # using "run bash -c" because we expect the command to fail but don't want script to exit
    run bash -c "multisig broadcast cosmos test_multisig_2_of_3 --config $HOME/multisig/tests/user1_config.toml"
    assert_failure
}

@test "Lower than threshold (3/4)" {
    gaiad tx bank send \
        "$multisig_addr_3_of_4" \
        "$test_addr_1" \
        "1$denom" \
        --gas=200000 \
        --fees="1$denom" \
        --chain-id=testhub \
        --generate-only > unsignedTx.json

    multisig tx push "$HOME/unsignedTx.json" cosmos test_multisig_3_of_4 \
        --config "$HOME/multisig/tests/user1_config.toml"
    multisig sign cosmos test_multisig_3_of_4 --from test_key_1 \
        --config "$HOME/multisig/tests/user1_config.toml"

    multisig sign cosmos test_multisig_3_of_4 --from test_key_2 \
        --config "$HOME/multisig/tests/user2_config.toml"

    # multisig should fail and return "Insufficient signatures for broadcast"
    # using "run bash -c" because we expect the command to fail but don't want script to exit
    run bash -c "multisig broadcast cosmos test_multisig_3_of_4 --config $HOME/multisig/tests/user1_config.toml"
    assert_failure
}

@test "Config file choise" {
    mkdir "$HOME/multisig/tests/config_tests"
    cd    "$HOME/multisig/tests/config_tests"

    run bash -c "multisig list --all"
    assert_failure # no config provided

    run bash -c "multisig list --all --config $HOME/multisig/tests/user2_config.toml"
    assert_success # config specified explicitly

    cp "$HOME/multisig/tests/user2_config.toml" config.toml
    run bash -c "multisig list --all"
    assert_success # default local config is used

    mkdir ~/.multisig
    mv config.toml ~/.multisig/
    run bash -c "multisig list --all"
    assert_success # default global config is used

    rm ~/.multisig/config.toml # to avoid messing up another tests
}
