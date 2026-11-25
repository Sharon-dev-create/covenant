#!/usr/bin/env bash
set -euo pipefail

mode=${1:?usage: bash script/transport.sh preflight|simulate|broadcast unichain|base|lasna [signature args...]}
network=${2:?select unichain, base, or lasna}
shift 2
case "$network" in
    unichain)
        chain=1301
        provider=0x775c9B990ADe401060B78D0e98684eEf8d2466C1
        rpc=${UNICHAIN_SEPOLIA_RPC:?set UNICHAIN_SEPOLIA_RPC}
        signer=${UNICHAIN_SIGNER:-}
        account=${UNICHAIN_KEYSTORE_ACCOUNT:-}
        keystore=${UNICHAIN_KEYSTORE_PATH:-}
        ;;
    base)
        chain=84532
        provider=0x476F44b11F5C942c58f4c8E3d0300E5710743585
        rpc=${BASE_SEPOLIA_RPC:?set BASE_SEPOLIA_RPC}
        signer=${BASE_SIGNER:-}
        account=${BASE_KEYSTORE_ACCOUNT:-}
        keystore=${BASE_KEYSTORE_PATH:-}
        ;;
    lasna)
        chain=5318007
        provider=0x8888888888888888888888888888888888888888
        rpc=${REACTIVE_LASNA_RPC:?set REACTIVE_LASNA_RPC}
        signer=${LASNA_SIGNER:-}
        account=${LASNA_KEYSTORE_ACCOUNT:-}
        keystore=${LASNA_KEYSTORE_PATH:-}
        ;;
    *) printf 'Unknown network %s\n' "$network" >&2; exit 2 ;;
esac

actual_chain=$(cast chain-id --rpc-url "$rpc")
[[ "$actual_chain" == "$chain" ]] || { printf 'Unexpected chain ID %s\n' "$actual_chain" >&2; exit 1; }

if [[ "$mode" == preflight ]]; then
    height=$(cast block-number --rpc-url "$rpc")
    bytecode=$(cast code "$provider" --rpc-url "$rpc" --block "$height")
    [[ "$bytecode" != 0x ]] || { printf 'Provider code missing\n' >&2; exit 1; }
    printf 'chain=%s block=%s provider=%s runtimeHash=%s\n' "$chain" "$height" "$provider" "$(cast keccak "$bytecode")"
    slot=0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc
    implementation_word=$(cast storage "$provider" "$slot" --rpc-url "$rpc" --block "$height")
    implementation="0x${implementation_word: -40}"
    impl_code=$(cast code "$implementation" --rpc-url "$rpc" --block "$height")
    [[ "$impl_code" != 0x ]] || { printf 'Provider implementation code missing\n' >&2; exit 1; }
    printf 'implementation=%s implementationHash=%s\n' "$implementation" "$(cast keccak "$impl_code")"
    cast gas-price --rpc-url "$rpc"
    for getter in _gasPriceCoeffPer1000 _extraGas _maxChargeGas; do
        printf '%s=' "$getter"
        cast call "$provider" "$getter()(uint256)" --rpc-url "$rpc" --block "$height"
    done
    if [[ -n "$signer" ]]; then
        printf 'signer=%s native balance (wei)=' "$signer"
        cast balance "$signer" --rpc-url "$rpc" --block "$height"
    fi
    exit
fi

: "${signer:?set the public signer address for this network}"
signature=${1:?supply a deployment script signature}
shift
case "$signature" in
    'deployReactive()'|'deployEmitter(uint8)'|'deployReceiver(uint8,address,address)'|\
    'configure(address,uint8,address,address,uint64)'|'fund(uint256,address,uint256)') ;;
    *) printf 'Unsupported deployment signature\n' >&2; exit 2 ;;
esac
for argument in "$@"; do
    [[ "$argument" != -* ]] || { printf 'Unexpected option in script arguments\n' >&2; exit 2; }
done

export TRANSPORT_SIGNER="$signer"
command=(forge script script/DeployTransport.s.sol:DeployTransport
    --rpc-url "$rpc" --sender "$signer" --sig "$signature" "$@")
case "$mode" in
    simulate) "${command[@]}" ;;
    broadcast)
        if [[ -n "$account" && -n "$keystore" ]]; then
            printf 'Use either the keystore account name or the keystore path, not both\n' >&2
            exit 2
        fi
        if [[ -n "$account" ]]; then
            signer_args=(--account "$account")
            derived=$(cast wallet address --account "$account")
        elif [[ -n "$keystore" ]]; then
            signer_args=(--keystore "$keystore")
            derived=$(cast wallet address --keystore "$keystore")
        else
            printf 'set the encrypted Foundry keystore account or path for this network\n' >&2
            exit 2
        fi
        [[ "${derived,,}" == "${signer,,}" ]] || {
            printf 'Keystore address %s does not match signer %s\n' "$derived" "$signer" >&2
            exit 1
        }
        "${command[@]}" "${signer_args[@]}" --broadcast
        ;;
    *) printf 'Unknown mode %s\n' "$mode" >&2; exit 2 ;;
esac
