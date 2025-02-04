require("@nomicfoundation/hardhat-toolbox");

/** @type import('hardhat/config').HardhatUserConfig */

require('dotenv').config();

module.exports = {
	solidity: {
		compilers: [
			{
				version: "0.8.28",
			},
		],
	},
	settings: {
		evmVersion: "istanbul",
	},
	networks: {
		Test0G: {
			url: "https://evmrpc-testnet.0g.ai/",
			// url: "https://rpc-testnet.0g.ai",
			chainId: 16600,
			accounts: [process.env.PRVKEY],
			gas: 300000000,
      		gasPrice: 3000000000,
		},
	},
};