# تحميل المتغيرات من ملف .env
RPC_L1=https://rpc.ankr.com/eth_sepolia/cf7cdeb4baf00c82329275cd6a2754168d7e807c0528d457b8aafeba14112187
RPC_L2=https://rpc.ankr.com/base_sepolia/cf7cdeb4baf00c82329275cd6a2754168d7e807c0528d457b8aafeba14112187
ETHERSCAN_API_KEY=ZZAHP3Q2Y431BJH5IPDI6412TZ64HPHYG8
# Relayer keys (يمتلك ETH testnet للغاز على كل شبكة)
PK_L1=0xcf613f5b38f743c9e65695ea36f3038528ab053cbfd0f223f12320348a4f1c55
PK_L2=0xcf613f5b38f743c9e65695ea36f3038528ab053cbfd0f223f12320348a4f1c55
L1_EXECUTOR=0x95E5f6ED3a936CB69954a609876654586De395fc

Sepolia:
	forge script script/DeployL1Sepolia.s.sol:DeployL1Sepolia \
	--rpc-url $(RPC_L1) \
	--broadcast \
	--etherscan-api-key $(ETHERSCAN_API_KEY) \
	--verify

Base:
	forge script script/DeployL2BaseSepolia.s.sol:DeployL2BaseSepolia \
	--rpc-url $(RPC_L2) \
	--broadcast \
	--etherscan-api-key $(ETHERSCAN_API_KEY) \
	--verify
