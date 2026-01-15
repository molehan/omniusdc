// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library CCTPMessageV2 {
    // Message header offsets (Circle docs)
    uint256 internal constant MSG_VERSION_OFFSET = 0; // uint32
    uint256 internal constant MSG_SOURCE_DOMAIN_OFFSET = 4; // uint32
    uint256 internal constant MSG_DEST_DOMAIN_OFFSET = 8; // uint32
    uint256 internal constant MSG_NONCE_OFFSET = 12; // bytes32
    uint256 internal constant MSG_SENDER_OFFSET = 44; // bytes32
    uint256 internal constant MSG_RECIPIENT_OFFSET = 76; // bytes32
    uint256 internal constant MSG_DEST_CALLER_OFFSET = 108; // bytes32
    uint256 internal constant MSG_MIN_FINALITY_OFFSET = 140; // uint32
    uint256 internal constant MSG_EXEC_FINALITY_OFFSET = 144; // uint32
    uint256 internal constant MSG_BODY_OFFSET = 148; // bytes (rest)

    // BurnMessageV2 offsets (inside messageBody)
    uint256 internal constant BURN_VERSION_OFFSET = 0; // uint32
    uint256 internal constant BURN_BURN_TOKEN_OFFSET = 4; // bytes32
    uint256 internal constant BURN_MINT_RECIPIENT_OFFSET = 36; // bytes32
    uint256 internal constant BURN_AMOUNT_OFFSET = 68; // uint256
    uint256 internal constant BURN_MSG_SENDER_OFFSET = 100; // bytes32
    uint256 internal constant BURN_MAX_FEE_OFFSET = 132; // uint256
    uint256 internal constant BURN_FEE_EXEC_OFFSET = 164; // uint256
    uint256 internal constant BURN_EXPIRATION_OFFSET = 196; // uint256
    uint256 internal constant BURN_HOOKDATA_OFFSET = 228; // bytes (rest)

    function _readUint32(bytes calldata data, uint256 offset) internal pure returns (uint32 v) {
        assembly {
            v := shr(224, calldataload(add(data.offset, offset)))
        }
    }

    function _readBytes32(bytes calldata data, uint256 offset) internal pure returns (bytes32 v) {
        assembly {
            v := calldataload(add(data.offset, offset))
        }
    }

    function _readUint256(bytes calldata data, uint256 offset) internal pure returns (uint256 v) {
        assembly {
            v := calldataload(add(data.offset, offset))
        }
    }

    // -------- Message header --------
    function sourceDomain(bytes calldata message) internal pure returns (uint32) {
        return _readUint32(message, MSG_SOURCE_DOMAIN_OFFSET);
    }

    function destinationDomain(bytes calldata message) internal pure returns (uint32) {
        return _readUint32(message, MSG_DEST_DOMAIN_OFFSET);
    }

    function destinationCaller(bytes calldata message) internal pure returns (bytes32) {
        return _readBytes32(message, MSG_DEST_CALLER_OFFSET);
    }

    function finalityThresholdExecuted(bytes calldata message) internal pure returns (uint32) {
        return _readUint32(message, MSG_EXEC_FINALITY_OFFSET);
    }

    function messageBody(bytes calldata message) internal pure returns (bytes calldata) {
        require(message.length >= MSG_BODY_OFFSET, "MSG_TOO_SHORT");
        return message[MSG_BODY_OFFSET:];
    }

    // -------- BurnMessageV2 (messageBody) --------
    function burnMintRecipient(bytes calldata body) internal pure returns (bytes32) {
        require(body.length >= BURN_MINT_RECIPIENT_OFFSET + 32, "BURN_TOO_SHORT");
        return _readBytes32(body, BURN_MINT_RECIPIENT_OFFSET);
    }

    function burnAmount(bytes calldata body) internal pure returns (uint256) {
        require(body.length >= BURN_AMOUNT_OFFSET + 32, "BURN_TOO_SHORT");
        return _readUint256(body, BURN_AMOUNT_OFFSET);
    }

    function burnFeeExecuted(bytes calldata body) internal pure returns (uint256) {
        require(body.length >= BURN_FEE_EXEC_OFFSET + 32, "BURN_TOO_SHORT");
        return _readUint256(body, BURN_FEE_EXEC_OFFSET);
    }

    function burnHookData(bytes calldata body) internal pure returns (bytes calldata) {
        require(body.length >= BURN_HOOKDATA_OFFSET, "BURN_TOO_SHORT");
        return body[BURN_HOOKDATA_OFFSET:];
    }

    // helpers
    function addressToBytes32(address a) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(a)));
    }

    function bytes32ToAddress(bytes32 b) internal pure returns (address) {
        return address(uint160(uint256(b)));
    }
}
