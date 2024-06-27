// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {ExpressLaneAuction} from "../src/ExpressLaneAuction.sol";

contract ExpressLaneAuctionTest is Test {
    ExpressLaneAuction public expLane;

    function setUp() public {
        // expLane = new ExpressLaneAuction();
        // counter.setNumber(0);
    }

    // function test_Increment() public {
    //     counter.increment();
    //     assertEq(counter.number(), 1);
    // }

    // function testFuzz_SetNumber(uint256 x) public {
    //     counter.setNumber(x);
    //     assertEq(counter.number(), x);
    // }
}
