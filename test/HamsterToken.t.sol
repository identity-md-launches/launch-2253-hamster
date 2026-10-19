// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {HamsterToken} from "../src/HamsterToken.sol";

/// @notice Stands in for the launch factory: deploys the token through CREATE2 so that `msg.sender`
///         of the constructor is this contract, exactly as ProjectFactory.launchCustom does.
contract FactoryProbe {
    function deploy(bytes memory code, bytes32 salt) external returns (address deployed) {
        assembly ("memory-safe") {
            deployed := create2(0, add(code, 32), mload(code), salt)
        }
        require(deployed != address(0) && deployed.code.length > 0, "constructor failed");
    }

    function move(IERC20 token, address to, uint256 amount) external returns (bool) {
        return token.transfer(to, amount);
    }
}

contract HamsterTokenTest is Test {
    uint256 internal constant EXPECTED_SUPPLY = 1_000_000_000 * 1e18;

    HamsterToken internal token;
    address internal deployer = makeAddr("deployer");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event SupplyMinted(address indexed deployer, uint256 supply);

    function setUp() public {
        vm.prank(deployer);
        token = new HamsterToken();
    }

    // ---------------------------------------------------------------- metadata and constants

    function test_metadata() public view {
        assertEq(token.name(), "HAMSTER");
        assertEq(token.symbol(), "HAMSTER");
        assertEq(token.decimals(), 18);
        assertEq(token.TOKEN_NAME(), "HAMSTER");
        assertEq(token.TOKEN_SYMBOL(), "HAMSTER");
        assertEq(token.DECIMALS(), 18);
    }

    function test_supplyConstants() public view {
        assertEq(token.WHOLE_SUPPLY(), 1_000_000_000);
        assertEq(token.TOTAL_SUPPLY(), EXPECTED_SUPPLY);
        assertEq(token.TOTAL_SUPPLY(), 1_000_000_000_000_000_000_000_000_000);
    }

    // ---------------------------------------------------------------- minting

    function test_constructorMintsWholeSupplyToDeployer() public view {
        assertEq(token.totalSupply(), EXPECTED_SUPPLY);
        assertEq(token.balanceOf(deployer), EXPECTED_SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
    }

    function test_constructorEmitsTransferAndSupplyMinted() public {
        address other = makeAddr("other");
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(0), other, EXPECTED_SUPPLY);
        vm.expectEmit(true, true, true, true);
        emit SupplyMinted(other, EXPECTED_SUPPLY);
        vm.prank(other);
        new HamsterToken();
    }

    /// @dev The launch deploys through CREATE2 from the factory; the factory must end up holding the
    ///      whole supply and the constructor must not have moved any of it.
    function test_deployedByAFactoryContractMintsToThatFactory() public {
        FactoryProbe factory = new FactoryProbe();
        address predicted =
            vm.computeCreate2Address(bytes32(uint256(7)), keccak256(type(HamsterToken).creationCode), address(factory));
        address deployed = factory.deploy(type(HamsterToken).creationCode, bytes32(uint256(7)));
        assertEq(deployed, predicted, "CREATE2 prediction mismatch");
        HamsterToken launched = HamsterToken(deployed);
        assertEq(launched.totalSupply(), EXPECTED_SUPPLY);
        assertEq(launched.balanceOf(address(factory)), EXPECTED_SUPPLY);
        assertEq(launched.balanceOf(address(this)), 0);
        assertEq(launched.balanceOf(tx.origin), 0);
        // The factory can pay the supply out whole, as it does to the distributor and the requester.
        assertTrue(factory.move(launched, alice, EXPECTED_SUPPLY / 10));
        assertEq(launched.balanceOf(alice), EXPECTED_SUPPLY / 10);
        assertEq(launched.balanceOf(address(factory)), EXPECTED_SUPPLY - EXPECTED_SUPPLY / 10);
    }

    function test_constructorTakesNoArgumentsAndHasNoDependencies() public view {
        // Creation code is the runtime plus the constructor; no constructor arguments are appended.
        bytes memory creation = type(HamsterToken).creationCode;
        assertGt(creation.length, 0);
        assertLe(address(token).code.length, 24_576, "runtime exceeds EIP-170");
    }

    // ---------------------------------------------------------------- transfers: success

    function test_transferMovesBalanceAndEmits() public {
        uint256 amount = 1_000e18;
        vm.expectEmit(true, true, true, true);
        emit Transfer(deployer, alice, amount);
        vm.prank(deployer);
        assertTrue(token.transfer(alice, amount));
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(deployer), EXPECTED_SUPPLY - amount);
        assertEq(token.totalSupply(), EXPECTED_SUPPLY);
    }

    function test_transferWholeBalanceArrivesWhole() public {
        vm.prank(deployer);
        token.transfer(alice, EXPECTED_SUPPLY);
        assertEq(token.balanceOf(alice), EXPECTED_SUPPLY);
        assertEq(token.balanceOf(deployer), 0);
        vm.prank(alice);
        token.transfer(bob, EXPECTED_SUPPLY);
        assertEq(token.balanceOf(bob), EXPECTED_SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_transferZeroAmountSucceeds() public {
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));
        assertEq(token.balanceOf(bob), 0);
    }

    function test_transferToSelfKeepsBalance() public {
        vm.prank(deployer);
        token.transfer(deployer, 5e18);
        assertEq(token.balanceOf(deployer), EXPECTED_SUPPLY);
    }

    function test_approveAndTransferFrom() public {
        uint256 amount = 250e18;
        vm.prank(deployer);
        token.transfer(alice, amount);

        vm.expectEmit(true, true, true, true);
        emit Approval(alice, bob, amount);
        vm.prank(alice);
        assertTrue(token.approve(bob, amount));
        assertEq(token.allowance(alice, bob), amount);

        vm.prank(bob);
        assertTrue(token.transferFrom(alice, bob, 100e18));
        assertEq(token.balanceOf(bob), 100e18);
        assertEq(token.balanceOf(alice), 150e18);
        assertEq(token.allowance(alice, bob), 150e18);
    }

    function test_infiniteAllowanceIsNotDecremented() public {
        vm.prank(deployer);
        token.transfer(alice, 10e18);
        vm.prank(alice);
        token.approve(bob, type(uint256).max);
        vm.prank(bob);
        token.transferFrom(alice, bob, 10e18);
        assertEq(token.allowance(alice, bob), type(uint256).max);
    }

    // ---------------------------------------------------------------- transfers: failure

    function test_transferRevertsOnInsufficientBalance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transfer(bob, 1);
    }

    function test_transferRevertsWhenExceedingBalanceByOne() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, deployer, EXPECTED_SUPPLY, EXPECTED_SUPPLY + 1
            )
        );
        vm.prank(deployer);
        token.transfer(alice, EXPECTED_SUPPLY + 1);
    }

    function test_transferToZeroAddressReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(deployer);
        token.transfer(address(0), 1);
    }

    function test_approveZeroAddressSpenderReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(deployer);
        token.approve(address(0), 1);
    }

    function test_transferFromRevertsWithoutAllowance() public {
        vm.prank(deployer);
        token.transfer(alice, 10e18);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 1));
        vm.prank(bob);
        token.transferFrom(alice, bob, 1);
    }

    function test_transferFromRevertsBeyondAllowance() public {
        vm.prank(deployer);
        token.transfer(alice, 10e18);
        vm.prank(alice);
        token.approve(bob, 5e18);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 5e18, 6e18));
        vm.prank(bob);
        token.transferFrom(alice, bob, 6e18);
    }

    function test_transferFromRevertsBeyondBalanceEvenWithAllowance() public {
        vm.prank(deployer);
        token.transfer(alice, 10e18);
        vm.prank(alice);
        token.approve(bob, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 10e18, 11e18));
        vm.prank(bob);
        token.transferFrom(alice, bob, 11e18);
    }

    // ---------------------------------------------------------------- no privileged powers

    /// @dev Every common admin or mint entry point must be absent: calls to them revert (no fallback)
    ///      and neither the supply nor the caller's balance changes, whoever calls.
    function test_noMintOrAdminEntryPointExists() public {
        string[14] memory signatures = [
            "mint(address,uint256)",
            "mint(uint256)",
            "mint()",
            "issue(uint256)",
            "setOwner(address)",
            "transferOwnership(address)",
            "upgradeTo(address)",
            "initialize(address)",
            "unpause()",
            "pause()",
            "setMinter(address)",
            "burnFrom(address,uint256)",
            "blacklist(address)",
            "owner()"
        ];
        address attacker = makeAddr("attacker");
        address[2] memory callers = [attacker, deployer];
        for (uint256 i = 0; i < signatures.length; i++) {
            bytes memory data = abi.encodeWithSignature(signatures[i], attacker, type(uint128).max);
            for (uint256 c = 0; c < callers.length; c++) {
                vm.prank(callers[c]);
                (bool ok,) = address(token).call(data);
                assertFalse(ok, string.concat("unexpected entry point: ", signatures[i]));
            }
        }
        assertEq(token.totalSupply(), EXPECTED_SUPPLY);
        assertEq(token.balanceOf(attacker), 0);
        assertEq(token.balanceOf(deployer), EXPECTED_SUPPLY);
    }

    function test_noOneCanMoveAHoldersBalanceWithoutAllowance() public {
        vm.prank(deployer);
        token.transfer(alice, 1_000e18);
        // The deployer, the most plausibly trusted address, cannot pull from a holder.
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, deployer, 0, 1));
        token.transferFrom(alice, deployer, 1);
        assertEq(token.balanceOf(alice), 1_000e18);
        // And the holder can still move freely afterwards.
        vm.prank(alice);
        assertTrue(token.transfer(bob, 500e18));
        assertEq(token.balanceOf(bob), 500e18);
    }

    function test_contractHoldsNoEther() public {
        (bool ok,) = address(token).call{value: 1 ether}("");
        assertFalse(ok, "token must not accept ether");
        assertEq(address(token).balance, 0);
    }

    function test_runtimeCodeHasNoDelegatecallCallcodeOrSelfdestruct() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        for (uint256 i = 0; i < runtime.length; i++) {
            uint8 op = uint8(runtime[i]);
            if (op >= 0x60 && op <= 0x7F) {
                i += (op - 0x5F);
                continue;
            }
            assertTrue(op != 0xF4, "DELEGATECALL");
            assertTrue(op != 0xF2, "CALLCODE");
            assertTrue(op != 0xFF, "SELFDESTRUCT");
        }
    }

    // ---------------------------------------------------------------- fuzz

    function testFuzz_transferConservesSupply(address to, uint256 amount) public {
        vm.assume(to != address(0));
        amount = bound(amount, 0, EXPECTED_SUPPLY);
        vm.prank(deployer);
        assertTrue(token.transfer(to, amount));
        assertEq(token.balanceOf(to) + token.balanceOf(deployer), EXPECTED_SUPPLY);
        assertEq(token.totalSupply(), EXPECTED_SUPPLY);
    }

    function testFuzz_transferAboveBalanceReverts(address from, uint256 amount) public {
        vm.assume(from != deployer && from != address(0));
        amount = bound(amount, 1, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, 0, amount));
        vm.prank(from);
        token.transfer(bob, amount);
    }

    function testFuzz_transferFromWithinAllowance(uint256 allowanceAmount, uint256 spend) public {
        allowanceAmount = bound(allowanceAmount, 0, EXPECTED_SUPPLY);
        spend = bound(spend, 0, allowanceAmount);
        vm.prank(deployer);
        token.approve(alice, allowanceAmount);
        vm.prank(alice);
        assertTrue(token.transferFrom(deployer, bob, spend));
        assertEq(token.balanceOf(bob), spend);
        assertEq(token.allowance(deployer, alice), allowanceAmount - spend);
        assertEq(token.totalSupply(), EXPECTED_SUPPLY);
    }

    function testFuzz_transferFromBeyondAllowanceReverts(uint256 allowanceAmount, uint256 spend) public {
        allowanceAmount = bound(allowanceAmount, 0, EXPECTED_SUPPLY - 1);
        spend = bound(spend, allowanceAmount + 1, EXPECTED_SUPPLY);
        vm.prank(deployer);
        token.approve(alice, allowanceAmount);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, allowanceAmount, spend)
        );
        vm.prank(alice);
        token.transferFrom(deployer, bob, spend);
    }

    function testFuzz_everyDeployerReceivesTheWholeSupply(address who) public {
        vm.assume(who != address(0));
        vm.assume(who.code.length == 0);
        vm.prank(who);
        HamsterToken fresh = new HamsterToken();
        assertEq(fresh.totalSupply(), EXPECTED_SUPPLY);
        assertEq(fresh.balanceOf(who), EXPECTED_SUPPLY);
    }
}
