// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library HookDataV1 {
    uint8 internal constant VERSION = 1;
    uint8 internal constant ACTION_DEPOSIT = 1;

    error InvalidHookData();

    function encodeDeposit(address ownerL1, uint64 clientNonce, bytes32 referralCode)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encode(VERSION, ACTION_DEPOSIT, ownerL1, clientNonce, referralCode);
    }

    function decodeDeposit(bytes calldata hookData)
        internal
        pure
        returns (address ownerL1, uint64 clientNonce, bytes32 referralCode)
    {
        (uint8 v, uint8 action, address owner, uint64 nonce, bytes32 ref) =
            abi.decode(hookData, (uint8, uint8, address, uint64, bytes32));

        if (v != VERSION || action != ACTION_DEPOSIT) revert InvalidHookData();
        return (owner, nonce, ref);
    }
}
