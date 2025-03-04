// SPDX-License-Identifier: MIT
//  _____     _ _         _         _
// |_   _|_ _(_) |_____  | |   __ _| |__ ___
//   | |/ _` | | / / _ \ | |__/ _` | '_ (_-<
//   |_|\__,_|_|_\_\___/ |____\__,_|_.__/__/
pragma solidity ^0.8.20;

import { IERC165Upgradeable } from
    "lib/openzeppelin-contracts-upgradeable/contracts/utils/introspection/IERC165Upgradeable.sol";

import { IBridge, IRecallableSender } from "../bridge/IBridge.sol";
import { EssentialContract } from "../common/EssentialContract.sol";

abstract contract BaseVault is
    EssentialContract,
    IRecallableSender,
    IERC165Upgradeable
{
    error VAULT_PERMISSION_DENIED();

    /// @notice Initializes the contract with the address manager.
    /// @param addressManager Address manager contract address.
    function init(address addressManager) external initializer {
        EssentialContract._init(addressManager);
    }

    /// @notice Checks if the contract supports the given interface.
    /// @param interfaceId The interface identifier.
    /// @return true if the contract supports the interface, false otherwise.
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override
        returns (bool)
    {
        return interfaceId == type(IRecallableSender).interfaceId;
    }

    function name() public pure virtual returns (bytes32);

    function checkProcessMessageContext()
        internal
        view
        returns (IBridge.Context memory ctx)
    {
        if (msg.sender != resolve("bridge", false)) {
            revert VAULT_PERMISSION_DENIED();
        }

        ctx = IBridge(msg.sender).context();
        address sender = resolve(ctx.srcChainId, name(), false);
        if (ctx.from != sender) revert VAULT_PERMISSION_DENIED();
    }

    function checkRecallMessageContext()
        internal
        view
        returns (IBridge.Context memory ctx)
    {
        if (msg.sender != resolve("bridge", false)) {
            revert VAULT_PERMISSION_DENIED();
        }

        ctx = IBridge(msg.sender).context();
        if (ctx.from != msg.sender) revert VAULT_PERMISSION_DENIED();
    }
}
