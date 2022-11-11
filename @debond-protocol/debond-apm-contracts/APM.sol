pragma solidity ^0.8.0;

// SPDX-License-Identifier: apache 2.0
/*
    Copyright 2022 Debond Protocol <info@debond.org>
    Licensed under the Apache License, Version 2.0 (the "License");
    you may not use this file except in compliance with the License.
    You may obtain a copy of the License at
    http://www.apache.org/licenses/LICENSE-2.0
    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.
*/
import "./interfaces/IAPM.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@debond-protocol/debond-governance-contracts/utils/ExecutableOwnable.sol";
import "@debond-protocol/debond-token-contracts/interfaces/IDebondToken.sol";


contract APM is IAPM, ExecutableOwnable {
    using SafeERC20 for IERC20;

    address bankAddress;
    address stakingDebondAddress;

    mapping(address => uint256) internal totalReserve;
    mapping(address => uint256) internal totalEntries; //Entries : virtual liquidity pool
    mapping(address => mapping(address => uint256)) entries;

    constructor(address _executableAddress, address _bankAddress, address _stakingDebondAddress) ExecutableOwnable(_executableAddress)
    {
        bankAddress = _bankAddress;
        stakingDebondAddress = _stakingDebondAddress;
    }

    modifier onlyBank() {
        require(msg.sender == bankAddress, "APM: Not Authorised");
        _;
    }

    function updateBankAddress(address _bankAddress) external onlyExecutable {
        require(_bankAddress != address(0), "APM: Address 0 given for Bank!");
        bankAddress = _bankAddress;
    }

    function _getReservesOneToken(
        address tokenA, //token we want to know reserve
        address tokenB //pool associated
    ) private view returns (uint256 reserveA) {
        uint256 totalEntriesA = totalEntries[tokenA]; //gas saving
        if (totalEntriesA != 0) {
            uint256 entriesA = entries[tokenA][tokenB];
            reserveA = (entriesA * totalReserve[tokenA]) / totalEntriesA; //use mulDiv?
        }
    }

    /**
    * @notice know the reserve for a pair (see white paper to know how it works)
    * @param tokenA address of tokenA
    * @param tokenB address of tokenB
    **/
    function getReserves(address tokenA, address tokenB)
        public
        view
        override
        returns (uint256 reserveA, uint256 reserveB)
    {
        (reserveA, reserveB) = (
            _getReservesOneToken(tokenA, tokenB),
            _getReservesOneToken(tokenB, tokenA)
        );
    }

    function _updateWhenAddLiquidityOneToken(
        uint256 amountA,
        address tokenA,
        address tokenB
    ) private {

        uint256 totalReserveA = totalReserve[tokenA]; //todo : should be put totalreserve[tokenA] or IERC20(tokenA).balanceOf(address(this))? No : totalReserve[A] is old reserve while balanceOf is current reserve

        if (totalReserveA != 0) {
            //update entries
            uint256 oldEntriesA = entries[tokenA][tokenB]; //for updating total Entries
            uint256 totalEntriesA = totalEntries[tokenA]; //save gas

            uint256 entriesA = _entriesAfterAddingLiq(
                oldEntriesA,
                amountA,
                totalEntriesA,
                totalReserveA
            );
            entries[tokenA][tokenB] = entriesA;

            //update total Entries
            totalEntries[tokenA] =
                totalEntriesA -
                oldEntriesA +
                entriesA;
        } else {
            entries[tokenA][tokenB] = amountA;
            totalEntries[tokenA] = amountA;
        }
        sync(tokenA);
        //totalReserve[tokenA] = totalReserveA + amountA;  //we replaced this by sync
    }

    /**
    * @notice update reserves when a pair is added in the apm
    * @param amountA amount of tokenA
    * @param amountB amount of tokenB
    * @param tokenA address of tokenA
    * @param tokenB address of tokenB
    **/
    function updateWhenAddLiquidity(
        uint256 amountA,
        uint256 amountB,
        address tokenA,
        address tokenB
    ) external onlyBank {
        _updateWhenAddLiquidityOneToken(amountA, tokenA, tokenB);
        _updateWhenAddLiquidityOneToken(amountB, tokenB, tokenA);
    }

    function _updateWhenRemoveLiquidityOneToken(
        uint256 amountA,
        address tokenA,
        address tokenB
    ) private {

        uint256 totalReserveA = totalReserve[tokenA]; //gas saving


        //update Entries
        uint256 oldEntriesA = entries[tokenA][tokenB]; //for updating total entries
        uint256 totalEntriesA = totalEntries[tokenA]; //save gas

        uint256 entriesA = _entriesAfterRemovingLiq(
            oldEntriesA,
            amountA,
            totalEntriesA,
            totalReserveA
        );
        entries[tokenA][tokenB] = entriesA;

        //update total Entries
        totalEntries[tokenA] =
            totalEntriesA -
            oldEntriesA +
            entriesA;

        //update total Reserve
        //totalReserve[tokenA] = totalReserveA -  amountA; //we replaced this by sync
        sync(tokenA);
    }

    /**
    * @notice update reserves when one token is removed from apm
    * @param amount amount of token
    * @param token address of token
    **/
    function _updateWhenRemoveLiquidity(
        uint256 amount, //amountA is the amount of tokenA removed in total pool reserve ( so not the total amount of tokenA in total pool reserve)
        address token
    ) private {
        totalReserve[token] -= amount;
    }

    /**
    * @notice update reserves when one token is swapped for another one
    * @param amountAAdded amount of tokenA the user gives to the apm
    * @param amountBWithdrawn amount of tokenB the user gets from the apm
    * @param tokenA address of tokenA
    * @param tokenB address of tokenB
    **/
    function _updateWhenSwap(
        uint256 amountAAdded, //amountA is the amount of tokenA swapped in this pool ( so not the total amount of tokenA in this pool after the swap)
        uint256 amountBWithdrawn,
        address tokenA,
        address tokenB
    ) private {
        _updateWhenAddLiquidityOneToken(amountAAdded, tokenA, tokenB);
        _updateWhenRemoveLiquidityOneToken(amountBWithdrawn, tokenB, tokenA);
    }

    function _entriesAfterAddingLiq(
        uint256 oldEntries,
        uint256 amount,
        uint256 totalEntriesToken,
        uint256 totalReserveToken
    ) private pure returns (uint256 newEntries) {
        newEntries =
            oldEntries +
            (amount * totalEntriesToken) /
            totalReserveToken;
    }

    function _entriesAfterRemovingLiq(
        uint256 oldEntries,
        uint256 amount,
        uint256 totalEntriesToken,
        uint256 totalReserveToken
    ) private pure returns (uint256 newEntries) {
        newEntries =
            oldEntries -
            (amount * totalEntriesToken) /
            totalReserveToken;
    }

    uint256 private unlocked = 1; //reentracy


    /**
    * @notice swap one token for another. This is a low level functions which should be called trough the BankRouter
    * @param amount0Out amount of token0 the user gives to the apm
    * @param amount1Out amount of token1 the user gets back from the apm
    * @param token0 address of token0
    * @param token1 address of token1
    * @param to address to send token1
    */
    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address token0,
        address token1,
        address to
    ) external {
        //no need to have both amount >0, there is always one equals to 0 (according to yu).
        require(unlocked == 1, "APM swap: LOCKED");
        unlocked = 0;
        require(
            (amount0Out != 0 && amount1Out == 0) ||
            (amount0Out == 0 && amount1Out != 0),
            "APM swap: INSUFFICIENT_OUTPUT_AMOUNT_Or_Both_output >0"
        );
        require(to != token0 && to != token1, "APM swap: INVALID_TO"); // do we really need this?
        (uint256 _reserve0, uint256 _reserve1) = getReserves(token0, token1); // gas savings
        require(
            amount0Out < _reserve0 && amount1Out < _reserve1,
            "APM swap: INSUFFICIENT_LIQUIDITY"
        );

        if (amount0Out == 0) IERC20(token1).safeTransfer(to, amount1Out);
        else IERC20(token0).safeTransfer(to, amount0Out);

         uint totalReserve0 = IERC20(token0).balanceOf(address(this));
         uint totalReserve1 = IERC20(token1).balanceOf(address(this));
         uint currentReserve0 =
            _reserve0 +
            totalReserve0 -
            totalReserve[token0]; // should be >= 0
         uint currentReserve1 =
            _reserve1 +
            totalReserve1 -
            totalReserve[token1];
        require(
            currentReserve0 * currentReserve1 >=
            _reserve0 * _reserve1,
            "APM swap: K"
        );

         uint amount0In = currentReserve0 > _reserve0 - amount0Out
            ? currentReserve0 - (_reserve0 - amount0Out)
            : 0;
         uint amount1In = currentReserve1 > _reserve1 - amount1Out
            ? currentReserve1 - (_reserve1 - amount1Out)
            : 0;
        require(
            amount0In > 0 || amount1In > 0,
            "APM swap: INSUFFICIENT_INPUT_AMOUNT"
        );
        if (amount0Out == 0) {
            _updateWhenSwap(amount0In, amount1Out, token0, token1);
        } else {
            _updateWhenSwap(amount1In, amount0Out, token1, token0);
        }
        unlocked = 1;
    }

    // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    function _getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 amountOut) {
        require(amountIn > 0, "APM: INSUFFICIENT_INPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "APM: INSUFFICIENT_LIQUIDITY");
        uint256 numerator = amountIn * reserveOut;
        uint256 denominator = reserveIn + amountIn;
        amountOut = numerator / denominator;
    }

    function getAmountsOut(uint256 amountIn, address[] memory path)
        external
        view
        returns (uint256[] memory amounts)
    {
        require(path.length >= 2, "APM: INVALID_PATH");
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        for (uint256 i; i < path.length - 1; i++) {
            (uint256 reserveIn, uint256 reserveOut) = getReserves(
                path[i],
                path[i + 1]
            );
            amounts[i + 1] = _getAmountOut(amounts[i], reserveIn, reserveOut);
        }
    }

    
    // force reserves to match balances
    function sync(address tokenAddress) public {
        totalReserve[tokenAddress] = IERC20(tokenAddress).balanceOf(address(this));
    }

    function removeLiquidity(
        address _to,
        address tokenAddress,
        uint256 amount
    ) external {
        require(msg.sender == bankAddress || msg.sender == stakingDebondAddress, "APM: Not Authorised");
        // transfer
        IERC20(tokenAddress).safeTransfer(_to, amount);
        // update getReserves
        _updateWhenRemoveLiquidity(amount, tokenAddress);
    }

    function removeLiquidityInsidePool(
        address _to,
        address tokenA,
        address tokenB,
        uint256 amountA
    ) external {
        IERC20(tokenA).safeTransfer(_to, amountA);
        updateWhenRemoveLiquidityOneToken(amountA, tokenA, tokenB);
    }

    function updateWhenRemoveLiquidityOneToken(uint amountA, address tokenA, address tokenB) public {
        require(msg.sender == bankAddress, "APM: Not Authorised");
        _updateWhenRemoveLiquidityOneToken(amountA, tokenA, tokenB);
    }
}
