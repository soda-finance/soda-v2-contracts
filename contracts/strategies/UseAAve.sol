// SPDX-License-Identifier: WTFPL
pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IStrategy.sol";
import "../SodaMaster.sol";

interface UniswapRouter {
    function swapExactTokensForTokens(uint, uint, address[] calldata, address, uint) external;
}

interface ILendingPool {
    function deposit(address _reserve, uint256 _amount, uint16 _referralCode) external payable;
    function core() external returns(address);
}

interface IAToken {
    function redeem(uint256 _amount) external;
    function balanceOf(address _user) external view returns(uint256);
    function principalBalanceOf(address _user) external view returns(uint256);
}

// This contract is owned by Timelock.
// What it does is simple: deposit usdc to ForTube, and wait for SodaPool's command.
contract UseAAve is IStrategy, Ownable {
    using SafeMath for uint256;

    uint256 constant PER_SHARE_SIZE = 1e12;

    SodaMaster public sodaMaster;

    ILendingPool public lendingPool;

    struct PoolInfo {
        IERC20 token;
        IAToken aToken;
        uint256 balance;
    }

    mapping(address => PoolInfo) public poolMap;  // By vault.
    mapping(address => uint256) private valuePerShare;  // By vault.

    constructor(SodaMaster _sodaMaster,
                ILendingPool _lendingPool) public {
        sodaMaster = _sodaMaster;
        lendingPool = _lendingPool;
    }

    function approve(IERC20 _token) external onlyOwner {
        _token.approve(sodaMaster.pool(), type(uint256).max);
        _token.approve(lendingPool.core(), type(uint256).max);
    }

    function setPoolInfo(
        address _vault,
        IERC20 _token,
        IAToken _aToken
    ) external onlyOwner {
        poolMap[_vault].token = _token;
        poolMap[_vault].aToken = _aToken;
        _token.approve(sodaMaster.pool(), type(uint256).max);
        _token.approve(lendingPool.core(), type(uint256).max);
    }

    function getValuePerShare(address _vault) external view override returns(uint256) {
        return valuePerShare[_vault];
    }

    function pendingValuePerShare(address _vault) external view override returns (uint256) {
        uint256 shareAmount = IERC20(_vault).totalSupply();
        if (shareAmount == 0) {
            return 0;
        }

        uint256 amount = poolMap[_vault].aToken.balanceOf(address(this)).sub(poolMap[_vault].balance);
        return amount.mul(PER_SHARE_SIZE).div(shareAmount);
    }

    function _update(address _vault, uint256 _tokenAmountDelta) internal {
        uint256 shareAmount = IERC20(_vault).totalSupply();
        if (shareAmount > 0) {
            valuePerShare[_vault] = valuePerShare[_vault].add(
                _tokenAmountDelta.mul(PER_SHARE_SIZE).div(shareAmount));
        }
    }

    /**
     * @dev See {IStrategy-deposit}.
     */
    function deposit(address _vault, uint256 _amount) public override {
        require(sodaMaster.isVault(msg.sender), "sender not vault");

        uint256 tokenAmountBefore = poolMap[_vault].balance;
        lendingPool.deposit(address(poolMap[_vault].token), _amount, 0);
        uint256 tokenAmountAfter = poolMap[_vault].aToken.balanceOf(address(this));
        poolMap[_vault].balance = tokenAmountAfter;

        _update(_vault, tokenAmountAfter.sub(tokenAmountBefore).sub(_amount));
    }

    /**
     * @dev See {IStrategy-claim}.
     */
    function claim(address _vault) external override {
        require(sodaMaster.isVault(msg.sender), "sender not vault");

        uint256 tokenAmountBefore = poolMap[_vault].balance;
        uint256 tokenAmountAfter = poolMap[_vault].aToken.balanceOf(address(this));
        poolMap[_vault].balance = tokenAmountAfter;

        _update(_vault, tokenAmountAfter.sub(tokenAmountBefore));
    }

    /**
     * @dev See {IStrategy-withdraw}.
     */
    function withdraw(address _vault, uint256 _amount) external override {
        require(sodaMaster.isVault(msg.sender), "sender not vault");

        uint256 tokenAmountBefore = poolMap[_vault].balance;
        poolMap[_vault].aToken.redeem(_amount);
        uint256 tokenAmountAfter = poolMap[_vault].aToken.balanceOf(address(this));
        poolMap[_vault].balance = tokenAmountAfter;

        _update(_vault, tokenAmountAfter.sub(tokenAmountBefore.sub(_amount)));
    }

    /**
     * @dev See {IStrategy-getTargetToken}.
     */
    function getTargetToken(address _vault) external view override returns(address) {
        return address(poolMap[_vault].token);
    }
}
