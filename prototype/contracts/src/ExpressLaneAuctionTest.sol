// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "./ExpressLaneAuction.sol";
import "forge-std/interfaces/IERC20.sol";

contract MockERC20 is IERC20 {
    string public name = "LANE";
    string public symbol = "LNE";
    uint8 public decimals = 18;
    uint256 public totalSupply = 1000000 * 10**18;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor() {
        balanceOf[msg.sender] = totalSupply;
    }

    function transfer(address recipient, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[recipient] += amount;
        emit Transfer(msg.sender, recipient, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool) {
        require(balanceOf[sender] >= amount, "Insufficient balance");
        require(allowance[sender][msg.sender] >= amount, "Allowance exceeded");
        balanceOf[sender] -= amount;
        balanceOf[recipient] += amount;
        allowance[sender][msg.sender] -= amount;
        emit Transfer(sender, recipient, amount);
        return true;
    }
}

contract ExpressLaneAuctionTest is Test {
    ExpressLaneAuction auction;
    MockERC20 token;

    address bidder1 = vm.addr(1);
    address bidder2 = vm.addr(2);
    address reservePriceSetter = vm.addr(3);
    address bidReceiver = address(0x789);
    uint256 initialTimestamp = block.timestamp;
    uint64 roundDuration = 3600; // 1 hour

    function setUp() public {
        token = new MockERC20();
        auction = new ExpressLaneAuction(
            address(this),
        reservePriceSetter,
            bidReceiver,
            roundDuration,
            initialTimestamp,
            address(token),
            0,
            0
        );

        // Allocate some tokens to bidders
        token.transfer(bidder1, 1000 * 10**18);
        token.transfer(bidder2, 1000 * 10**18);

        // Approve the auction contract to spend tokens on behalf of bidders
        vm.prank(bidder1);
        token.approve(address(auction), 1000 * 10**18);

        vm.prank(bidder2);
        token.approve(address(auction), 1000 * 10**18);
    }

    function getTestSignature(
        uint256 privateKey,
        uint16 domainValue,
        uint256 chainId,
        uint256 round,
        uint256 amount
    ) public returns (bytes memory) {
        bytes32 messageHash = keccak256(abi.encodePacked(domainValue, chainId, round, amount));
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, ethSignedMessageHash);
        return abi.encodePacked(r, s, v);
    }

    function testSubmitDeposit() public {
        vm.prank(bidder1);
        auction.submitDeposit(100 * 10**18);
        assertEq(auction.bidderBalance(bidder1), 100 * 10**18);
    }

    function testInitiateWithdrawal() public {
        vm.prank(bidder1);
        auction.submitDeposit(100 * 10**18);

        vm.prank(bidder1);
        auction.initiateWithdrawal(50 * 10**18);

        assertEq(auction.bidderBalance(bidder1), 50 * 10**18);
    }

    function testFinalizeWithdrawal() public {
        assertEq(token.balanceOf(bidder1), 1000 * 10**18); // Initial balance

        vm.prank(bidder1);
        auction.submitDeposit(100 * 10**18);

        vm.prank(bidder1);
        auction.initiateWithdrawal(50 * 10**18);

        // Simulate time passing to next round + 2
        vm.warp(block.timestamp + roundDuration * 2);

        vm.prank(bidder1);
        auction.finalizeWithdrawal();

        assertEq(token.balanceOf(bidder1), 950 * 10**18); // Initial balance minus deposit plus withdrawn
    }

    function testResolveAuction() public {
        vm.prank(bidder1);
        auction.submitDeposit(200 * 10**18);

        vm.prank(bidder2);
        auction.submitDeposit(300 * 10**18);

        uint256 bidder1PrivateKey = 1;
        uint256 bidder2PrivateKey = 2;

        uint256 nextRound = auction.currentRound() + 1;

        // Set up bids
        Bid memory bid1 = Bid({
            bidder: bidder1,
            chainId: block.chainid,
            round: nextRound,
            amount: 150 * 10**18,
            signature: getTestSignature(bidder1PrivateKey, auction.bidSignatureDomainValue(), block.chainid, nextRound, 150 * 10**18)
        });

        Bid memory bid2 = Bid({
            bidder: bidder2,
            chainId: block.chainid,
            round: nextRound,
            amount: 100 * 10**18,
            signature: getTestSignature(bidder2PrivateKey, auction.bidSignatureDomainValue(), block.chainid, nextRound, 100 * 10**18)
        });

        // Resolve the auction
        auction.resolveAuction(bid1, bid2);

        // Verify results
        assertEq(auction.bidderBalance(bidder1), 100 * 10**18);
        assertEq(auction.bidderBalance(bidder2), 300 * 10**18);
        assertEq(auction.expressLaneControllerByRound(nextRound), bidder1);
    }

    function testVerifySignature() public {
        // Example private key and signer address
        address signer = vm.addr(1);

        // Example message
        bytes memory message = abi.encodePacked("Hello, world!");

        // Sign the message
        bytes32 messageHash = keccak256(message);
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, ethSignedMessageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Verify the signature
        bool isValid = auction.verifySignature(signer, message, signature);
        assertTrue(isValid, "Signature should be valid");
    }
}

