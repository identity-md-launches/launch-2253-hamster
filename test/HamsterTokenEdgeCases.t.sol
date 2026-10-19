// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {HamsterToken} from "src/HamsterToken.sol";

/// @notice Boundary, authorization and rollback properties for the public ERC-20 interface.
/// forge-config: default.fuzz.runs = 1000
contract HamsterTokenEdgeCasesTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 1e18;
    HamsterToken private token;
    address private alice = makeAddr("edge.alice");
    address private bob = makeAddr("edge.bob");
    address private carol = makeAddr("edge.carol");

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        token = new HamsterToken();
    }

    function test_oneWeiCanBeTransferredAndReturnedExactly() public {
        assertTrue(token.transfer(alice, 1));
        _assertBalances(1, 0);
        vm.prank(alice);
        assertTrue(token.transfer(address(this), 1));
        _assertBalances(0, 0);
    }

    function test_zeroTransfersEmitAndDoNotNeedBalanceOrAllowance() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));

        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(carol);
        assertTrue(token.transferFrom(alice, bob, 0));
        assertEq(token.allowance(alice, carol), 0);
        _assertBalances(0, 0);
    }

    function test_selfTransferAtZeroOneWeiAndWholeSupplyIsNeutral() public {
        uint256[3] memory amounts = [uint256(0), 1, SUPPLY];
        for (uint256 i; i < amounts.length; ++i) {
            vm.expectEmit(true, true, false, true, address(token));
            emit Transfer(address(this), address(this), amounts[i]);
            assertTrue(token.transfer(address(this), amounts[i]));
            _assertBalances(0, 0);
        }
    }

    function test_maximumUintCannotBeTransferredEvenWithInfiniteAllowance() public {
        bytes memory reason = abi.encodeWithSelector(
            IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
        );
        vm.expectRevert(reason);
        token.transfer(bob, type(uint256).max);
        token.approve(alice, type(uint256).max);
        vm.expectRevert(reason);
        vm.prank(alice);
        token.transferFrom(address(this), bob, type(uint256).max);
        assertEq(token.allowance(address(this), alice), type(uint256).max);
        _assertBalances(0, 0);
    }

    function test_zeroRecipientRevertsEvenForZeroAndRestoresFiniteAllowance() public {
        token.approve(alice, SUPPLY);
        uint256[3] memory amounts = [uint256(0), 1, SUPPLY];
        for (uint256 i; i < amounts.length; ++i) {
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
            token.transfer(address(0), amounts[i]);

            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
            vm.prank(alice);
            token.transferFrom(address(this), address(0), amounts[i]);
            assertEq(token.allowance(address(this), alice), SUPPLY, "failed call consumed allowance");
            _assertBalances(0, 0);
        }
    }

    function test_zeroSpenderRejectsZeroOneAndMaximumApproval() public {
        token.approve(alice, 23);
        uint256[3] memory amounts = [uint256(0), 1, type(uint256).max];
        for (uint256 i; i < amounts.length; ++i) {
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
            token.approve(address(0), amounts[i]);
            assertEq(token.allowance(address(this), address(0)), 0);
            assertEq(token.allowance(address(this), alice), 23);
            _assertBalances(0, 0);
        }
    }

    function test_ownerUsingTransferFromAlsoNeedsApproval() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(address(this), bob, 1);
        token.approve(address(this), 1);
        assertTrue(token.transferFrom(address(this), bob, 1));
        assertEq(token.allowance(address(this), address(this)), 0);
        _assertBalances(0, 1);
    }

    function test_delegatedSelfTransferConsumesAllowanceWithoutMovingBalance() public {
        token.transfer(alice, 9);
        vm.prank(alice);
        token.approve(bob, 7);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, alice, 7);
        vm.prank(bob);
        assertTrue(token.transferFrom(alice, alice, 7));
        assertEq(token.allowance(alice, bob), 0);
        _assertBalances(9, 0);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 1));
        vm.prank(bob);
        token.transferFrom(alice, alice, 1);
        _assertBalances(9, 0);
    }

    function test_exhaustedAllowanceCannotBeSpentTwice() public {
        token.approve(alice, SUPPLY);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), bob, SUPPLY);
        vm.prank(alice);
        assertTrue(token.transferFrom(address(this), bob, SUPPLY));
        assertEq(token.allowance(address(this), alice), 0);
        _assertBalances(0, SUPPLY);

        // Refill the owner, so replay fails for authorization rather than lack of tokens.
        vm.prank(bob);
        token.transfer(address(this), SUPPLY);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transferFrom(address(this), bob, 1);
        _assertBalances(0, 0);
    }

    function test_approvalsAreScopedToBothOwnerAndSpender() public {
        token.transfer(alice, 7);
        token.approve(bob, 9);
        vm.prank(alice);
        token.approve(carol, 7);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 1));
        vm.prank(bob);
        token.transferFrom(alice, bob, 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, carol, 0, 1));
        vm.prank(carol);
        token.transferFrom(address(this), bob, 1);

        assertEq(token.allowance(address(this), bob), 9);
        assertEq(token.allowance(alice, carol), 7);
        _assertBalances(7, 0);
        vm.prank(carol);
        assertTrue(token.transferFrom(alice, bob, 7));
        assertEq(token.allowance(alice, carol), 0);
        assertEq(token.allowance(address(this), bob), 9);
        _assertBalances(0, 7);
    }

    function test_infiniteApprovalCanBeReplacedAndRevoked() public {
        token.approve(alice, type(uint256).max);
        token.approve(alice, type(uint256).max - 1);
        vm.prank(alice);
        assertTrue(token.transferFrom(address(this), bob, 1));
        assertEq(token.allowance(address(this), alice), type(uint256).max - 2);

        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), alice, 0);
        token.approve(alice, 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transferFrom(address(this), bob, 1);
        assertEq(token.allowance(address(this), alice), 0);
        _assertBalances(0, 1);
    }

    function test_tokensSentToTokenContractRemainPartOfSupply() public {
        assertTrue(token.transfer(address(token), SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(token)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferFromZeroOwnerCannotMint() public {
        // Even a zero-value call must reject the invalid owner. The particular error's
        // precedence relative to the allowance check is not an ERC-20 requirement.
        vm.prank(bob);
        (bool ok,) = address(token).call(abi.encodeCall(token.transferFrom, (address(0), bob, 0)));
        assertFalse(ok);
        assertEq(token.allowance(address(0), bob), 0);
        _assertBalances(0, 0);
    }

    function testFuzz_roundTripReturnsEveryWei(uint256 amount) public {
        amount = bound(amount, 0, SUPPLY);
        assertTrue(token.transfer(alice, amount));
        _assertBalances(amount, 0);
        vm.prank(alice);
        assertTrue(token.transfer(address(this), amount));
        _assertBalances(0, 0);
    }

    function testFuzz_splittingATransferDoesNotChangeItsResult(uint256 total, uint256 first) public {
        total = bound(total, 0, SUPPLY);
        first = bound(first, 0, total);
        assertTrue(token.transfer(alice, first));
        assertTrue(token.transfer(alice, total - first));
        _assertBalances(total, 0);
    }

    function testFuzz_balanceFailureRollsBackFiniteAllowance(uint256 held, uint256 requested, uint256 approved) public {
        held = bound(held, 0, SUPPLY);
        requested = bound(requested, held + 1, type(uint256).max - 1);
        approved = bound(approved, requested, type(uint256).max - 1);
        token.transfer(alice, held);
        vm.prank(alice);
        token.approve(bob, approved);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, held, requested));
        vm.prank(bob);
        token.transferFrom(alice, bob, requested);
        assertEq(token.allowance(alice, bob), approved, "revert must restore the allowance debit");
        _assertBalances(held, 0);

        // Failure must not freeze the holder or change approvals through a direct transfer.
        vm.prank(alice);
        assertTrue(token.transfer(address(this), held));
        assertEq(token.allowance(alice, bob), approved);
        _assertBalances(0, 0);
    }

    function testFuzz_approvalReplacementIsExactAndIsolated(uint256 first, uint256 replacement) public {
        token.approve(bob, 17);
        vm.prank(alice);
        token.approve(bob, 19);
        assertTrue(token.approve(alice, first));
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), alice, replacement);
        assertTrue(token.approve(alice, replacement));
        assertTrue(token.approve(alice, replacement));
        assertEq(token.allowance(address(this), alice), replacement, "approve replaces; it does not add");
        assertEq(token.allowance(address(this), bob), 17);
        assertEq(token.allowance(alice, bob), 19);
        _assertBalances(0, 0);
    }

    function testFuzz_revocationStopsSpendingUntilReapproved(uint256 approved, uint256 spent) public {
        approved = bound(approved, 1, SUPPLY);
        spent = bound(spent, 0, approved - 1);
        token.transfer(alice, approved);
        vm.prank(alice);
        token.approve(bob, approved);
        vm.prank(bob);
        assertTrue(token.transferFrom(alice, bob, spent));
        assertEq(token.allowance(alice, bob), approved - spent);
        vm.prank(alice);
        token.approve(bob, 0);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 1));
        vm.prank(bob);
        token.transferFrom(alice, bob, 1);
        assertEq(token.allowance(alice, bob), 0);
        _assertBalances(approved - spent, spent);

        vm.prank(alice);
        token.approve(bob, 1);
        vm.prank(bob);
        assertTrue(token.transferFrom(alice, bob, 1));
        assertEq(token.allowance(alice, bob), 0);
        _assertBalances(approved - spent - 1, spent + 1);
    }

    function testFuzz_infiniteAllowanceSurvivesRepeatedSpending(uint256 first, uint256 second) public {
        first = bound(first, 0, SUPPLY);
        second = bound(second, 0, SUPPLY - first);
        token.approve(alice, type(uint256).max);
        vm.prank(alice);
        assertTrue(token.transferFrom(address(this), bob, first));
        assertEq(token.allowance(address(this), alice), type(uint256).max);
        vm.prank(alice);
        assertTrue(token.transferFrom(address(this), bob, second));
        assertEq(token.allowance(address(this), alice), type(uint256).max);
        _assertBalances(0, first + second);
    }

    function testFuzz_selfTransferStillRequiresSufficientBalance(uint256 held, uint256 requested) public {
        held = bound(held, 0, SUPPLY);
        requested = bound(requested, held + 1, type(uint256).max);
        token.transfer(alice, held);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, held, requested));
        vm.prank(alice);
        token.transfer(alice, requested);
        _assertBalances(held, 0);
    }

    function testFuzz_ownerSpenderAndRecipientMayAllCoincide(uint256 held, uint256 spent) public {
        held = bound(held, 0, SUPPLY);
        spent = bound(spent, 0, held);
        token.transfer(alice, held);
        vm.prank(alice);
        token.approve(alice, spent);
        vm.prank(alice);
        assertTrue(token.transferFrom(alice, alice, spent));
        assertEq(token.allowance(alice, alice), 0);
        _assertBalances(held, 0);
    }

    function _assertBalances(uint256 aliceBalance, uint256 bobBalance) private view {
        assertEq(token.balanceOf(alice), aliceBalance);
        assertEq(token.balanceOf(bob), bobBalance);
        assertEq(token.balanceOf(address(this)), SUPPLY - aliceBalance - bobBalance);
        assertEq(token.balanceOf(carol), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
