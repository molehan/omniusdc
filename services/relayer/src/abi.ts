export const L2_GATEWAY_ABI = [
  "event DepositInitiated(address indexed depositorL2,uint256 amount,address indexed ownerL1,uint32 destinationDomain,bytes32 mintRecipient,bytes32 destinationCaller,uint32 minFinalityThreshold,uint256 maxFee,uint64 clientNonce,bytes32 referralCode)"
];

export const L1_WITHDRAW_ROUTER_ABI = [
  "event WithdrawExecuted(bytes32 indexed intentDigest,address indexed owner,address indexed receiver,uint256 shares,uint256 assetsBurnedGross,uint256 maxFee,uint256 minAssetsOut,uint32 dstDomain,uint32 minFinalityThreshold,bytes32 destinationCaller)"
];

// الموجود عندك سابقًا:
export const L1_EXECUTOR_ABI = [
  "function finalize(bytes message, bytes attestation) external returns (uint256 shares)"
];

export const MESSAGE_TRANSMITTER_V2_ABI = [
  "function receiveMessage(bytes message, bytes attestation) external returns (bool)"
];
