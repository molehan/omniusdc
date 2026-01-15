// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract L1WithdrawRouter {
    error NotImplemented();

    function execute(
        bytes calldata,
        /*intent*/
        bytes calldata,
        /*sig*/
        bytes calldata /*permitSig*/
    )
        external
        pure
    {
        revert NotImplemented();
    }
}
