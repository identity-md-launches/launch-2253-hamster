// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {HamsterToken} from "../src/HamsterToken.sol";
import {DeployHamsterToken} from "../script/DeployHamsterToken.s.sol";

contract DeployHamsterTokenTest is Test {
    function test_deployFunctionMintsToTheScriptCaller() public {
        DeployHamsterToken deployScript = new DeployHamsterToken();
        // `deploy()` creates the token from the script contract, so the script contract is the
        // constructor's msg.sender and receives the supply. No environment is read.
        HamsterToken token = deployScript.deploy();
        assertEq(token.name(), "HAMSTER");
        assertEq(token.symbol(), "HAMSTER");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), 1_000_000_000 * 1e18);
        assertEq(token.balanceOf(address(deployScript)), 1_000_000_000 * 1e18);
    }
}
