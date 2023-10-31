// SPDX-License-Identifier: MIT
//  _____     _ _         _         _
// |_   _|_ _(_) |_____  | |   __ _| |__ ___
//   | |/ _` | | / / _ \ | |__/ _` | '_ (_-<
//   |_|\__,_|_|_\_\___/ |____\__,_|_.__/__/

pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import "../contracts/common/AddressManager.sol";

import
    "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract SetRemoteBridges is Script {
    uint256 public privateKey = vm.envUint("PRIVATE_KEY");
    address public bridgeSuiteAddressManager = vm.envAddress("BRIDGE_SUITE_ADDRESS_MANAGER");
    uint256[] public remoteChainIDs = vm.envUint("REMOTE_CHAIN_IDS", ",");
    address[] public remoteBridges = vm.envAddress("REMOTE_BRIDGES", ",");
    address[] public remoteERC20Vaults = vm.envAddress("REMOTE_ERC20_VAULTS", ",");
    address[] public remoteERC721Vaults = vm.envAddress("REMOTE_ERC721_VAULTS", ",");
    address[] public remoteERC1155Vaults = vm.envAddress("REMOTE_ERC1155_VAULTS", ",");

    function run() external {
        require(remoteChainIDs.length == remoteBridges.length, "invalid remote bridge addresses length");
        require(remoteChainIDs.length == remoteERC20Vaults.length, "invalid remote ERC20Vault addresses length");
        require(remoteChainIDs.length == remoteERC721Vaults.length, "invalid remote ERC721Vault addresses length");
        require(remoteChainIDs.length == remoteERC1155Vaults.length, "invalid remote ERC1155Vault addresses length");

        vm.startBroadcast(privateKey);

        ProxiedAddressManager proxy = ProxiedAddressManager(payable(bridgeSuiteAddressManager));
        for (uint256 i; i < remoteChainIDs.length; ++i) {
          proxy.setAddress(uint64(remoteChainIDs[i]), "bridge", remoteBridges[i]);
          proxy.setAddress(uint64(remoteChainIDs[i]), "erc20_vault", remoteERC20Vaults[i]);
          proxy.setAddress(uint64(remoteChainIDs[i]), "erc721_vault", remoteERC721Vaults[i]);
          proxy.setAddress(uint64(remoteChainIDs[i]), "erc1155_vault", remoteERC1155Vaults[i]);
        }

        vm.stopBroadcast();
    }
}
