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
			// url: "https://rpc.ankr.com/0g_newton", // Thirdweb RPC
			// url: "https://evm-rpc.0g.testnet.node75.org", // node75 RPC
			url: "http://8.218.94.246:8545", // OG v3
			// chainId: 16600,
			chainId: 80087,
			accounts: [process.env.PRVKEY],
			gas: 50000,
      		gasPrice: 3000000000,
		},
		galileo: {
			url: "https://evmrpc-testnet.0g.ai",
			chainId: 80087,
			accounts: [process.env.PRVKEY],
			gas: 50000,
	  		gasPrice: 3000000000,
		},
	},
};