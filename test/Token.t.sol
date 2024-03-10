//SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {SecuredOnBlockChainToken} from "../src/OnSecuredToken.sol";
import {IUniswapV2Router02} from "../src/interfaces/IUniswap.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "forge-std/Test.sol";

contract SOBTest is Test {
    SecuredOnBlockChainToken sob;
    IUniswapV2Router02 router;
    address pair;

    address excluded = makeAddr("excluded");
    address limitEx = makeAddr("limitEx");
    address regular = makeAddr("regular");
    address dev = makeAddr("dev");
    address mkt = makeAddr("mkt");

    function setUp() public {
        vm.deal(excluded, 10 ether);
        vm.deal(limitEx, 10 ether);
        vm.deal(regular, 10 ether);

        sob = new SecuredOnBlockChainToken(address(this), mkt, dev);

        router = IUniswapV2Router02(sob.router());
        pair = sob.uniswapV2Pair();

        sob.updateWalletExcludeStatus(excluded, true);
        sob.updateWalletLimitStatus(limitEx, true);
    }

    function test_initial() public {
        assertEq(sob.owner(), address(this));
        assertEq(sob.marketingWallet(), mkt);
        assertEq(sob.devWallet(), dev);

        assertEq(sob.isExcludedFromFee(excluded), true);
        assertEq(sob.isExcludedFromFee(limitEx), false);
        assertEq(sob.isExcludedFromLimit(limitEx), true);
        assertEq(sob.isExcludedFromLimit(excluded), false);

        assertEq(sob.totalSupply(), 1_000_000 gwei);
        assertEq(sob.balanceOf(address(this)), 1_000_000 gwei);

        assertEq(sob.isPair(pair), true);
    }

    function test_maxTx() public {
        uint overLimit = 100_000 gwei;
        sob.transfer(limitEx, overLimit);
        sob.transfer(excluded, overLimit);
        assertEq(sob.balanceOf(limitEx), overLimit);

        vm.prank(excluded);
        vm.expectRevert();
        sob.transfer(regular, overLimit);

        vm.prank(limitEx);
        sob.transfer(regular, overLimit);

        assertEq(sob.balanceOf(regular), overLimit);
        assertEq(sob.balanceOf(limitEx), 0);
        assertEq(sob.balanceOf(excluded), overLimit);
    }

    function test_addLiquidity() public {
        uint liquidityAmount = sob.totalSupply() / 4;
        sob.approve(address(router), liquidityAmount);

        router.addLiquidityETH{value: 1 ether}(
            address(sob),
            liquidityAmount,
            liquidityAmount,
            1 ether,
            address(this),
            block.timestamp
        );

        assertGt(IERC20(pair).totalSupply(), 0);
    }

    modifier wLiq() {
        uint liquidityAmount = sob.totalSupply() / 4;
        sob.approve(address(router), liquidityAmount);

        router.addLiquidityETH{value: 1 ether}(
            address(sob),
            liquidityAmount,
            liquidityAmount,
            1 ether,
            address(this),
            block.timestamp
        );
        _;
    }

    function test_noTaxBuy() public wLiq {
        uint buyAmount = 0.03 ether;

        address[] memory path = new address[](2);
        path[0] = router.WETH();
        path[1] = address(sob);

        vm.prank(regular);
        router.swapExactETHForTokensSupportingFeeOnTransferTokens{
            value: buyAmount
        }(0, path, regular, block.timestamp);

        assertGt(sob.balanceOf(regular), 0);
        assertEq(sob.balanceOf(address(sob)), 0);
    }

    function test_noTaxSell() public wLiq {
        uint sellAmount = 1000 gwei;

        sob.transfer(regular, sellAmount);

        address[] memory path = new address[](2);
        path[0] = address(sob);
        path[1] = router.WETH();

        uint prevBal = regular.balance;

        vm.startPrank(regular);
        sob.approve(address(router), sellAmount);
        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            sellAmount,
            0,
            path,
            regular,
            block.timestamp
        );

        vm.stopPrank();

        assertEq(sob.balanceOf(regular), 0);
        assertGt(regular.balance, prevBal);
        assertEq(sob.balanceOf(address(sob)), 0);
    }

    modifier wTax() {
        sob.updateBuyFee(5);
        sob.updateSellFee(5);
        _;
    }

    function test_taxBuy() public wLiq wTax {
        uint buyAmount = 0.03 ether;

        address[] memory path = new address[](2);
        path[0] = router.WETH();
        path[1] = address(sob);

        vm.prank(regular);
        router.swapExactETHForTokensSupportingFeeOnTransferTokens{
            value: buyAmount
        }(0, path, regular, block.timestamp);

        uint regBal = sob.balanceOf(regular);
        uint tokenBal = sob.balanceOf(address(sob));

        assertGt(regBal, 0);
        assertGt(tokenBal, 0);

        uint percent = (regBal * 100) / (regBal + tokenBal);
        assertTrue(percent >= 93);
        console.log(
            "regBal: %s  tokenBal: %s  percent: %s",
            regBal,
            tokenBal,
            percent
        );
    }

    function test_taxSell() public wLiq wTax {
        uint sellAmount = 1000 gwei;

        sob.transfer(regular, sellAmount);

        address[] memory path = new address[](2);
        path[0] = address(sob);
        path[1] = router.WETH();

        vm.startPrank(regular);
        sob.approve(address(router), sellAmount);
        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            sellAmount,
            0,
            path,
            regular,
            block.timestamp
        );

        vm.stopPrank();

        assertEq(sob.balanceOf(address(sob)), 50 gwei);
    }

    function test_autoSwap() public wLiq wTax {
        uint sellAmount = 4_000 gwei;
        sob.transfer(limitEx, sellAmount);

        address[] memory path = new address[](2);
        path[0] = address(sob);
        path[1] = router.WETH();

        vm.startPrank(limitEx);
        sob.approve(address(router), sellAmount);
        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            sellAmount,
            0,
            path,
            limitEx,
            block.timestamp
        );
        vm.stopPrank();

        // this should trigger an autoswap
        sob.transfer(regular, 1 gwei);

        assertGt(dev.balance, 0);
        assertGt(mkt.balance, 0);
    }
}
