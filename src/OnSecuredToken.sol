//SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IUniswapV2Pair, IUniswapV2Router02, IUniswapV2Factory} from "./interfaces/IUniswap.sol";

error SOB__InvalidWalletAddress(address invalidWallet);
error SOB__InvalidPairAddress(address invalidPair);
error SOB__InvalidRouterAddress(address invalidRouter);
error SOB__CannotTransfer(uint8 code);
error SOB__InvalidFeeAmount(uint256 fee, uint256 maxFee);
error SOB__InvalidSplit(uint8 errorTotal);
error SOB__InvalidMaxTxAmount();
error SOB__MaxTx();

// code == 0: Cannot transfer 0 ETH
// code == 1: Cannot transfer receiver address failed

contract SecuredOnBlockChainToken is ERC20, Ownable {
    uint256 public constant FEE_BASIS = 100;
    address private constant DEAD = 0x000000000000000000000000000000000000dEaD;

    mapping(address => bool) public isExcludedFromFee;
    mapping(address => bool) public isExcludedFromLimit;
    mapping(address => bool) public isPair;
    uint256 public feeOnBuy = 0;
    uint256 public feeOnSell = 0;
    uint256 public swapThreshold;
    uint256 public maxTxAmount;

    IUniswapV2Router02 public router =
        IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    address public immutable WETH;
    address public marketingWallet;
    address public devWallet;
    address public uniswapV2Pair;

    uint8 public marketingPercent = 8;
    uint8 public devPercent = 2;
    uint8 public totalPercent = 10;
    bool private swapping;

    //------------------------------------------------------------------------
    //---------------------- Events ---------------------
    event MarketingWalletUpdate(
        address indexed previousMarketingWallet,
        address indexed newMarketingWallet
    );
    event DevWalletUpdate(
        address indexed previousDevWallet,
        address indexed newDevWallet
    );
    event PairUpdate(address indexed previousPair, address indexed newPair);
    event RouterUpdate(
        address indexed previousRouter,
        address indexed newRouter
    );
    event InvalidTransfer(address indexed to, uint256 ETHvalue);
    event UpdateExcludedStatus(address indexed wallet, bool status);
    event UpdateLimitStatus(address indexed wallet, bool status);
    event UpdateBuyFee(uint256 prevFee, uint256 fee);
    event UpdateSellFee(uint256 prevFee, uint256 fee);
    event UpdateThreshold(uint256 prevThreshold, uint256 threshold);
    event UpdateFeeSplit(uint8 mktShares, uint8 devShares, uint8 totalShares);
    event MaxTxUpdate(uint256 prevMaxTx, uint256 newMaxTx);

    //------------------------------------------------------------------------
    //-------------------- Modifiers --------------------

    constructor(
        address _ownerWallet,
        address _mktWallet,
        address _devWallet
    ) ERC20("Secured On Blockchain", "SOB") Ownable(_ownerWallet) {
        // Total Supply 1M gwei. 9 decimals
        super._update(address(0), _ownerWallet, 1_000_000 gwei);
        maxTxAmount = totalSupply() / 100; // 1% of total supply
        marketingWallet = _mktWallet;
        devWallet = _devWallet;
        IUniswapV2Factory factory = IUniswapV2Factory(router.factory());
        WETH = router.WETH();
        uniswapV2Pair = factory.createPair(address(this), WETH);
        isPair[uniswapV2Pair] = true;
        swapThreshold = totalSupply() / 5_000;
        // Exclude From Fees
        isExcludedFromFee[_ownerWallet] = true;
        isExcludedFromFee[address(this)] = true;
        // Exclude From Limits
        isExcludedFromLimit[_ownerWallet] = true;
        isExcludedFromLimit[address(this)] = true;
        isExcludedFromLimit[DEAD] = true;
        isExcludedFromLimit[uniswapV2Pair] = true;
        _approve(address(this), address(router), type(uint256).max);
    }

    //------------------------------------------------------------------------
    //-------------------- External/Public functions -------------------------
    //------------------------------------------------------------------------
    receive() external payable {}

    fallback() external payable {}

    //-------------------- onlyOwner functions --------------------

    /**
     * @notice Update the Marketing Wallet
     * @param _newMarketingWallet The new Marketing Wallet address
     * @dev Only the owner can update the Marketing Wallet and the new wallet should not be the zero address or the contract address or the current marketing address
     */
    function updateMarketingWallet(
        address _newMarketingWallet
    ) external onlyOwner {
        if (
            _newMarketingWallet == address(0) ||
            _newMarketingWallet == address(this) ||
            _newMarketingWallet == marketingWallet
        ) revert SOB__InvalidWalletAddress(_newMarketingWallet);
        emit MarketingWalletUpdate(marketingWallet, _newMarketingWallet);
        marketingWallet = _newMarketingWallet;
    }

    /**
     * @notice Update the Dev Wallet
     * @param _devWallet The new Dev Wallet address
     * @dev Only the owner can update the Dev Wallet and the new wallet should not be the zero address or the contract address or the current marketing address
     */
    function updateDevWallet(address _devWallet) external onlyOwner {
        if (
            _devWallet == address(0) ||
            _devWallet == address(this) ||
            _devWallet == devWallet
        ) revert SOB__InvalidWalletAddress(_devWallet);
        emit DevWalletUpdate(devWallet, _devWallet);
        devWallet = _devWallet;
    }

    /**
     * @notice Update the Main Pair to swap for ETH
     * @param _uniswapV2Pair The new UniswapV2Pair address
     * @dev Only the owner can update the Pair and the new wallet should not be the zero address or the contract address or the current address
     *  or the current pair address or be an invalid V2pair
     */
    function updateV2Pair(address _uniswapV2Pair) external onlyOwner {
        address token0 = IUniswapV2Pair(_uniswapV2Pair).token0();
        address token1 = IUniswapV2Pair(_uniswapV2Pair).token1();
        if (token0 != address(this) && token1 != address(this)) {
            revert SOB__InvalidWalletAddress(_uniswapV2Pair);
        }
        emit PairUpdate(uniswapV2Pair, _uniswapV2Pair);
        uniswapV2Pair = _uniswapV2Pair;
    }

    /**
     * @notice Update the UniswapV2Router
     * @param _uniswapV2Router The new UniswapV2Router address
     * @dev Only the owner can update the Router and the new wallet should not be the zero address or the contract address or the current address
     *  or the current pair address or be an invalid v2 router
     */
    function updateV2Router(address _uniswapV2Router) external onlyOwner {
        if (
            _uniswapV2Router == address(0) ||
            _uniswapV2Router == address(this) ||
            _uniswapV2Router == address(router) ||
            IUniswapV2Router02(_uniswapV2Router).WETH() != WETH
        ) revert SOB__InvalidRouterAddress(_uniswapV2Router);
        emit RouterUpdate(address(router), _uniswapV2Router);
        router = IUniswapV2Router02(_uniswapV2Router);
    }

    /**
     * @notice Add a new pair to the list of pairs
     * @param pair The address of the pair to add
     */
    function addPair(address pair) external onlyOwner {
        if (pair == address(0) || pair == address(this))
            revert SOB__InvalidPairAddress(pair);
        isPair[pair] = true;
        isExcludedFromLimit[pair] = true;
    }

    /**
     * @notice Update the exclusion status of a wallet from fees
     * @param wallet The address to update exclusion status from fees
     * @param status The new exclusion status
     */
    function updateWalletExcludeStatus(
        address wallet,
        bool status
    ) external onlyOwner {
        isExcludedFromFee[wallet] = status;
        emit UpdateExcludedStatus(wallet, status);
    }

    /**
     * @notice Update the limit exclusion of a wallet
     * @param wallet The address to update exclusion status from limits
     * @param status The new limit exclusion status
     * @dev Wallet to update cannot be the pair or the router
     */
    function updateWalletLimitStatus(
        address wallet,
        bool status
    ) external onlyOwner {
        if (wallet == uniswapV2Pair || wallet == address(router))
            revert SOB__InvalidWalletAddress(wallet);
        isExcludedFromLimit[wallet] = status;
        emit UpdateLimitStatus(wallet, status);
    }

    /**
     * @notice Swap currently held fees for ETH and distribute to mkt and dev wallets
     */
    function manualSwapFees() external onlyOwner {
        _swapFees();
    }

    /**
     * @notice update the fee taken on BUY transactions
     * @param _fee The new fee to apply
     * @dev The fee cannot be more than 25%
     */
    function updateBuyFee(uint256 _fee) external onlyOwner {
        if (_fee > 25) revert SOB__InvalidFeeAmount(_fee, 25);
        emit UpdateBuyFee(feeOnBuy, _fee);
        feeOnBuy = _fee;
    }

    /**
     * @notice update the fee taken on BUY transactions
     * @param _fee The new fee to apply
     * @dev The fee cannot be more than 25%
     */
    function updateSellFee(uint256 _fee) external onlyOwner {
        if (_fee > 25) revert SOB__InvalidFeeAmount(_fee, 25);
        emit UpdateSellFee(feeOnSell, _fee);
        feeOnSell = _fee;
    }

    /**
     * @notice update the amount to collect before triggering a conversion to ETH
     * @param _threshold The new threshold to apply
     */
    function updateSwapThreshold(uint256 _threshold) external onlyOwner {
        emit UpdateThreshold(swapThreshold, _threshold);
        swapThreshold = _threshold;
    }

    /**
     * Updates the Max Tokens a tx can make in a single TX
     * @param _maxTx The new maxTx to apply
     */
    function updateMaxTx(uint256 _maxTx) external onlyOwner {
        if (_maxTx < totalSupply() / 100) revert SOB__InvalidMaxTxAmount();
        emit MaxTxUpdate(maxTxAmount, _maxTx);
        maxTxAmount = _maxTx;
    }

    /**
     * @notice update the fee split between marketing and dev wallets
     * @param _mktShares The new marketing shares
     * @param _devShares The new dev shares
     * @dev totalPercent cannot be 0. Shares do not change the fees, only the split
     */
    function updateFeeSplit(
        uint8 _mktShares,
        uint8 _devShares
    ) external onlyOwner {
        if (_mktShares + _devShares == 0) revert SOB__InvalidSplit(0);
        totalPercent = _mktShares + _devShares;
        marketingPercent = _mktShares;
        devPercent = _devShares;
    }

    /**
     * @notice remove any ETH from the contract to DEV wallet
     */
    function extractETH() external {
        uint amount = address(this).balance;
        if (amount == 0) revert SOB__CannotTransfer(0);
        (bool success, ) = devWallet.call{value: address(this).balance}("");
        if (!success) revert SOB__CannotTransfer(1);
    }

    /**
     * @notice remove any ERC20 token from the contract to DEV wallet
     * @param token The address of the ERC20 token to extract from this contract
     */
    function extractERC20(address token) external {
        if (token == address(this) || token == address(0))
            revert SOB__InvalidWalletAddress(token);
        ERC20 erc = ERC20(token);
        uint256 balance = erc.balanceOf(address(this));
        if (balance == 0) revert SOB__CannotTransfer(0);
        erc.transfer(devWallet, balance);
    }

    //------------------------------------------------------------------------
    //-------------------- Internal/Private functions ------------------------
    //------------------------------------------------------------------------
    /**
     * @notice Update the balances of the sender and receiver
     * @param from The sender address
     * @param to The receiver address
     * @param value The amount to transfer
     * @dev This function is called by the transfer and transferFrom functions
     * and it updates the balances of the sender and receiver and also takes care of the fees
     * if the threshold is reached it swaps for ETH and splits the fees
     */
    function _update(
        address from,
        address to,
        uint256 value
    ) internal override {
        bool isBuy = isPair[from];
        bool isSell = isPair[to];

        // Check Max TX limits
        if (value > maxTxAmount) {
            if (isBuy && !isExcludedFromLimit[to]) revert SOB__MaxTx();
            else if (isSell && !isExcludedFromLimit[from]) revert SOB__MaxTx();
            else {
                if (!isExcludedFromLimit[from]) revert SOB__MaxTx();
            }
        }

        bool canSwap = !swapping &&
            !isSell &&
            balanceOf(address(this)) >= swapThreshold;

        if (canSwap) {
            _swapFees();
        }

        bool takeFee = !swapping &&
            !(isExcludedFromFee[from] || isExcludedFromFee[to]);
        uint fee = 0;
        if (takeFee) {
            if (isBuy) {
                fee = (value * feeOnBuy) / FEE_BASIS;
            } else if (isSell) {
                fee = (value * feeOnSell) / FEE_BASIS;
            }
            super._update(from, address(this), fee);
            value -= fee;
        }

        super._update(from, to, value);
    }

    /**
     * @notice swap the fees collected in SOB for ETH and send to the marketing and dev wallets respectively
     */
    function _swapFees() private {
        swapping = true;
        uint256 totalFees = balanceOf(address(this));

        // Swapping
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = WETH;

        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            totalFees,
            0,
            path,
            address(this),
            block.timestamp
        );

        uint256 ethBalance = address(this).balance;
        if (totalPercent > 0) {
            uint256 marketingFee = (ethBalance * marketingPercent) /
                totalPercent;
            uint256 devFee = (ethBalance * devPercent) / totalPercent;
            (bool success, ) = marketingWallet.call{value: marketingFee}("");
            if (!success) emit InvalidTransfer(marketingWallet, marketingFee);
            (success, ) = devWallet.call{value: devFee}("");
            if (!success) emit InvalidTransfer(marketingWallet, marketingFee);
        }
        swapping = false;
    }

    //-------------------- External/Public VIEW functions --------------------
    function decimals() public pure override returns (uint8) {
        return 9;
    }
    //-------------------- Internal/Private VIEW functions -------------------
}
