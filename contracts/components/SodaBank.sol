// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../tokens/SodaMade.sol";
import "../tokens/SodaVault.sol";
import "../calculators/ICalculator.sol";
import "../SodaMaster.sol";

// SodaBank produces SodaMade assets by locking user's vault assets.
// This contract is owned by Timelock.
contract SodaBank is Ownable {
    using SafeMath for uint256;

    // Info of each pool.
    struct PoolInfo {
        SodaMade made;
        SodaVault vault;           // Address of vault contract.
        ICalculator calculator;
    }

    // PoolInfo by poolId.
    mapping(uint256 => PoolInfo) public poolMap;

    // Info of each loan.
    struct LoanInfo {
        uint256 poolId;  // Corresponding asset of the loan.
        uint256 loanId;  // LoanId of the loan.
    }

    // Loans of each user.
    mapping (address => LoanInfo[]) public loanList;

    SodaMaster public sodaMaster;

    event Borrow(address indexed user, uint256 indexed index, uint256 indexed poolId, uint256 amount);
    event PayBackInFull(address indexed user, uint256 indexed index);
    event PayBackPartially(address indexed user, uint256 indexed index, uint256 amount);
    event CollectDebt(address indexed user, uint256 indexed poolId, uint256 loanId);

    constructor(
        SodaMaster _sodaMaster
    ) public {
        sodaMaster = _sodaMaster;
    }

    // Set pool info.
    function setPoolInfo(uint256 _poolId, SodaMade _made, SodaVault _vault, ICalculator _calculator) public onlyOwner {
        poolMap[_poolId].made = _made;
        poolMap[_poolId].vault = _vault;
        poolMap[_poolId].calculator = _calculator;
    }

    // Return length of address loan
    function getLoanListLength(address _who) external view returns (uint256) {
        return loanList[_who].length;
    }

    // Lend made Tokens to create a new loan by locking vault.
    function borrow(uint256 _poodId, uint256 _amount) external {
        PoolInfo storage pool = poolMap[_poodId];
        require(address(pool.calculator) != address(0), "no calculator");

        uint256 loanId = pool.calculator.getNextLoanId();
        pool.calculator.borrow(msg.sender, _amount);
        uint256 lockedAmount = pool.calculator.getLoanLockedAmount(loanId);
        // Locks in vault.
        pool.vault.lockByBank(msg.sender, lockedAmount);

        // Give user SodaMade tokens.
        pool.made.mint(msg.sender, _amount);

        // Records the loan.
        LoanInfo memory loanInfo;
        loanInfo.poolId = _poodId;
        loanInfo.loanId = loanId;
        loanList[msg.sender].push(loanInfo);

        emit Borrow(msg.sender, loanList[msg.sender].length - 1, _poodId, _amount);
    }

    // Pay back to a loan fully.
    function payBackInFull(uint256 _index) external {
        require(_index < loanList[msg.sender].length, "getTotalLoan: index out of range");
        PoolInfo storage pool = poolMap[loanList[msg.sender][_index].poolId];
        require(address(pool.calculator) != address(0), "no calculator");

        uint256 loanId = loanList[msg.sender][_index].loanId;
        uint256 lockedAmount = pool.calculator.getLoanLockedAmount(loanId);
        uint256 principal = pool.calculator.getLoanPrincipal(loanId);
        uint256 interest = pool.calculator.getLoanInterest(loanId);
        // Burn principal.
        pool.made.burnFrom(msg.sender, principal);
        // Transfer interest to sodaRevenue.
        pool.made.transferFrom(msg.sender, sodaMaster.revenue(), interest);
        pool.calculator.payBackInFull(loanId);
        // Unlocks in vault.
        pool.vault.unlockByBank(msg.sender, lockedAmount);

        emit PayBackInFull(msg.sender, _index);
    }

    // Pay back to a loan partially.
    function payBackPartially(uint256 _index, uint256 _amount) external {
        require(_index < loanList[msg.sender].length, "getTotalLoan: index out of range");
        PoolInfo storage pool = poolMap[loanList[msg.sender][_index].poolId];
        require(address(pool.calculator) != address(0), "no calculator");

        uint256 loanId = loanList[msg.sender][_index].loanId;
        uint256 lockedAmount = pool.calculator.getLoanLockedAmount(loanId);
        uint256 principal = pool.calculator.getLoanPrincipal(loanId);
        uint256 interest = pool.calculator.getLoanInterest(loanId);

        require(_amount <= principal + interest, "Paid too much");

        uint256 paidPrincipal = _amount.mul(principal).div(principal + interest);
        uint256 paidInterest = _amount.sub(paidPrincipal);

        // Burn principal.
        pool.made.burnFrom(msg.sender, paidPrincipal);
        // Transfer interest to sodaRevenue.
        pool.made.transferFrom(msg.sender, sodaMaster.revenue(), paidInterest);
        // Recalculate.
        uint256 amountToUnlock = pool.calculator.payBackPartially(loanId, paidPrincipal);
        // Unlocks in vault.
        pool.vault.unlockByBank(msg.sender, amountToUnlock);

        emit PayBackPartially(msg.sender, _index, _amount);
    }

    // Collect debt if someone defaults. Collector keeps half of the profit.
    function collectDebt(uint256 _poolId, uint256 _loanId) external {
        PoolInfo storage pool = poolMap[_poolId];
        require(address(pool.calculator) != address(0), "no calculator");

        address loanCreator = pool.calculator.getLoanCreator(_loanId);
        uint256 principal = pool.calculator.getLoanPrincipal(_loanId);
        uint256 interest = pool.calculator.getLoanInterest(_loanId);
        uint256 extra = pool.calculator.getLoanExtra(_loanId);
        uint256 lockedAmount = pool.calculator.getLoanLockedAmount(_loanId);

        // Pay principal + interest + extra.
        // Burn principal.
        pool.made.burnFrom(msg.sender, principal);
        // Transfer interest and extra to sodaRevenue.
        pool.made.transferFrom(msg.sender, sodaMaster.revenue(), interest + extra);

        // Clear the loan.
        pool.calculator.collectDebt(_loanId);
        // Unlocks in vault.
        pool.vault.unlockByBank(loanCreator, lockedAmount);

        pool.vault.transferByBank(loanCreator, msg.sender, lockedAmount);

        emit CollectDebt(msg.sender, _poolId, _loanId);
    }
}
