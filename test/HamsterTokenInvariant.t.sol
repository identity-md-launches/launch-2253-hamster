// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {HamsterToken} from "src/HamsterToken.sol";

/// @notice A closed set of four callers plus the token as a passive recipient.
/// @dev Expected state comes from the specified initial supply and requested actions, never
///      from reading token balances/allowances back into the model. No storage is patched.
contract HamsterTokenHandler is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 1e18;
    HamsterToken public immutable token;
    address[4] public actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(HamsterToken token_, address[4] memory actors_) {
        token = token_;
        actors = actors_;
        expectedBalance[actors_[0]] = SUPPLY;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = _actor(fromSeed);
        _transfer(from, _actor(toSeed), bound(amountSeed, 0, expectedBalance[from]));
    }

    function transferEntireBalance(uint256 fromSeed, uint256 toSeed) external {
        address from = _actor(fromSeed);
        _transfer(from, _actor(toSeed), expectedBalance[from]);
    }

    /// @dev Repeated approvals can replace finite limits, grant infinity, or revoke either.
    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed, uint8 mode) external {
        uint256 amount;
        if (mode % 4 == 0) amount = 0;
        else if (mode % 4 == 1) amount = type(uint256).max;
        else if (mode % 4 == 2) amount = bound(amountSeed, 0, SUPPLY);
        else amount = amountSeed;
        _approve(_actor(ownerSeed), _actor(spenderSeed), amount);
    }

    /// @dev Spends existing approvals, without first granting fresh ones. Owner, spender and
    ///      recipient are independent, so self-spends and self-transfers are reachable too.
    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amountSeed) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        address to = _actor(toSeed);
        uint256 allowanceBefore = expectedAllowance[owner][spender];
        uint256 available = _min(expectedBalance[owner], allowanceBefore);
        uint256 amount = bound(amountSeed, 0, available);

        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount), "valid delegated transfer returned false");
        if (allowanceBefore != type(uint256).max) expectedAllowance[owner][spender] -= amount;
        _recordTransfer(owner, to, amount);
    }

    function rejectDirectOverdraft(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = _actor(fromSeed);
        uint256 held = expectedBalance[from];
        uint256 amount = bound(amountSeed, held + 1, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, held, amount));
        vm.prank(from);
        token.transfer(_actor(toSeed), amount);
        // Failed actions leave the model untouched; invariants check all balances and approvals.
    }

    function rejectDelegatedOverdraft(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amountSeed)
        external
    {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 held = expectedBalance[owner];
        uint256 amount = bound(amountSeed, held + 1, type(uint256).max - 1);
        // A finite approval lets the allowance debit execute before the balance check fails.
        // That debit must roll back along with the rest of the failed transaction.
        _approve(owner, spender, amount);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, held, amount));
        vm.prank(spender);
        token.transferFrom(owner, _actor(toSeed), amount);
    }

    function rejectUnauthorizedSpend(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amountSeed)
        external
    {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 allowed = expectedAllowance[owner][spender];
        uint256 amount;
        bytes memory reason;
        if (allowed == type(uint256).max) {
            // No input exceeds infinity. Exercise the remaining balance limit in this state.
            uint256 held = expectedBalance[owner];
            amount = bound(amountSeed, held + 1, type(uint256).max);
            reason = abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, held, amount);
        } else {
            amount = bound(amountSeed, allowed + 1, type(uint256).max);
            reason = abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, amount);
        }
        vm.expectRevert(reason);
        vm.prank(spender);
        token.transferFrom(owner, _actor(toSeed), amount);
    }

    function rejectZeroRecipient(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 amount = bound(amountSeed, 0, expectedBalance[owner]);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(owner);
        token.transfer(address(0), amount);

        amount = bound(amountSeed, 0, _min(expectedBalance[owner], expectedAllowance[owner][spender]));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(owner, address(0), amount);
    }

    function rejectZeroSpender(uint256 ownerSeed, uint256 amount) external {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(_actor(ownerSeed));
        token.approve(address(0), amount);
    }

    function donateToToken(uint256 fromSeed, uint256 amountSeed) external {
        address from = _actor(fromSeed);
        // Include passive contract holdings in conservation without draining the entire
        // actor set into an unrecoverable recipient early in every random sequence.
        uint256 amount = bound(amountSeed, 0, _min(expectedBalance[from], 1e18));
        _transfer(from, address(token), amount);
    }

    function _transfer(address from, address to, uint256 amount) private {
        vm.prank(from);
        assertTrue(token.transfer(to, amount), "valid transfer returned false");
        _recordTransfer(from, to, amount);
    }

    function _recordTransfer(address from, address to, uint256 amount) private {
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function _approve(address owner, address spender, uint256 amount) private {
        vm.prank(owner);
        assertTrue(token.approve(spender, amount), "valid approval returned false");
        expectedAllowance[owner][spender] = amount;
    }

    function _actor(uint256 seed) private view returns (address) {
        return actors[seed % actors.length];
    }

    function _min(uint256 a, uint256 b) private pure returns (uint256) {
        return a < b ? a : b;
    }
}

/// @notice Unexpected handler reverts must fail the campaign, never silently discard an action.
/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract HamsterTokenInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 1e18;
    HamsterToken private token;
    HamsterTokenHandler private handler;
    address[4] private actors;

    function setUp() public {
        actors = [
            makeAddr("invariant.deployer"),
            makeAddr("invariant.alice"),
            makeAddr("invariant.bob"),
            makeAddr("invariant.carol")
        ];
        vm.prank(actors[0]);
        token = new HamsterToken();
        handler = new HamsterTokenHandler(token, actors);

        // Seed all actors using real transfers, then establish finite and infinite approvals
        // so meaningful delegated transfers are reachable from the start of every sequence.
        for (uint256 i = 1; i < actors.length; ++i) {
            handler.transfer(0, i, SUPPLY / 4);
        }
        for (uint256 i; i < actors.length; ++i) {
            handler.approve(i, (i + 1) % actors.length, SUPPLY / 8, 2);
            handler.approve(i, (i + 2) % actors.length, 0, 1);
        }

        bytes4[] memory selectors = new bytes4[](10);
        selectors[0] = handler.transfer.selector;
        selectors[1] = handler.transferEntireBalance.selector;
        selectors[2] = handler.approve.selector;
        selectors[3] = handler.transferFrom.selector;
        selectors[4] = handler.rejectDirectOverdraft.selector;
        selectors[5] = handler.rejectDelegatedOverdraft.selector;
        selectors[6] = handler.rejectUnauthorizedSpend.selector;
        selectors[7] = handler.rejectZeroRecipient.selector;
        selectors[8] = handler.rejectZeroSpender.selector;
        selectors[9] = handler.donateToToken.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_balancesMatchLedgerAndConserveFixedSupply() public view {
        uint256 sum;
        for (uint256 i; i < actors.length; ++i) {
            uint256 actual = token.balanceOf(actors[i]);
            assertEq(actual, handler.expectedBalance(actors[i]), "actor balance differs from requested transfers");
            sum += actual;
        }
        uint256 heldByToken = token.balanceOf(address(token));
        assertEq(heldByToken, handler.expectedBalance(address(token)), "contract-held tokens were lost or created");
        sum += heldByToken;
        assertEq(sum, SUPPLY, "transfers created, destroyed or leaked tokens");
        assertEq(token.totalSupply(), SUPPLY, "the constructor supply changed");
        assertEq(token.balanceOf(address(handler)), 0, "handler unexpectedly received tokens");
        assertEq(token.balanceOf(address(this)), 0, "test unexpectedly received tokens");
    }

    function invariant_allowancesMatchOnlyApprovedAndSpentAmounts() public view {
        for (uint256 i; i < actors.length; ++i) {
            for (uint256 j; j < actors.length; ++j) {
                assertEq(
                    token.allowance(actors[i], actors[j]),
                    handler.expectedAllowance(actors[i], actors[j]),
                    "allowance changed outside its owner's approval or successful spending"
                );
            }
            assertEq(token.allowance(actors[i], address(0)), 0);
            assertEq(token.allowance(address(0), actors[i]), 0);
        }
    }

    function invariant_metadataAndZeroBalanceRemainUnchanged() public view {
        assertEq(token.name(), "HAMSTER");
        assertEq(token.symbol(), "HAMSTER");
        assertEq(token.decimals(), 18);
        assertEq(token.balanceOf(address(0)), 0, "a transfer minted or burned through address zero");
    }

    /// @dev Deterministically exercise every handler, including positive delegated spending,
    ///      depletion, self-transfer, revocation and rollback. Random action counts need no
    ///      probabilistic minimum assertion that could make an otherwise sound campaign flaky.
    function test_handlerExercisesMeaningfulTransitions() public {
        handler.transfer(0, 1, 1);
        handler.transferFrom(0, 1, 2, 1);
        handler.transferFrom(0, 2, 0, 1);
        assertEq(token.allowance(actors[0], actors[1]), SUPPLY / 8 - 1);
        assertEq(token.allowance(actors[0], actors[2]), type(uint256).max);
        _assertAllInvariants();

        handler.approve(0, 1, 0, 0);
        handler.rejectUnauthorizedSpend(0, 1, 2, 1);
        handler.rejectDirectOverdraft(0, 1, type(uint256).max);
        handler.rejectDelegatedOverdraft(0, 1, 2, SUPPLY);
        handler.rejectZeroRecipient(0, 1, 1);
        handler.rejectZeroSpender(0, type(uint256).max);
        _assertAllInvariants();

        handler.donateToToken(0, 1);
        handler.transferEntireBalance(1, 2);
        assertEq(token.balanceOf(actors[1]), 0);
        handler.transferEntireBalance(2, 2);
        _assertAllInvariants();
    }

    function _assertAllInvariants() private view {
        invariant_balancesMatchLedgerAndConserveFixedSupply();
        invariant_allowancesMatchOnlyApprovedAndSpentAmounts();
        invariant_metadataAndZeroBalanceRemainUnchanged();
    }
}
