// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IMessageTransmitterV2} from "../../src/cctp/interfaces/IMessageTransmitterV2.sol";
import {CCTPMessageV2} from "../../src/cctp/CCTPMessageV2.sol";
import {MockUSDC} from "../mocks/MockUSDC.sol";

contract MockMessageTransmitterV2 is IMessageTransmitterV2 {
    MockUSDC public immutable usdc;
    address public feeRecipient;

    constructor(address usdc_, address feeRecipient_) {
        usdc = MockUSDC(usdc_);
        feeRecipient = feeRecipient_;
    }

    function receiveMessage(
        bytes calldata message,
        bytes calldata /*attestation*/
    )
        external
        returns (bool)
    {
        bytes calldata body = CCTPMessageV2.messageBody(message);

        bytes32 mintRecipientB32 = CCTPMessageV2.burnMintRecipient(body);
        address mintRecipient = CCTPMessageV2.bytes32ToAddress(mintRecipientB32);

        uint256 amount = CCTPMessageV2.burnAmount(body);
        uint256 fee = CCTPMessageV2.burnFeeExecuted(body);

        // Fees are deducted from bridged amount; fee minted separately in real impl.
        uint256 net = amount - fee;

        usdc.mint(mintRecipient, net);
        if (fee > 0 && feeRecipient != address(0)) {
            usdc.mint(feeRecipient, fee);
        }

        return true;
    }
}
