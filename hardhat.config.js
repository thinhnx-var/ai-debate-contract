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
		zero: {
			// url: "https://evmrpc-testnet.0g.ai/",
			url: "https://16600.rpc.thirdweb.com/", // Thirdweb RPC
			chainId: 16600,
			accounts: [process.env.PRVKEY],
			gas: 50000,
      		gasPrice: 3000000000,
		},
	},
};