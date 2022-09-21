// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";


library Erc20Utils {
    function addTokensToContract(
        IERC20 _token,
        address payable _payerAddress,
        uint _amount
    ) internal {
        require(_amount > 0, "Amount must be greater than 0");
        require(_token.transferFrom(_payerAddress, address(this), _amount), "Contract fails to receive payment");
    }

    function moveTokensFromContract(
        IERC20 _token,
        address payable _payeeAddress,
        uint _amount
    ) internal {
        require(_amount > 0, "Amount must be greater than 0");
        require(_token.transfer(_payeeAddress, _amount), "Token transfer to payer fails");
    }
}
