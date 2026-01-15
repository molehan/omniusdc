// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract L1CCTPExecutor {
    error NotImplemented();

    function finalize(
        bytes calldata,
        /*message*/
        bytes calldata /*attestation*/
    )
        external
        pure
    {
        revert NotImplemented();
    }
}
