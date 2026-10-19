// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {HamsterToken} from "../src/HamsterToken.sol";

/// @title Deploy script for HamsterToken
/// @notice Reviewable reference for a manual deployment. On an IdentityMD launch this script is NOT
///         used: the ProjectFactory deploys the token from its creation code and receives the supply.
///         The token takes no constructor arguments, so there is no configuration to read.
contract DeployHamsterToken is Script {
    /// @notice Deploys the token. The caller of this function (the broadcasting account when run
    ///         through `forge script --broadcast`) becomes `msg.sender` of the constructor and
    ///         therefore receives the whole supply.
    function deploy() public returns (HamsterToken token) {
        token = new HamsterToken();
    }

    /// @notice Entry point for `forge script`. Deploys inside a broadcast.
    function run() external returns (HamsterToken token) {
        vm.startBroadcast();
        token = deploy();
        vm.stopBroadcast();
    }
}
