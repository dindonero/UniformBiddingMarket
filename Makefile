-include .env

install :; forge install foundry-rs/forge-std --no-commit && forge install openzeppelin/openzeppelin-contracts --no-commit && forge install OpenZeppelin/openzeppelin-contracts-upgradeable --no-commit && forge install OpenZeppelin/openzeppelin-foundry-upgrades --no-commit

deploy_on_arbitrum_sepolia :; forge script ./script/EnergyBiddingMarket.s.sol --rpc-url https://arb-sepolia.g.alchemy.com/v2/18IIrRGp692rMuRPiRPntO8EZ2PNZGap --broadcast --private-key ${PRIVATE_KEY} --verify WWQ7TEHXAYKHJCN6IF82HW2EWX8X135482