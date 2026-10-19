// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title HAMSTER (HAMSTER)
/// @notice A plain, fixed-supply ERC-20. The whole supply of 1,000,000,000 HAMSTER (18 decimals) is
///         minted once, in the constructor, to the deployer (`msg.sender`). There is no owner, no
///         minter, no pause, no blacklist, no fee and no burn hook: after construction the contract
///         has no privileged functions at all, and the supply can never grow.
/// @dev    On an IdentityMD launch the deployer is the ProjectFactory, which receives the supply and
///         distributes it (swarm share, pool seed, remainder) itself. The constructor takes no
///         arguments and calls no other contract, so it deploys on an empty chain.
contract HamsterToken is ERC20 {
    /// @notice ERC-20 name, as requested.
    string public constant TOKEN_NAME = "HAMSTER";
    /// @notice ERC-20 symbol, as requested.
    string public constant TOKEN_SYMBOL = "HAMSTER";
    /// @notice Decimals of the token (the ERC-20 default, as requested).
    uint8 public constant DECIMALS = 18;
    /// @notice Total supply in whole tokens, before scaling by decimals.
    uint256 public constant WHOLE_SUPPLY = 1_000_000_000;
    /// @notice Total supply in minor units: 1,000,000,000 * 10^18. The manifest's `token.totalSupply`.
    uint256 public constant TOTAL_SUPPLY = WHOLE_SUPPLY * 10 ** DECIMALS;

    /// @notice Emitted once, when the whole supply is minted to the deployer.
    /// @param deployer The address that deployed the token and received the supply.
    /// @param supply   The amount minted, in minor units; always `TOTAL_SUPPLY`.
    event SupplyMinted(address indexed deployer, uint256 supply);

    /// @notice Mints the entire fixed supply to `msg.sender`.
    constructor() ERC20(TOKEN_NAME, TOKEN_SYMBOL) {
        _mint(msg.sender, TOTAL_SUPPLY);
        emit SupplyMinted(msg.sender, TOTAL_SUPPLY);
    }

    /// @inheritdoc ERC20
    function decimals() public pure override returns (uint8) {
        return DECIMALS;
    }
}
