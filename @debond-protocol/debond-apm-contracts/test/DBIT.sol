pragma solidity ^0.8.0;

// SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


contract DBIT is ERC20, Ownable {


    constructor() ERC20("D/BIT TOKEN", "D/BIT") {}

    function mint(address _to, uint256 _amount) external {
        _mint(_to, _amount);
    }

    function supplyCollateralised() external pure returns (uint) {
        return 0;
    }

    function burn(address _from, uint amount) external {
        _burn(_from, amount);
    }

}
